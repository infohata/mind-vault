# Visual-acuity tests via Playwright

## When to write Playwright vs render-and-assert

Render-and-assert covers **fragment shape** (URL X → fragment Y). Playwright covers **integration shape** (action sequence A→B→C → state Z) — where "the right code path wasn't invoked at all" bugs hide.

Write Playwright when:

- Assertion depends on a **sequence of user actions** (click → fill → click → reload).
- Bug manifests only when **client JS reactivity meets a server-driven HTMX swap** (Alpine `x-text` vs walker-refreshed fragment).
- Surface **changes with viewport** (`:hover` fails on touch, dropdown click-toggle, mobile sheet).
- Assertion depends on **URL state after `pushState` / popstate** (drawer stack tokens, bookmark roundtrip).

Skip Playwright (render-and-assert instead) when: single-URL fragment shape; pure template logic; view response shape.

## Methodology rule

> Any UI element driven by client-side reactivity + server-driven swaps needs a Playwright case exercising both branches end-to-end. New shell-extending IDEAs add their own case as they ship.

Fires in `/plan` (acceptance criteria), `/work` (test author), `/wrap` (suite hygiene). Playwright is **additive** to render-and-assert, not a replacement.

## Bootstrap traps

Fixtures (Host injection, schema seeding, cookie pre-baking) → [`MULTI_TENANT_PLAYWRIGHT.md`](MULTI_TENANT_PLAYWRIGHT.md). Wait recipes → [`HTMX_ALPINE_WAITS.md`](HTMX_ALPINE_WAITS.md). Docker + django bootstrap mechanics below.

### 1. Separate `requirements-e2e.txt`

Don't put playwright + pytest-playwright in `requirements-dev.txt` (host tooling). Browser binaries live only in the playwright image; host install is dead weight.

### 2. Use MS upstream image, accept Python-version gap

`mcr.microsoft.com/playwright/python:vX.Y.Z-noble` — chromium + firefox + webkit pre-installed. Self-built off `python:<your-version>-slim` + `playwright install-deps` costs ~150MB of apt you'd maintain.

Your app image's Python is often newer than what MS ships on the Playwright image. Treat the gap as load-bearing:

- **No PEP 695-only syntax** in shared e2e code (`type Alias =`, `def f[T]`) if the Playwright image is older than 3.12. Use `typing.TypeVar`.
- **Pin playwright pip lib to image version exactly.** Drift → `Executable doesn't exist at /ms-playwright/...`.
- **Audit transitive deps that ship only on the newer Python.** Example: `pydub` → `audioop-lts` (audioop removed in 3.13; `audioop-lts` ships only ≥3.13 wheels) fails install on a 3.12 Playwright image. Filter at Dockerfile if e2e doesn't need that path.

### 3. Playwright image needs full Django ORM

Session-cookie minting imports `django.contrib.sessions.backends.db.SessionStore` → pulls Django + django-tenants + full ORM. Install full `requirements-web.txt` in the playwright image; subset breaks at fixture import.

### 4. Three Django opt-outs for live-DB e2e

```python
# conftest.py
import os
import pytest

@pytest.fixture(scope="session")
def django_db_setup(django_db_blocker):
    # bypass pytest-django test-DB lifecycle; e2e hits the live dev DB
    with django_db_blocker.unblock():
        yield

@pytest.fixture(scope="session", autouse=True)
def django_initialized(django_db_setup) -> None:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "<project>.settings")
    os.environ.setdefault("DJANGO_ALLOW_ASYNC_UNSAFE", "true")
    import django
    django.setup()
```

`django_db_blocker.unblock()` returns a context manager — the bare call form is a no-op (CM created but never entered). Always use `with ... :` + `yield` for session-scope unblock, matching the sibling [`MULTI_TENANT_PLAYWRIGHT.md`](MULTI_TENANT_PLAYWRIGHT.md) pattern.

`DJANGO_ALLOW_ASYNC_UNSAFE` is honest: pytest-playwright owns the asyncio loop, fixtures are sequential per test — no actual race.

### 5. Chromium refuses Host-header overrides

`extra_http_headers={'Host': ...}` → `net::ERR_INVALID_ARGUMENT`. The "connect to nginx, pretend to be tenant.example.com" pattern is dead.

django-tenants routing pattern:

1. Pick a docker-resolvable hostname (e.g. `nginx` service name).
2. Add to `ALLOWED_HOSTS`. Django enforces it even with `DEBUG=True` when set explicitly; TenantMiddleware catches `DisallowedHost` → 404 empty body (easy to misdiagnose).
3. Add as **non-primary `Domain` row** on the test tenant. Primary stays at dev hostname.
4. `PLAYWRIGHT_BASE_URL=http://<hostname>`. Cookie domain matches URL host.

Don't `extra_hosts: ['localhost:<ip>']` to override container `localhost` — docker appends to `/etc/hosts`, chromium picks the first `127.0.0.1 localhost`.

### 6. Don't bind-mount a file under a directory mount

```yaml
volumes:
  - ./web:/app
  - ./requirements-web.txt:/app/requirements-web.txt:ro   # ← trap
```

Docker creates empty `./web/requirements-web.txt` on host as the second mount's target — untracked artefact. Bake into image at build; pip wouldn't rerun anyway.

### 7. Language pinning for stable string assertions

- ORM-set test user `language='en'` once.
- Inject `django_language=en` cookie at BrowserContext creation alongside session cookie. Belt-and-braces.

### 8. Empty `STATIC_ROOT` ⇒ silently dead shell ⇒ mass timeouts (fresh volume)

nginx serves `/static/` from `STATIC_ROOT` (e.g. `alias /app/static/`). A **fresh
docker volume** (CI, a sprint-auto fresh-volume worktree, a new dev) has it empty
because `collectstatic` never ran — so every `/static/*.js` 404s, the Alpine/HTMX
shell never initialises, and **every interaction test (drawer open, dropdown,
deep-link) times out at `wait_for_selector`** while the non-JS tests (list
visibility, smoke) pass. The failure presents as "23/37 wholesale timeouts", which
looks like a harness/routing bug, not a missing build step.

Diagnose — set `host=` and `e2e_host=` for your stack first (the bare `<...>` form
would be parsed as shell redirection; `STATIC_ROOT` is a Django setting, so substitute
its concrete container path e.g. `/app/static`): `find /app/static -name '*.js' | wc -l` (zero?) and
`curl -s -o /dev/null -w '%{http_code}' -H "Host: $e2e_host" "http://$host/static/.../alpine.min.js"`
(404?). Fix — make the e2e entrypoint self-provision static, not just data:

```make
test-e2e:
	@docker compose up -d web nginx          # cold-stack guard
	@docker compose exec -T web python manage.py compile_scss      # build CSS
	@docker compose exec -T web python manage.py collectstatic --noinput
	@docker compose exec -T web python manage.py seed_e2e_tenant   # then data
	@docker compose --profile e2e run --rm playwright pytest -c /e2e/pytest.ini /e2e
```

Put the same `compile_scss` + `collectstatic` in the fresh-volume bootstrap hook
(sprint-auto `post_up_init` or equivalent) so a worktree's e2e is green without a
manual `make static`. **A reproducible e2e env provisions assets AND data — not
just data.**

### 9. `testpaths` must be absolute in the e2e `pytest.ini`

The e2e suite uses a **separate** `pytest.ini` (pytest-playwright plugin set differs
from the unit runner). If `testpaths = .` (relative) and someone runs a **flags-only**
invocation — `make test-e2e ARGS="-rs"` → `pytest -c /e2e/pytest.ini -rs` with **no
path** — collection falls back to `testpaths`, and `.` resolves against the
container's cwd (often `/app`, the source mount), pulling the **whole repo's unit
suite** into the e2e runner. Those tests then run against the **live DB** (the e2e
conftest overrides `django_db_setup` to use the running DB, no test-DB isolation) and
seed **stray tenants / rows** into it. Pin it absolute:

```ini
[pytest]
testpaths = /e2e        # NOT `.` — a flags-only ARGS would otherwise collect /app
```

An explicit CLI path still overrides `testpaths`, so single-file runs are unaffected;
only the bare/flags-only case is rescoped.

## First-suite-worthy threshold

Aggregate **≥3 documented integration-shape regressions** before bootstrapping. Don't bootstrap for one bug.

Each first-suite file:

- Targets one named regression class (e.g. `test_drawer_chrome_consistency.py`). File name = bug it backstops; functions = specific cases.
- Stays small (1–3 cases). Goal: prove the suite catches the class.
- Documents gaps via `@pytest.mark.skip(reason=...)`. Skips with concrete reasons > missing tests.

## Out of scope for first-suite

- CI per-PR gate (runner cost + binary-cache trade-off, own decision).
- Visual snapshot diffing → [`VISUAL_BASELINE_BUMPS.md`](VISUAL_BASELINE_BUMPS.md).
- Multi-browser gates. Chromium-only until firefox/webkit catch a regression chromium misses.
