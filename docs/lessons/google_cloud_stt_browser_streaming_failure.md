# Google Cloud STT Browser Streaming Failure - Lessons Learned

**Date**: 2026-01-29  
**Project**: teisutis  
**Status**: Resolved - Migrated to batch API  
**Applies To**: Any project attempting browser → Google Cloud STT V2 streaming

---

## TL;DR

**Problem**: Browser MediaRecorder → Google Cloud STT V2 streaming API doesn't work reliably, even from Chrome to Google's own service.

**Root Cause**: Browser MediaRecorder outputs WebM container **fragments** (not complete files), which Google Cloud STT V2 streaming API cannot parse consistently, even with `AutoDetectDecodingConfig`.

**Solution**: Use batch API (`recognize()`) instead of streaming API (`streaming_recognize()`). Trade +1.5-3s latency for 66% code reduction and reliable transcription.

**Lesson**: Don't attempt real-time browser → Google Cloud STT streaming. It's a rabbit hole.

---

## The Problem Journey

### Attempt 1: WEBM_OPUS Explicit Config
- **Goal**: Stream WebM/Opus chunks (100ms intervals) directly to Google STT
- **Result**: 0 transcription results, no errors
- **Issue**: WebM fragments lack proper container headers

### Attempt 2: OGG_OPUS Preference
- **Goal**: Use Ogg container (designed for streaming)
- **Result**: Browser doesn't support Ogg Opus, still sends WebM
- **Issue**: Format fallback not solving container fragmentation

### Attempt 3: AutoDetectDecodingConfig
- **Goal**: Let Google auto-detect format from chunk headers
- **Result**: 0 transcription results, no errors
- **Issue**: Auto-detection doesn't handle incomplete containers

### Attempt 4: V2 API Protocol Fix
- **Goal**: Fix request structure (recognizer+config in first request only)
- **Result**: Protocol correct, but still 0 results
- **Issue**: Protocol wasn't the problem; data format was

### Final Solution: Batch API
- **Goal**: Send complete audio blob after recording stops
- **Result**: ✅ Working transcription, Lithuanian accuracy confirmed
- **Trade-off**: +1.5-3s latency (acceptable for chat use case)

---

## Technical Details

### Why Browser Streaming Fails

**MediaRecorder Behavior**:
```javascript
// Start with 100ms timeslice for low latency
mediaRecorder.start(100);

// Each chunk is a FRAGMENT, not a complete file:
// - Missing EBML container header (only first chunk has partial header)
// - Missing codec initialization data in subsequent chunks
// - No proper frame boundaries
// - Google STT expects complete container structure per chunk
```

**Google Cloud STT V2 Streaming Expectations**:
- Each chunk should be decodable independently (or)
- Codec initialization data must be sent once and persist across chunks (but)
- WebM fragments from MediaRecorder don't satisfy either requirement

**Why Even `AutoDetectDecodingConfig` Fails**:
- Auto-detection analyzes container headers
- WebM fragments after first chunk have NO container headers
- Detection fails silently, returns empty results

---

## Architecture Comparison

### Streaming API (Failed)
```
Browser MediaRecorder (100ms chunks)
  ↓ WebM fragments
Django Channels Consumer
  ↓ Base64 chunks
Google Cloud STT streaming_recognize()
  ↓ Empty results iterator
0 transcriptions
```

**Complexity**: 762 lines, threading, queues, generators, state management

### Batch API (Working)
```
Browser MediaRecorder (complete recording)
  ↓ Complete WebM blob
Django Channels Consumer
  ↓ Base64 complete audio
Google Cloud STT recognize()
  ↓ Single response
Final transcript
```

**Complexity**: 260 lines, single request/response, no threading

---

## Implementation: Batch API Solution

### Backend (`stt_service.py`)
```python
def transcribe_complete_audio(
    self,
    audio_data: bytes,
    language_codes: Optional[List[str]] = None,
    session_id: Optional[str] = None,
) -> str:
    """Synchronous batch transcription - wrap with database_sync_to_async."""
    
    config = cloud_speech.RecognitionConfig(
        auto_decoding_config=cloud_speech.AutoDetectDecodingConfig(),
        language_codes=language_codes or ["lt-LT", "en-US", "ru-RU"],
        model="long",  # Batch API model
    )
    
    request = cloud_speech.RecognizeRequest(
        recognizer=self.recognizer_path,
        config=config,
        content=audio_data,
    )
    
    response = self.client.recognize(request=request)
    
    transcript = ""
    for result in response.results:
        if result.alternatives:
            transcript += result.alternatives[0].transcript + " "
    
    return transcript.strip()
```

### Frontend (`voice.js`)
```javascript
// Record complete audio (no timeslice)
this.mediaRecorder.start();

// Collect chunks
this.mediaRecorder.ondataavailable = (event) => {
    if (event.data.size > 0) {
        this.audioChunks.push(event.data);
    }
};

// Send complete blob on stop
this.mediaRecorder.onstop = () => {
    const completeBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
    
    const reader = new FileReader();
    reader.onloadend = () => {
        const base64Data = reader.result.split(',')[1];
        this._sendMessage({
            type: 'audio_complete',
            audio_data: base64Data,
        });
    };
    reader.readAsDataURL(completeBlob);
};
```

### WebSocket Protocol
```json
// 1. Start recording (optional)
{ "type": "start_recording", "language_codes": ["lt-LT"] }

// 2. Send complete audio (required)
{ "type": "audio_complete", "audio_data": "base64_webm_blob" }

// 3. Receive result
{ "type": "transcription_complete", "text": "Transcribed text", "session_id": "xyz" }
```

---

## Performance Characteristics

### Latency Breakdown (5-second recording)
| Phase | Duration | Notes |
|-------|----------|-------|
| Recording | 5s | User speaking |
| Frontend processing | 100-200ms | Blob creation, base64 encoding |
| Network upload | 100-500ms | ~50-200KB audio |
| Google Cloud API | 1-2s | Batch processing |
| Network download | 50-100ms | Transcript text |
| **Total** | **6.5-8s** | vs 5s for streaming |

**Trade-off**: +1.5-3s latency for 66% code reduction and reliability

### Audio Size (WebM/Opus)
- **Encoding rate**: ~10-15 KB/second
- **5-second recording**: ~50-75 KB
- **10-second recording**: ~100-150 KB
- **Max duration (10MB limit)**: ~600-700 seconds (10-12 minutes)

---

## Code Metrics

| Metric | Before (Streaming) | After (Batch) | Reduction |
|--------|-------------------|---------------|-----------|
| `stt_service.py` | 762 lines | 260 lines | **66%** |
| `consumers.py` (STT) | ~600 lines | ~200 lines | **67%** |
| **Total removed** | | | **~900 lines** |

### Complexity Eliminated
- ❌ Threading (`threading.Thread`)
- ❌ Queues (`Queue`, `get()`, `put()`)
- ❌ Generators (`yield`, async iterators)
- ❌ State management (`is_streaming`, `last_sent_transcript`)
- ❌ Background tasks (`asyncio.create_task`)
- ❌ Connection lifecycle (start, stop, cleanup)
- ❌ Duplicate detection
- ❌ Chunk boundary handling

---

## When to Use Each Approach

### Use Batch API ✅
- **Chat applications** (short recordings, 5-30 seconds)
- **Voice commands** (1-5 seconds)
- **Transcription accuracy > latency**
- **Cost optimization important**
- **Simpler maintenance preferred**

### Use Streaming API ⚠️
- **Live captioning** (real-time display required)
- **Long recordings** (>1 minute, interim results needed)
- **Server-side audio sources** (not browser)
- **Custom audio pipelines** (control over container format)

### Never Use Browser Streaming ❌
- Browser MediaRecorder → Google Cloud STT V2 streaming
- Why: Unreliable due to container fragmentation
- Even Google's own Chrome can't stream to Google's own STT reliably

---

## Cost Comparison

### Streaming API
- **Billing**: Per 15-second interval of **connection time**
- **Overhead**: Connection setup, keep-alive, teardown
- **Example**: 5-second recording may bill for 15 seconds due to connection overhead

### Batch API
- **Billing**: Per 15-second interval of **audio duration**
- **Overhead**: None
- **Example**: 5-second recording bills for 15 seconds (minimum), but no connection overhead

**Result**: Batch API typically 10-30% cheaper for short recordings

---

## Testing Insights

### What Doesn't Work
❌ Saving WebM chunks from MediaRecorder and combining them  
❌ Using `ffmpeg` to "fix" WebM fragments  
❌ Explicit WEBM_OPUS encoding with streaming API  
❌ OGG_OPUS preference (browser falls back to WebM)  
❌ AutoDetectDecodingConfig with streaming chunks  

### What Works
✅ Complete WebM blob to batch API  
✅ AutoDetectDecodingConfig with batch API  
✅ Model: `long` for batch, `chirp_2` for streaming (if you must)  
✅ Lithuanian, English, Russian multi-language detection  
✅ Automatic punctuation in batch mode  

---

## Key Takeaways

1. **Don't fight browser MediaRecorder**: It outputs fragments by design
2. **Google STT streaming isn't browser-friendly**: Even with auto-detection
3. **Batch API is simpler**: 66% less code, no threading, no edge cases
4. **Latency trade-off is acceptable**: +1.5-3s for massive complexity reduction
5. **Cost reduction bonus**: Lower API costs, simpler infrastructure
6. **Production validated**: Working in teisutis for Lithuanian transcription

---

## References

- **Teisutis Implementation**: `teisutis/web/teisutis_ai/stt_service.py` (commit b196857)
- **Frontend Implementation**: `teisutis/web/teisutis_ai/static/teisutis_ai/js/voice.js`
- **Migration Artefact**: `teisutis/docs/artefacts/by-agent/backend/stt_batch_api_2026-01-29.md`
- **Google Cloud STT V2 Batch API**: https://cloud.google.com/speech-to-text/v2/docs/sync-recognize
- **MediaRecorder API**: https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder

---

## Conclusion

Browser → Google Cloud STT V2 streaming is a trap. The combination of:
- Browser MediaRecorder's fragmented output
- Google STT's container parsing requirements
- Lack of proper codec initialization in chunks

...makes reliable streaming nearly impossible, even with auto-detection.

**The pragmatic solution**: Accept +1.5-3s latency, use batch API, enjoy 66% less code and working transcription.

**For future projects**: Start with batch API. Only consider streaming if you control the audio source (server-side) or have validated codec initialization handling.
