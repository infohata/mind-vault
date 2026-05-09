# `ManifestStaticFilesStorage` — `collectstatic` is not enough, restart the app server

**When this fires**: production / staging deployments using `ManifestStaticFilesStorage` (the recommended Django production-mode static backend) where `collectstatic` is run as part of a deploy. The django SKILL.md body's section holds the firing-conditions stub; this reference holds the trapdoor walkthrough + Makefile target shape + symptom-shape diagnostic.

## The trapdoor

Django's `ManifestStaticFilesStorage` hash-fingerprints every URL: `theme.css` is served as `theme.dd52cbcbcdb6.css`, the hash changes on every content change, browsers auto-bust cache on every deploy. This is the right default. The trapdoor: the hash → URL mapping lives in `staticfiles.json`, which **the app server reads once at process startup and caches in-memory for the worker's lifetime**.

After `collectstatic` runs:

- ✅ new hashed file exists on disk
- ✅ `staticfiles.json` has the new entry
- ❌ **but** the running app server's `{% static %}` template tag still resolves to the OLD hash

Result: the user reloads, the rendered HTML still references the old `theme.<oldhash>.css`, the browser fetches that URL successfully (it's still on disk under the old hash), and the user sees no change no matter how hard they refresh. A "hard refresh" (Cmd/Ctrl+Shift+R) doesn't help — the URL emitted in HTML is the cached one, not the new one.

## The fix

```python
# settings.py — typical config
_STATICFILES_BACKEND = (
    'django.contrib.staticfiles.storage.ManifestStaticFilesStorage'
    if not DEBUG
    else 'django.contrib.staticfiles.storage.StaticFilesStorage'
)
STORAGES = {
    'staticfiles': {'BACKEND': _STATICFILES_BACKEND},
}
```

```makefile
# ❌ insufficient: leaves the app server emitting the old hashed URL
static:
	docker compose exec web python manage.py compile_scss
	docker compose exec web python manage.py collectstatic --noinput

# ✅ correct: pair the rebuild with a restart so {% static %} re-reads the manifest
static:
	docker compose exec web python manage.py compile_scss
	docker compose exec web python manage.py collectstatic --noinput

restart-web:
	docker compose restart web
```

The contract: every static-file change requires `make static && make restart-web` to land for users. This is the same shape as the env-var change-then-recreate pattern (`docker compose restart` doesn't pick up new ENV; you need `up -d --force-recreate`) — both are "the disk changed but the process is still on the old view."

## Symptom shape during debug

1. User reports "I refreshed and don't see my CSS / JS change."
2. Dev tools shows the page loaded `theme.<oldhash>.css`.
3. `curl https://example.com/static/.../theme.<oldhash>.css` returns the OLD content (because that's what's at the old-hash URL — the new content is at the new hash).
4. Restart the app server → next page load emits the NEW hashed URL → browser fetches NEW file → user sees the change.

Applies the same way to JS / image / font / any post-processed asset. Does not apply when `DEBUG=True` because `StaticFilesStorage` (no manifest) just resolves URLs to plain filenames at request time. The staging / production gotcha only.
