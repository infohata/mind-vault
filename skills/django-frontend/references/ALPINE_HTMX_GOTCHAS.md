# Alpine 3 + HTMX bridge — three subtle gotchas

A trio of behaviours that bite when wiring Alpine 3 components to HTMX events (custom-event bridges, OOB swaps with Alpine state, deferred handler binding). Each is silent — no error, no warning — and only manifests after manual smoke or a corner-case input.

Load this reference when:
- Writing an `Alpine.data('foo', () => ({...}))` factory that owns event listeners.
- Bridging server events to client state via `HX-Trigger` headers.
- Deciding where to bind global handlers for HTMX events (`htmx:responseError`, `htmx:sendError`, `htmx:load`).

## 1. Alpine 3 auto-calls `init()` — never pair `x-init="init()"` with a factory `x-data`

When `x-data` is a factory call (`x-data="myFactory()"`), Alpine 3 invokes `init()` on the returned object **automatically**, once, after the component mounts. Adding an explicit `x-init="init()"` on top of that runs `init()` a **second** time on the same component.

The double-init silently registers any `addEventListener` calls twice, double-fires anything in init's body, and creates two listeners that both fire on every event. Symptoms:

- Toasts double-render from a single dispatched event.
- Form submissions get logged twice in your custom analytics hook.
- Console warnings appear twice ("malformed payload"), once per listener.

```html
<!-- WRONG: init() called twice -->
<div x-data="toastStack()" x-init="init()"> ... </div>

<!-- RIGHT: factory's auto-init is sufficient -->
<div x-data="toastStack()"> ... </div>

<!-- ALSO RIGHT: object x-data needs explicit x-init since it has no init() of its own -->
<div x-data="{ open: false }" x-init="open = window.matchMedia('(min-width: 768px)').matches"> ... </div>
```

The rule: **`x-data="foo()"` already runs `init()`; `x-init` is for inline expressions or for object-shaped `x-data` with no factory.** When migrating from Alpine 2 to Alpine 3, sweep the codebase for `x-init="init()"` on factory-shaped components — Alpine 2 didn't auto-call init.

## 2. HTMX wraps non-raw-object `HX-Trigger` values in `{value, elt}`

When a server response includes `HX-Trigger: someEvent`, HTMX dispatches `someEvent` as a `CustomEvent` on the triggering element. The `event.detail` shape depends on the JSON value attached to the trigger header:

| Server header value | `event.detail` shape |
|---|---|
| Bare event name: `HX-Trigger: itemSaved` | `null` |
| Raw object: `HX-Trigger: {"itemSaved": {"id": 42}}` | `{id: 42}` |
| Array: `HX-Trigger: {"uiNotify": [{"message": "Saved"}]}` | `{value: [{message: "Saved"}], elt: <button>}` |
| Primitive: `HX-Trigger: {"countUpdated": 5}` | `{value: 5, elt: <button>}` |

The first two are intuitive. The third and fourth are **not** — HTMX wraps non-raw-object values (arrays, numbers, strings, booleans, null) in `{value, elt}` because `CustomEvent.detail` semantics expected a single object with named properties. Listeners that assume the array IS the detail will read `event.detail.value` as `undefined` and silently drop the payload.

Listener-side defence:

```javascript
window.addEventListener('uiNotify', (event) => {
    let detail = event.detail;
    // Detect HTMX's value-wrapping shape and unwrap.
    if (
        detail !== null
        && typeof detail === 'object'
        && !Array.isArray(detail)
        && 'value' in detail
        && 'elt' in detail
    ) {
        detail = detail.value;
    }
    // Now detail is the original payload — array, primitive, or unwrapped object.
    const items = Array.isArray(detail) ? detail : [detail];
    for (const entry of items) {
        // ... handle entry
    }
});
```

The same listener works for both bridge-dispatched events from your own JS (where `detail` is the raw payload) and HTMX-dispatched events (where `detail` is wrapped). Always normalise to an array before iterating — a single payload should be processed identically to a batch.

## 3. The HTML spec runs defer scripts BEFORE `DOMContentLoaded` — not after

A common misconception ("`DOMContentLoaded` fires first; defer scripts run later") inverts the actual ordering. The HTML spec specifies:

1. HTML parsing completes.
2. **All `<script defer>` scripts execute in document order.**
3. **Then** `DOMContentLoaded` fires on `document`.

The practical impact for HTMX projects: **HTMX itself loads with `defer`** (the recommended pattern). Any handler bound inside a `DOMContentLoaded` callback runs *after* HTMX's defer-init has already started firing events.

This is silent until a page has an element that triggers HTMX on initial parse — `hx-trigger="load"`, `hx-trigger="every 5s"` with the first tick during init, or any HTMX action initiated by an Alpine `x-init` that runs synchronously. Those events fire into the void; your `DOMContentLoaded`-deferred listener never sees them.

Wrong:

```javascript
// htmx-error-handler.js, loaded blocking from <head>
function _registerListeners() {
    document.body.addEventListener('htmx:responseError', onResponseError);
}
// "Wait for DOM ready" — but defer scripts ran first, including HTMX's first events.
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', _registerListeners);
} else {
    _registerListeners();
}
```

Right:

```javascript
// htmx-error-handler.js, loaded blocking from <head>.
// HTMX events bubble to ``document`` (per HTMX docs guarantee), and ``document``
// exists at script-parse time even before <body> is parsed. Bind synchronously
// at parse time — before any defer-loaded script can dispatch.
document.addEventListener('htmx:responseError', onResponseError);
document.addEventListener('htmx:sendError', onSendError);
```

Two related rules:

- **Bind to `document`, not `document.body`**. `document` exists from the moment `<!DOCTYPE html>` is seen; `document.body` doesn't exist until `<body>` is parsed. HTMX events bubble to both, but `document` is reachable from anywhere a blocking head script runs.
- **For Alpine factory registration via `alpine:init`**, the script that calls `Alpine.data('foo', ...)` must execute BEFORE Alpine's own defer-task fires `alpine:init`. Either load the registration script blocking from `<head>` (no `defer`), or use `document.addEventListener('alpine:init', ...)` from a defer script and accept that registration happens just before the first DOM walk.

## Bringing it together: the safe-by-default boilerplate

For an Alpine 3 component that listens to HTMX-dispatched events:

```html
<!-- In <head>, blocking (no defer): -->
<script>
document.addEventListener('alpine:init', () => {
    Alpine.data('myComponent', () => ({
        init() {
            window.addEventListener('myEvent', (event) => {
                let detail = event.detail;
                if (
                    detail !== null
                    && typeof detail === 'object'
                    && !Array.isArray(detail)
                    && 'value' in detail
                    && 'elt' in detail
                ) {
                    detail = detail.value;
                }
                const items = Array.isArray(detail) ? detail : [detail];
                for (const entry of items) { /* ... */ }
            });
        },
    }));
});
</script>
<script src="alpine.min.js" defer></script>
<script src="htmx.min.js" defer></script>

<!-- In <body>: -->
<div x-data="myComponent()"><!-- no x-init="init()" --></div>
```

Reference: the IDEA-138 toast surface (teisutis [PR #412](https://github.com/infohata/teisutis/pull/412)) hit all three within a single afternoon's work — the first two during manual smoke, the third caught by bugbot. Each took ≥30 minutes to diagnose because the symptoms looked unrelated to the actual cause.

---

**Last Updated**: 2026-05-04
