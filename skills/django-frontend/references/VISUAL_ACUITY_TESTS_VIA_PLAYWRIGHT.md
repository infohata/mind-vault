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

`mcr.microsoft.com/playwright/python:vX.Y.Z-noble` — chromium + firefox + webkit pre-installed. Self-built off `python:3.14-slim` + `playwright install-deps` costs ~150MB of apt you'd maintain.

MS image is Python 3.12 today; web image may be 3.14:

- **No PEP 695 syntax** in shared e2e code (`type Alias =`, `def f[T]`). Use `typing.TypeVar`.
- **Pin playwright pip lib to image version exactly.** Drift → `Executable doesn't exist at /ms-playwright/...`.
- **Audit transitive 3.13+-only wheels.** `pydub` → `audioop-lts` (audioop removed in 3.13; `audioop-lts` ships only ≥3.13 wheels) fails install on 3.12 image. Filter at Dockerfile if e2e doesn't need that path.

### 3. Playwright image needs full Django ORM

Session-cookie minting imports `django.contrib.sessions.backends.db.SessionStore` → pulls Django + django-tenants + full ORM. Install full `requirements-web.txt` in the playwright image; subset breaks at fixture import.

### 4. Three Django opt-outs for live-DB e2e

```python
# conftest.py
@pytest.fixture(scope="session")
def django_db_setup(django_db_blocker):
    django_db_blocker.unblock()  # bypass pytest-django test-DB lifecycle

@pytest.fixture(scope="session", autouse=True)
def django_initialized(django_db_setup) -> None:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "<project>.settings")
    os.environ.setdefault("DJANGO_ALLOW_ASYNC_UNSAFE", "true")
    import django
    django.setup()
```

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
