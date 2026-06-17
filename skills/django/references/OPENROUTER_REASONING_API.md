# OpenRouter reasoning-token streaming

**Fires when** a backend streams from a reasoning-capable model through the OpenRouter API (Gemini "thinking", o-series, etc.) and wants to *request*, *read back*, *display*, or *persist* the model's reasoning ("thinking") tokens.

The integration is easy to get subtly wrong in four independent ways. All four below were observed live against a Gemini flash-lite model.

## 1. Requesting reasoning — the `reasoning` object

Reasoning is OFF/at-model-discretion unless you send a top-level `reasoning` object in the request body (alongside `model` / `messages` / `stream` / `tools`):

```python
data = {
    "model": model,
    "messages": messages,
    "stream": True,
    "reasoning": {"effort": "medium"},   # low | medium | high
    # ... tools, etc.
}
```

- `effort` (`low|medium|high`) maps to Gemini's `thinkingLevel` and is the **correct lever for Gemini 3.x**. `max_tokens` maps to `thinkingBudget` and is **imprecise on Gemini 3.x** — prefer `effort`.
- Send `effort` **OR** `max_tokens`, never both.
- `reasoning: {"enabled": true}` alone == medium effort.
- Effort is an **answer-quality** lever, not a readability/cost one: turning reasoning *up* on an already-acceptable cheap model is a quality improvement at no model-tier cost (the "cheap quality lever"). The token-cost increase is measurable; the answer-quality payoff needs a task-set eval, not a token count — don't lock effort low on cost grounds alone.
- Make it a settings knob (`AI_REASONING_EFFORT`, env-overridable), resolved per-request with a kwargs override.

## 2. Reading it back (streaming) — two channels, NO `delta.thinking`

OpenRouter normalises every provider's reasoning channel into the SSE delta as:

- `delta.reasoning` — a plain **string** (incremental).
- `delta.reasoning_details[]` — a **typed array**. Entry shapes:
  - `{"type": "reasoning.text", "text": "...", "summary": "..."}` → **human-readable** → display this.
  - `{"type": "reasoning.encrypted", "data"/"signature": "<base64>"}` → **opaque** signature for chain-of-thought continuity → **never display**.

There is **NO `delta.thinking` field** — a read-back that reads `delta['thinking']` is a silent no-op (reasoning never surfaces no matter what you requested). Guard every field (`.get`, a chunk may omit `text`).

## 3. The dual-channel dedup gotcha (the expensive one)

OpenRouter frequently **mirrors the same reasoning into BOTH** `delta.reasoning` (string) **and** `delta.reasoning_details[].text` **in the same delta**. If you yield/accumulate from both, the reasoning is **persisted/displayed doubled** (exact 2× duplication — the tell).

Fix: **prefer the typed array; fall back to the string only when `reasoning_details` is absent** for that delta.

```python
details = delta.get("reasoning_details", [])
if details:
    # surface the RAW array (readable + encrypted) for continuity (§5), and
    yield_raw_reasoning_details(details)
    for d in details:
        if isinstance(d, dict) and d.get("type") == "reasoning.text":
            text = d.get("text") or d.get("summary")
            if text:
                yield_display_thinking(text)
        # "reasoning.encrypted" → never displayed
else:
    s = delta.get("reasoning")            # string fallback ONLY when no array
    if s:
        yield_display_thinking(s)
```

## 4. Reasoning is ENCRYPTED on tool-CALL turns (partial display)

A reasoning-capable model can stream **readable** reasoning when it answers directly, but on any turn where it **fires a tool** it returns reasoning **only** as `reasoning.encrypted` (opaque). The trigger is a tool being **called**, not merely **provided** — a turn that provides tools but answers directly is still readable.

Consequences for a tool-using pipeline:
- **Display coverage is partial** by design — readable on direct-answer turns, blank on tool-calling turns. Not a bug; surface it as a product decision, not a failure.
- The encrypted blob is **still useful**: echo the raw `reasoning_details` (readable *and* encrypted) back on the assistant message across tool-call iterations so the model keeps its chain-of-thought through the tool round-trip. The round-trip is API-valid (the echoed details are accepted on the next request). Intra-response (in-memory tool loop) is the cheap win; persisting + replaying across separate turns is a heavier follow-up.

## 5. Accounting

Reasoning tokens land under `usage.completion_tokens_details.reasoning_tokens` — already folded into the normalised total, so no separate accounting is needed (don't double-count).

## De-risk before writing app code

A standalone probe (real key from `.env`, sweep effort, single- vs two-turn tool round-trip, separating readable vs encrypted) resolves §1–§4 at zero app cost and is worth writing first — the encrypted-on-tool-turns behaviour in particular is model-specific and decides whether the display feature is even achievable for your model.

Docs: `openrouter.ai/docs/guides/best-practices/reasoning-tokens`.

Pairs with: persisting the streamed reasoning across a mid-stream disconnect needs **instance state** on the consumer — see [`ASYNC_WEBSOCKET.md` → Persisting partial streamed content across a mid-stream disconnect](ASYNC_WEBSOCKET.md).
