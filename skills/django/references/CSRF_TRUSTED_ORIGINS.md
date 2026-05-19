# CSRF_TRUSTED_ORIGINS — required in Django 4.0+ even for same-origin POSTs behind a proxy

Django 4.0+ added a stricter `Origin` header check to its CSRF middleware. Any POST whose `Origin` (or `Referer`, when `Origin` is missing) doesn't appear in `CSRF_TRUSTED_ORIGINS` is rejected with a 403 `Forbidden (Origin checking failed - <origin> does not match any trusted origins.)`.

This bites every new Django 4+ project that runs behind a reverse proxy (nginx, Traefik, Caddy) on a non-standard port: admin login, every form POST, every DRF write — all fail until the setting is populated. The setting wasn't required in older Django versions; it's easy to miss when scaffolding a new project.

## The trap

A fresh Django + Docker Compose stack with nginx in front, accessed via `http://localhost:<non-80-port>/admin/login/`:

1. User loads the login page (GET → 200, CSRF token cookie set).
2. User submits the form (POST → 403 `CSRF verification failed. Request aborted.`).
3. Django logs `Forbidden (Origin checking failed - http://localhost:8088 does not match any trusted origins.): /admin/login/`.

The browser's `Origin` header (`http://localhost:8088`) is compared against the server's own constructed origin (`request.scheme + "://" + request.get_host()`). When the proxy correctly forwards the Host header, these should match — but Django **still requires** the trusted-origins list to be populated for non-trivial cases, and "trivial" doesn't include "behind nginx on a non-standard port".

## The fix

Set `CSRF_TRUSTED_ORIGINS` in settings. For dev, derive from the same env var that drives the host port so the dev stack works on whatever port the host assigned (relevant when running parallel stacks or when the default port is taken):

```python
# settings/dev.py
import os

_HTTP_PORT = os.environ.get("HTTP_PORT", "80")
CSRF_TRUSTED_ORIGINS = [
    f"http://localhost:{_HTTP_PORT}",
    f"http://127.0.0.1:{_HTTP_PORT}",
]
```

For prod, read from env directly — comma-separated list of full origins (scheme included):

```python
# settings/prod.py
import os

CSRF_TRUSTED_ORIGINS = [
    o.strip() for o in os.environ.get("CSRF_TRUSTED_ORIGINS", "").split(",")
    if o.strip()
]
# Example .env value: CSRF_TRUSTED_ORIGINS=https://app.example.com,https://www.example.com
```

## Required shape of entries

- **Scheme is mandatory.** `localhost:8088` alone is rejected; must be `http://localhost:8088`.
- **Port matters when non-standard.** `http://localhost` won't match `http://localhost:8088`.
- **Wildcards are limited.** Subdomain wildcards work (`https://*.example.com`); host wildcards (`http://*:8088`) do not.
- **No path component.** `http://localhost:8088/admin/` is rejected; just `http://localhost:8088`.

## Bootstrap checklist for new Django 4+ projects

When scaffolding a new Django project that will run behind a proxy:

- [ ] Add `CSRF_TRUSTED_ORIGINS` to `dev.py` (derived from `HTTP_PORT` or hardcoded for the dev port).
- [ ] Add `CSRF_TRUSTED_ORIGINS` to `prod.py` (read from env; document the comma-separated format in `.env.template`).
- [ ] Smoke-test admin login end-to-end (`curl` for GET 200 + form CSRF token, then POST → expect 302, not 403). The HTTP-level smoke test that just hits `/` won't catch this — only a POST does.

## Related rules / skills

- `skills/django/SKILL.md` — overall Django backend conventions; bootstrap settings live here.
- `skills/deployment/SKILL.md` — when the proxy is part of a Docker Compose deployment.

## Diagnosis if it slips through

Symptom: any form POST returns 403 with "CSRF verification failed. Request aborted." in the browser. Run:

```bash
docker compose logs web 2>&1 | grep -iE "(csrf|origin checking)" | tail -5
```

Look for `Forbidden (Origin checking failed - <X> does not match any trusted origins.)`. The origin in the message is the value to add to `CSRF_TRUSTED_ORIGINS`.

---

**Last Updated**: 2026-05-19 — promoted from `tasker` IDEA-001 bootstrap. Caught during browser verification — every smoke test passed (curl GET / → 200, /admin/ → 302), but the first attempt to log into admin failed at the form POST. See `tasker/docs/archive/2026-05-DEVELOPMENT_LOG.md` for the precedent commit (`fix(settings): set CSRF_TRUSTED_ORIGINS in dev so admin login works`).
