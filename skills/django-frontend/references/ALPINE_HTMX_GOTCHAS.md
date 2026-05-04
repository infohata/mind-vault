# Alpine 3 + HTMX bridge — five subtle gotchas

A set of behaviours that bite when wiring Alpine 3 components to HTMX events (custom-event bridges, OOB swaps with Alpine state, deferred handler binding, HX-on as a state-mutation seam, lazy-fetch on synthetic state changes). Each is silent — no error, no warning — and only manifests after manual smoke or a corner-case input.

Load this reference when:
- Writing an `Alpine.data('foo', () => ({...}))` factory that owns event listeners.
- Bridging server events to client state via `HX-Trigger` headers.
- Deciding where to bind global handlers for HTMX events (`htmx:responseError`, `htmx:sendError`, `htmx:load`).
- Using `hx-on::after-request` (or any `hx-on::*`) inside an Alpine `x-data` scope to mutate Alpine state.
- Building disclosure widgets / collapsibles with optional first-expand HTMX lazy-fetch.

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

## 4. `hx-on::*` runs in plain JS scope, NOT Alpine's evaluator

When you write `<div x-data="{ resetUrl: '' }">` and try to update `resetUrl` from `hx-on::after-request="resetUrl = ..."`, **the assignment doesn't reach Alpine's reactive state**. HTMX evaluates `hx-on` handlers via `new Function("event", code)` — that runs in plain JS scope. Bare `resetUrl = ...` becomes a window global (in non-strict mode) or a `ReferenceError` (in strict mode). Alpine's `x-text="resetUrl"` and `x-show="resetUrl"` bindings see no state change and never react.

Symptom: a button bound with `hx-on::after-request` fires its HTMX request, response comes back, the assignment runs without throwing — but the dependent UI never updates. Manual smoke catches this; tests that assert markup at render time miss it entirely (the `x-data` binding renders fine; the runtime-dispatch issue is invisible to render-and-assert).

```html
<!-- WRONG: hx-on assignment doesn't update Alpine state -->
<span x-data="{ resetUrl: '' }">
    <button hx-post="/generate-link/"
            hx-on::after-request="if(event.detail.successful){
                try{ resetUrl = JSON.parse(event.detail.xhr.responseText).url; }catch(e){}
            }">Generate</button>
    <span x-text="resetUrl"></span>      <!-- never populates -->
    <span x-show="resetUrl"><c-copy-button :target="..." /></span>  <!-- never reveals -->
</span>
```

Three workable patterns, in increasing order of robustness:

**A — `Alpine.$data($el).resetUrl = ...`** (Alpine 3.13+). Walks up to the closest Alpine scope and writes through its proxy. Closest to "just make the bare assignment work":

```html
hx-on::after-request="if(event.detail.successful){
    try{ Alpine.$data(this).resetUrl = JSON.parse(event.detail.xhr.responseText).url; }catch(e){}
}"
```

Works, but couples the consumer to Alpine's API surface and depends on the closest-ancestor `x-data` actually being the right scope (fragile under refactors that wrap or unwrap intermediate components).

**B — Listen via Alpine, not HTMX**. `x-on:htmx:after-request.camel="…"` on the parent `x-data` evaluates the handler in Alpine's scope:

```html
<span x-data="{ resetUrl: '' }"
      x-on:htmx:after-request.camel="if($event.detail.successful){
          try{ resetUrl = JSON.parse($event.detail.xhr.responseText).url; }catch(e){}
      }">
    <button hx-post="/generate-link/" hx-swap="none">Generate</button>
    ...
</span>
```

The `.camel` modifier is required because HTMX dispatches the event as `htmx:afterRequest` (camelCase) and HTML attribute names lowercase. This is the cleanest "stay-in-Alpine" approach.

**C — Plain DOM bridge: skip Alpine entirely for the reveal**. Use `document.getElementById('source').textContent = ...; document.getElementById('reveal').hidden = false`. Sidesteps the whole class of bridging bugs:

```html
<button hx-post="/generate-link/"
        hx-on::after-request="if(event.detail.successful){
            try{
                var d=JSON.parse(event.detail.xhr.responseText);
                document.getElementById('reset-source').textContent = d.url;
                document.getElementById('reset-copy').hidden = false;
            }catch(e){}
        }">Generate</button>
<span class="is-sr-only" id="reset-source"></span>
<span id="reset-copy" hidden>
    <c-copy-button target="#reset-source" />
</span>
```

Pattern C is the right default when the consumer just needs to "show this hidden region after the response lands and let a c-copy-button read its content." No Alpine state needed because the c-copy-button reads `target.textContent` at click time anyway. Reference: teisutis [PR #413 commit `a3344000`](https://github.com/infohata/teisutis/commit/a3344000) replaced an Alpine-bridge attempt with this pattern after the manual smoke caught the buttons doing nothing.

## 5. `hx-trigger="click once"` doesn't fire on synthetic state changes — drive lazy-fetch from a state-watcher

When a UI primitive (collapsible, accordion, popover) supports both **user click** AND **synthetic open** (initial expanded state, deep-link from `location.hash`, programmatic open), and a side effect (HTMX lazy-fetch, telemetry ping, focus restoration) needs to fire on first-open regardless of how the open happened — **don't bind the side effect to the click event**.

`hx-trigger="click once"` only fires on a real `click` event. Setting `open = true` from `x-init` (e.g. `if (window.location.hash === '#' + id) open = true`) is a synthetic state mutation, not an input event — no click bubbles up, the trigger never fires. The user-visible result: body shows whatever placeholder the lazy-fetch was meant to replace ("Loading…", an empty container), forever, with no error or console warning.

Test renders that assert markup pass fine. The bug only surfaces in a manual smoke that reaches the synthetic-open path — which is exactly the path most tests skip because it requires reloading with a specific URL hash.

The fix is to drive the side effect from the **state**, not the **input event**. Alpine `x-effect` watching the open variable, with a `loaded` (or equivalent) guard for exactly-once:

```html
<div x-data="{ open: false, loaded: false }"
     x-init="if (window.location.hash === '#' + $el.id) open = true"
     x-effect="if (open && !loaded) {
         loaded = true;
         htmx.ajax('GET', '/lazy-fetch-url/', '#body-content');
     }">
    <button @click="open = !open">Toggle</button>
    <div x-show="open" x-cloak>
        <div id="body-content">
            <span class="loading">Loading…</span>
        </div>
    </div>
</div>
```

`x-effect` re-runs whenever a reactive dep changes; the `open && !loaded` guard ensures exactly one fetch per primitive instance regardless of how `open` flipped — initial `expanded=true`, hash-deeplink, user click, programmatic `Alpine.$data(...).open = true`, all funnel through the same gate.

The general principle: when an effect must fire on a state change rather than on a specific input event, use a state-watcher (`x-effect` in Alpine, `effect()` in Vue, `useEffect` in React, etc.). Click-handlers are for "user explicitly chose to do this," not for "the thing has now opened, regardless of cause."

Reference: teisutis [PR #413 commit `4fcad0a0`](https://github.com/infohata/teisutis/commit/4fcad0a0) rewrote a `c-collapsible` cotton primitive from `hx-trigger="click once"` to `x-effect`-driven lazy-fetch after bugbot caught that hash-deeplink + lazy-fetch combo silently failed.

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

References:

- The IDEA-138 toast surface (teisutis [PR #412](https://github.com/infohata/teisutis/pull/412)) hit gotchas 1-3 within a single afternoon's work — first two during manual smoke, third caught by bugbot.
- The IDEA-139 cotton primitives (teisutis [PR #413](https://github.com/infohata/teisutis/pull/413)) hit gotchas 4-5 in the same one-day cycle — gotcha 4 caught by manual smoke (Alpine reactive bridge from `hx-on` doesn't work), gotcha 5 caught by bugbot (lazy-fetch + hash-deeplink combo silently broken).

Each takes ≥30 minutes to diagnose because the symptoms always look unrelated to the actual cause.

---

**Last Updated**: 2026-05-04
