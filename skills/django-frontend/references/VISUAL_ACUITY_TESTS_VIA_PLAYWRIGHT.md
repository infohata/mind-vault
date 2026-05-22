# Visual-acuity tests via Playwright

## When to write a Playwright test (and when NOT to)

Render-and-assert tests cover **fragment shape** — given URL X, fragment Y
renders correctly. They cannot cover **integration shape** — given user-action
sequence A→B→C, surface Y reaches state Z. The integration-shape gap is where
"the right code path wasn't invoked at all" bugs hide: walker firings,
state-machine transitions, popstate reconciliation, client-side reactivity
meeting server-driven HTMX swaps.

Write a Playwright test when:

- The assertion depends on a **sequence of user actions** (click → fill →
  click → reload), not a single request.
- The bug only manifests when **client JS reactivity meets a server-driven
  HTMX swap** (e.g. Alpine `x-text` binding vs walker-refreshed fragment).
- The surface **changes with viewport** (mobile vs desktop semantics — `:hover`
  fails on touch, dropdown click-toggle, mobile sheet behaviour).
- The assertion depends on **URL state after `history.pushState` / popstate**
  (preview-drawer stack tokens, bookmark roundtrip, deep-link restore).

Skip Playwright (use render-and-assert instead) when:

- "Given this URL + context, fragment X renders Y."
- Template logic with no JS.
- Django view response shape.

## The methodology rule

> Any UI element whose state is driven by client-side reactivity + server-driven
> swaps needs a Playwright case exercising both branches end-to-end. New
> shell-extending IDEAs add their own Playwright case to the suite as they ship.

The rule fires during `/plan` (acceptance criteria), `/work` (test author),
and `/wrap` (suite hygiene). Render-and-assert stays as the cheap fragment-shape
coverage layer; Playwright is **additive**, not a replacement.

## Bootstrap recipe — what the first-suite stand-up learned the hard way

The fixtures layer (Host injection, schema seeding, cookie pre-baking) lives in
[`MULTI_TENANT_PLAYWRIGHT.md`](MULTI_TENANT_PLAYWRIGHT.md). Wait recipes live in
[`HTMX_ALPINE_WAITS.md`](HTMX_ALPINE_WAITS.md). The pieces below are the
**docker + django bootstrap mechanics** that surfaced as load-bearing during
the first-suite stand-up — none of them were obvious from the fixtures
references alone.

### 1. Don't conflate dev-host and dev-test dependencies

Project's `requirements-dev.txt` is host-only tooling (linters, bandit,
pyflakes). Playwright + pytest-playwright go in a **separate**
`requirements-e2e.txt` that only the playwright dev-test image installs.
Putting them in `requirements-dev.txt` is a false-economy: any host dev who
`pip install -r requirements-dev.txt`s pulls 50MB of Python package without the
browser binaries, then can't use it anyway.

### 2. Use MS's upstream image, accept the Python-version gap

`mcr.microsoft.com/playwright/python:vX.Y.Z-noble` ships chromium + firefox +
webkit pre-installed at known-compatible versions. Building your own off
`python:3.14-slim` and running `playwright install-deps && playwright install`
costs ~150MB of apt installs you maintain instead of MS.

The version gap (MS image is Python 3.12 today; project's web image is 3.14):

- **Avoid PEP 695-only syntax** in shared e2e code: `type Alias = ...`,
  `def f[T](x: T) -> T`. Use `from typing import TypeVar` instead.
- **Pin playwright pip lib version to match the image version exactly**.
  Drift triggers `Executable doesn't exist at /ms-playwright/...` — pip is
  newer than the binary set. Both bump together.
- **Audit transitive deps that pin Python 3.13+ wheels**. `pydub` now declares
  `audioop-lts` as a hard dep (audioop was removed from stdlib in 3.13).
  `audioop-lts` only ships wheels for ≥3.13, so installing it on the
  Python-3.12 playwright image fails. Filter such deps out at the Dockerfile
  level if your e2e tests don't exercise the audio path — document the
  exclusion in the Dockerfile prose.

### 3. The playwright image needs the full Django ORM, not a subset

Programmatic session-cookie minting (the load-bearing login fixture pattern in
[`MULTI_TENANT_PLAYWRIGHT.md`](MULTI_TENANT_PLAYWRIGHT.md)) imports
`django.contrib.sessions.backends.db.SessionStore`, which pulls Django +
django-tenants + the entire ORM. A "minimal subset" image install is a false
economy — it breaks at fixture import time, not at build time. Install the full
`requirements-web.txt` in the playwright image too. The ~200MB cost is paid in
a dev-only image.

### 4. Three Django opt-outs the e2e suite needs

Live-dev-DB Playwright differs from pytest-django's managed-test-DB model.
Three boilerplate hooks unblock it; without all three, fixtures fail at
session boot:

```python
# conftest.py
@pytest.fixture(scope="session")
def django_db_setup(django_db_blocker):
    """Bypass pytest-django's test-DB lifecycle. e2e hits the live dev DB."""
    django_db_blocker.unblock()


@pytest.fixture(scope="session", autouse=True)
def django_initialized(django_db_setup) -> None:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "<project>.settings")
    # pytest-playwright owns the asyncio loop; Django would otherwise refuse
    # sync ORM calls from within a running loop.
    os.environ.setdefault("DJANGO_ALLOW_ASYNC_UNSAFE", "true")
    import django
    django.setup()
```

The `DJANGO_ALLOW_ASYNC_UNSAFE` is honest — fixtures run sequentially per
test, so there's no actual race. We're acknowledging the context, not
running unsafe concurrency.

### 5. Routing — Host header tricks fight chromium harder than expected

Chromium **refuses Host-header overrides** even via Playwright's
`extra_http_headers` (`net::ERR_INVALID_ARGUMENT`). This rules out the
"connect to nginx via compose DNS but pretend to be `tenant.example.com`"
pattern that other tools accept.

Working pattern for django-tenants:

1. Pick a hostname **resolvable by docker** (the nginx service hostname, e.g.
   `nginx`).
2. Add it to `ALLOWED_HOSTS` (Django enforces ALLOWED_HOSTS even with
   `DEBUG=True` when set explicitly; the TenantMiddleware catches
   `DisallowedHost` and returns 404 with empty body — easy to misdiagnose).
3. Add it as a non-primary `Domain` row to your test tenant. The primary
   domain stays whatever your dev hostname is (e.g. `localhost`); this is
   purely additive.
4. Set `PLAYWRIGHT_BASE_URL=http://<hostname>`. Cookie domain matches the URL
   host. Browser connects naturally, django-tenants routes via the Domain row.

Don't try `extra_hosts: ['localhost:<nginx-ip>']` to override the container's
own `localhost`. Docker **appends** to `/etc/hosts`, doesn't override the
built-in `127.0.0.1 localhost`, and chromium's resolver picks the first match.

### 6. Compose service hygiene — don't volume-mount a file under a directory mount

```yaml
playwright:
  volumes:
    - ./web:/app
    - ./requirements-web.txt:/app/requirements-web.txt:ro   # ← trap
```

Docker bind-mounts the second line by creating an empty file at the host path
`./web/requirements-web.txt` (the target path under `/app`). That file shows
up untracked in your repo — a confusing artefact. **Bake the requirements file
into the image at build time and skip the runtime mount.** Re-mounting saves
no useful rebuild — pip would rerun against the same content anyway.

### 7. Language pinning for stable string assertions

The test user's profile language sets the default locale; the request also
honours `Accept-Language` and the language cookie. To keep string assertions
locale-stable:

- Set the test user's `language='en'` once via ORM. Permanent — it's a test
  user.
- Inject the `django_language=en` cookie at BrowserContext creation alongside
  the session cookie. Belt-and-braces; survives any future cookie purges.

## What's first-suite-worthy

The cost-benefit threshold for committing to a Playwright suite is **multiple
known regression classes**. Don't bootstrap for one bug. Aggregate ≥3
documented bugs of the integration-shape kind that escaped render-and-assert
coverage; the first-suite-day cost amortises across them.

Each first-suite test file:

- Targets one named regression class (e.g. `test_drawer_chrome_consistency.py`).
  Name the file by the bug it backstops; the test functions inside become the
  specific cases.
- Stays small (1–3 cases). Phase 2 isn't about exhaustive coverage; it's about
  proving the suite catches the documented class.
- Documents what it doesn't yet cover via `@pytest.mark.skip(reason=...)`
  for cases that need follow-up work (form payload mapping, click vs URL
  semantics). Skips with concrete reasons are healthier than missing tests —
  they advertise the gap.

## Out of scope for first-suite

- CI wiring (per-PR gate). Cost-benefit decision; needs runner-cost trade-offs
  + binary-cache strategy in its own decision space.
- Visual snapshot diffing (`page.screenshot()` + pixelmatch). Separate skill
  territory; see [`VISUAL_BASELINE_BUMPS.md`](VISUAL_BASELINE_BUMPS.md) for the
  hygiene rules when that lands.
- Multi-browser (firefox + webkit) gates. Gate on a chromium-pass regression
  that the other browsers catch; until then YAGNI.

## Provenance

Method: first-suite stand-up, 2026-05-22.
First-suite scope: 4 files (chrome consistency, filter survival, bookmark
roundtrip, mobile dropdown click-toggle), 10/13 active tests after
documented skips, total wall-time ~26s.
