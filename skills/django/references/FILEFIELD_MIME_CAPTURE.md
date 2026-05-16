# FileField MIME capture + registry drift guards

**When this fires**: file uploads (FileField / FormField) where the application categorises content by MIME type. Two recurring failure modes — `FieldFile.content_type` returning empty silently, and "one true list" registries drifting between consumer modules — both produce silent breakage that only surfaces in production. The django SKILL.md body's FileField-MIME section holds the firing-conditions stub; this reference holds the two failure modes + capture pattern + drift-guard assert.

## 1. `FieldFile.content_type` is always empty

`FieldFile.__getattr__` does **not** delegate `content_type` from the underlying `UploadedFile`, even on a freshly-assigned field before save. Code that relies on `getattr(att.file, "content_type", None)` to pick up a browser-supplied MIME silently falls through to extension-based guessing every time. Verify via shell:

```python
uf = SimpleUploadedFile("a.webm", b"x", content_type="audio/webm;codecs=opus")
att = MyModel(file=uf)
getattr(att.file, "content_type", "MISSING")       # → "MISSING" (surprise)
getattr(att.file.file, "content_type", "MISSING")  # → "audio/webm;codecs=opus"
```

Capture at upload into a DB column; read path prefers the column over re-read:

```python
class Attachment(models.Model):
    file = models.FileField(upload_to="attachments/")
    mime_type = models.CharField(max_length=127, blank=True, default="")

    def save(self, *args, **kwargs):
        if self.file and not self.mime_type:
            underlying = getattr(self.file, "file", None)
            if isinstance(underlying, UploadedFile):
                raw = getattr(underlying, "content_type", "") or ""
                if raw:
                    # Strip ``;codecs=…`` / ``;charset=…`` so re-reads get a clean MIME.
                    self.mime_type = raw.split(";", 1)[0].strip().lower()[:127]
        super().save(*args, **kwargs)
```

Backfill migration for legacy rows uses `mimetypes.guess_type(filename)`; pair with an explicit `migrations.RunPython.noop` reverse (the forward operation isn't safely reversible once new uploads start populating the column — blanking it on reverse would wipe correct data).

## 2. "One true list" enforced at import time

When the canonical set lives in module A (e.g. `core.attachment_types.AUDIO_MIMES`) and a parallel consumer module B carries a related dict (e.g. `{mime → pydub_format_hint}`), the two drift silently as new formats are added to A. Enforce coverage with a module-scope assert in B so any new format *has to* update both sides or the app physically won't start:

```python
from core.attachment_types import AUDIO_MIMES

_MIME_TO_FORMAT = {
    "audio/webm": "webm",
    "audio/mp4": "mp4",
    # …
}

_missing = AUDIO_MIMES - _MIME_TO_FORMAT.keys()
assert not _missing, (
    f"_MIME_TO_FORMAT is missing pydub mappings for AUDIO_MIMES: {sorted(_missing)}. "
    f"Update both sides when adding a format to the registry."
)
del _missing
```

The assert fires at import, which is what you want — startup fails before the first request, so the drift is discovered at `python manage.py check` rather than on the first user-facing audio upload.
