# HTMX + Alpine — Playwright wait recipes

How to wait for HTMX swaps to finish, Alpine components to be ready, and combined-state pages to settle, when driving them from headless Playwright. The wrong wait flakes intermittently (50%-pass tests, classic CI nightmare); the right wait is deterministic.

Load this reference when:

- Authoring Playwright tests against a Django + HTMX + Alpine surface.
- Diagnosing a flaky Playwright test that "works locally, fails on CI".
- Deciding between `wait_for_load_state`, `wait_for_function`, `wait_for_selector`, and `expect(...).to_have_count(0)` for a specific assertion seam.
- Pairing with [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) to test a behaviour the gotchas describe.

## 1. HTMX swap completion — the four-class wait

After an HTMX-triggered request (`hx-get`, `hx-post`, `hx-trigger`, etc.), the assertion target may need *any of four lifecycle classes* to clear before the DOM is settled. The canonical recipe (from htmx upstream discussion #2360):

```python
async def wait_htmx_settled(page):
    await expect(page.locator(
        '.htmx-request, .htmx-settling, .htmx-swapping, .htmx-added'
    )).to_have_count(0)
```

Why all four:

- `.htmx-request` — request in flight, applied to the triggering element while the network call is pending.
- `.htmx-swapping` — response received, content is being swapped into the target element.
- `.htmx-settling` — swap completed, settle phase running (initialiser scripts in the new content).
- `.htmx-added` — applied transiently to newly-added elements during the settle phase.

A test that only checks `.htmx-request` passes immediately after the network call but **before the swap**. A test that checks `.htmx-settling` passes after the swap but before initialisers fire. The four-class union catches all four phases.

### The trap: `htmx-settled` is not a real class

```python
# ❌ WRONG — this class does not exist in HTMX core.
await page.wait_for_function(
    "document.body.classList.contains('htmx-settled')"
)
```

`htmx-settled` would be the obvious symmetric pair to `htmx-settling`, but htmx core doesn't add it. A test that waits for `.htmx-settled` hangs indefinitely on any project that hasn't wired a custom hook to add the class. Use the four-class recipe.

## 2. Alpine readiness — `window.Alpine !== undefined`

Alpine boots on `DOMContentLoaded`. After a navigation or HTMX swap, Alpine binds to new `[x-data]` elements asynchronously:

```python
async def wait_alpine_ready(page):
    await page.wait_for_function('window.Alpine !== undefined')
```

This guarantees Alpine itself is loaded — but **NOT** that any specific `[x-data]` component has called its `init()`. To wait for a specific component:

```python
async def wait_alpine_component_ready(page, component_selector: str):
    await page.wait_for_function('window.Alpine !== undefined')
    # Wait for the component's reactive proxy to be populated:
    await page.wait_for_function(
        f'!!Alpine.$data(document.querySelector({component_selector!r}))'
    )
```

`Alpine.$data(el)` is the public API for reading a component's reactive state from outside Alpine; it returns `undefined` if Alpine hasn't bound yet, an object once `init()` has fired.

### The trap: don't probe `_x_dataStack`

```javascript
// ❌ WRONG — internal API, not stable across Alpine 3 minor versions.
document.querySelector('[x-data]')._x_dataStack
```

`_x_dataStack` is Alpine's internal storage and the leading underscore tells you it's unsupported. Use `Alpine.$data(el)`.

## 3. The HTMX-during-Alpine-init race

The interesting case: a page boots with Alpine `[x-data]` AND fires an `hx-trigger="load"` against an inner element on initial mount. The simple "Alpine ready" check passes during a partially-initialised DOM if the `load`-triggered swap is mid-flight. See [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) gotcha 5 for the underlying race.

Recipe — both checks, in sequence:

```python
async def wait_alpine_and_htmx_settled(page):
    await page.wait_for_function('window.Alpine !== undefined')
    await page.wait_for_load_state('networkidle')
    await expect(page.locator(
        '.htmx-request, .htmx-settling, .htmx-swapping, .htmx-added'
    )).to_have_count(0)
```

Order matters: `window.Alpine` first (otherwise `Alpine.$data` would `undefined`); `networkidle` second (resolves once HTMX `load`-trigger swaps complete); four-class union third (closes the settle window).

### `networkidle` is acceptable here

Playwright generally recommends against `wait_for_load_state('networkidle')` because it's brittle on pages with long-poll WebSockets or analytics beacons. For HTMX-on-load swaps specifically, the swap IS the network signal and `networkidle` is the cleanest seam to wait for it. If the project ships analytics beacons that fire periodically, replace `networkidle` with an explicit `wait_for_response(...)` that matches the HTMX swap URL.

## 4. Cotton components — no special wait needed

Cotton renders server-side. By the time the response HTML is in the DOM, Cotton is "done" — there's no client-side rendering phase to wait for. The waits above (HTMX swap completion, Alpine readiness) are the only seams that matter.

If a Cotton component contains an `[x-data]` directive, recipe 2 (Alpine ready) applies to its initialiser. If the Cotton component triggers an HTMX swap on init, recipe 3 (combined wait) applies.

## 5. Form submissions with HTMX boost

When a form has `hx-boost="true"` or `hx-post="..."`:

```python
async def submit_htmx_form(page, form_selector, **field_values):
    for name, value in field_values.items():
        await page.fill(f'{form_selector} [name="{name}"]', value)
    async with page.expect_response(lambda r: 'htmx' in r.request.headers.get('hx-request', '').lower()) as response_info:
        await page.click(f'{form_selector} [type="submit"]')
    response = await response_info.value
    assert response.status == 200
    await wait_htmx_settled(page)
```

`expect_response` with the `hx-request` header filter is more reliable than `wait_for_response` URL matching when the form's action URL is computed by the server (e.g. via reverse routing).

## 6. Toast / shell notification assertions

Shell-managed toast components (see [`SHELL_NOTIFICATIONS.md`](SHELL_NOTIFICATIONS.md)) render via `HX-Trigger: notify` headers. To assert a toast appeared:

```python
async def assert_toast(page, expected_text: str, kind: str = 'info'):
    toast = page.locator(f'.toast.toast-{kind}', has_text=expected_text)
    await expect(toast).to_be_visible(timeout=5_000)
```

Don't add a manual sleep before the assertion — Playwright's `expect(...).to_be_visible()` polls internally. The 5-second timeout is the cap; if the toast appears in 50ms, the assertion resolves in 50ms.

## 7. Modal open / close

For modal primitives (see [`MODAL_SYSTEM.md`](MODAL_SYSTEM.md)) opened via Alpine state:

```python
async def open_modal(page, trigger_selector: str, modal_selector: str):
    await page.click(trigger_selector)
    await wait_alpine_ready(page)  # Alpine animates the modal open
    await expect(page.locator(modal_selector)).to_be_visible()
    # If the modal contains [x-data] of its own, also wait for that:
    await page.wait_for_function(
        f'!!Alpine.$data(document.querySelector({modal_selector!r}))'
    )
```

For HTMX-loaded modal contents (modal shell renders, then HTMX fetches the inner template):

```python
async def open_htmx_modal(page, trigger_selector: str, modal_selector: str):
    await page.click(trigger_selector)
    await wait_alpine_ready(page)
    await expect(page.locator(modal_selector)).to_be_visible()
    await wait_htmx_settled(page)
    await expect(page.locator(f'{modal_selector} .modal-loading')).to_have_count(0)
```

## 8. Anti-patterns

| Pattern | Why it flakes | Replace with |
|---------|---------------|--------------|
| `await page.wait_for_timeout(500)` | Hardcoded delay; depends on host CPU + network | The recipe matching the actual seam (recipes 1-7) |
| `await page.wait_for_function("document.body.classList.contains('htmx-settled')")` | Class doesn't exist | Recipe 1 (four-class union) |
| `_x_dataStack` probe | Internal API, breaks on Alpine minor bumps | `Alpine.$data(el)` |
| `wait_for_load_state('domcontentloaded')` after HTMX swap | DOM was loaded before the swap; this resolves immediately | Recipe 1 |
| Manual `time.sleep()` in pytest fixture | Plain sync sleep blocks the event loop | `await page.wait_for_function(...)` |
| `wait_for_selector(...)` without `state='visible'` | Default state is `visible` — actually fine — but be explicit | `wait_for_selector(..., state='visible')` (or use `expect(...).to_be_visible()`) |
| Chained `assert` after `click()` with no wait | Playwright's auto-wait covers actions but not arbitrary assertions | Always pair an action with an explicit settle recipe |

## Related references

- [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) — the seven subtle gotchas; this file's recipes test for them.
- [`HTMX_PATTERNS.md`](HTMX_PATTERNS.md) — what HTMX's swap lifecycle looks like server-side.
- [`SHELL_NOTIFICATIONS.md`](SHELL_NOTIFICATIONS.md) — toast routing via HX-Trigger.
- [`MODAL_SYSTEM.md`](MODAL_SYSTEM.md) — Alpine-managed modal lifecycle.
- [`MULTI_TENANT_PLAYWRIGHT.md`](MULTI_TENANT_PLAYWRIGHT.md) — host-header + schema-seeding fixtures for django-tenants Playwright tests.

---

**Last Updated**: 2026-05-09
