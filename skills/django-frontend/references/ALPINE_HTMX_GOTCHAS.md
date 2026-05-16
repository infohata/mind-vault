# Alpine 3 + HTMX bridge — seven subtle gotchas

A set of behaviours that bite when wiring Alpine 3 components to HTMX events (custom-event bridges, OOB swaps with Alpine state, deferred handler binding, HX-on as a state-mutation seam, lazy-fetch on synthetic state changes), plus the JS-side i18n contract for cotton components and the listener-installation-order trap for refusable gates. Each is silent — no error, no warning — and only manifests after manual smoke or a corner-case input.

Load this reference when:
- Writing an `Alpine.data('foo', () => ({...}))` factory that owns event listeners.
- Bridging server events to client state via `HX-Trigger` headers.
- Deciding where to bind global handlers for HTMX events (`htmx:responseError`, `htmx:sendError`, `htmx:load`).
- Using `hx-on::after-request` (or any `hx-on::*`) inside an Alpine `x-data` scope to mutate Alpine state.
- Building disclosure widgets / collapsibles with optional first-expand HTMX lazy-fetch.
- Writing JS that mutates `textContent` / `innerHTML` of a DOM element rendered by a `{% trans %}`-aware cotton component (gotcha 6 — JS clobbers translations).
- Designing a JS function that has both side-effect installs (event listeners, classes, refs) AND a refusable gate check (gotcha 7 — install-after-gate).

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

## 6. JS that wraps a cotton component clobbers `{% trans %}` translations with hardcoded English

When JavaScript mutates the `textContent` / `innerHTML` of a DOM element rendered by a cotton component template, any **defensive English fallback** in the JS literal silently overrides the cotton template's `{% trans %}`-rendered translation.

The classic shape:

```javascript
// Modal title rebuilt on every open() call:
titleEl.textContent = opts.title || 'Confirm';
// "Looks fine" — opts.title is the caller-supplied value.
// But: when opts.title is undefined, the fallback `'Confirm'` overwrites
// whatever was in titleEl.textContent — including the cotton-template-rendered
// `{% trans "Confirm" %}` that resolved to `Patvirtinti` (Lithuanian),
// `Bekreft` (Norwegian), etc. The user sees English.
```

Bugbot will catch this as an "i18n regression — non-English users see English text". Bugbot's stated diagnosis ("missing translation map entry") is often **wrong** — the map entry is present, the .po catalog has the translation, the cotton template renders it correctly at request time. The bug is the JS overwrite that happens *after* render.

**Three fix patterns** (use whichever fits the JS surface):

### 6a. Snapshot the template-rendered text once per component instance, reuse on every mutation

The JS function snapshots the DOM element's initial `textContent` (or `outerHTML` for richer state) on first lookup, caches it per component-id, and reuses the cached value as the fallback on subsequent mutations:

```javascript
const _defaultsCache = {};

function _captureDefaults(componentId, modalEl) {
    if (_defaultsCache[componentId]) return _defaultsCache[componentId];
    const titleEl = modalEl.querySelector('[data-modal-title]');
    const messageEl = modalEl.querySelector('[data-modal-message]');
    _defaultsCache[componentId] = {
        // The cotton template rendered these with {% trans %} — they're
        // already in the user's locale at this snapshot point.
        title: (titleEl && titleEl.textContent) || 'Confirm',
        message: (messageEl && messageEl.textContent) || 'Are you sure?',
    };
    return _defaultsCache[componentId];
}

function showConfirm(opts) {
    const modalEl = document.getElementById(opts.id || 'uiConfirmModal');
    const defaults = _captureDefaults(opts.id, modalEl);
    const titleEl = modalEl.querySelector('[data-modal-title]');
    if (titleEl) titleEl.textContent = opts.title || defaults.title;
    // ...
}
```

The English literal `'Confirm'` in `_captureDefaults` becomes a *defensive* last-resort (only fires if the cotton template ever omits the data hook entirely — should be impossible). The user-facing path always reaches the locale-resolved cached value.

### 6b. Snapshot a richer chunk of HTML when the mutation replaces innerHTML, not textContent

Same pattern, but cache `outerHTML` of a marker element instead of `textContent`. Useful for loading-indicators, multi-element fragments:

```javascript
const _loadingIndicatorCache = {};

function _captureLoadingIndicator(modalId, bodyEl) {
    if (_loadingIndicatorCache[modalId]) return _loadingIndicatorCache[modalId];
    const indicator = bodyEl.querySelector('[data-loading-indicator]');
    if (!indicator) return null;
    _loadingIndicatorCache[modalId] = indicator.outerHTML;
    return _loadingIndicatorCache[modalId];
}

function showFormModal(opts) {
    const bodyEl = document.querySelector('[data-modal-body]');
    const loadingHtml = _captureLoadingIndicator(opts.id, bodyEl);
    if (loadingHtml) bodyEl.innerHTML = loadingHtml;
    // The previous bug: bodyEl.innerHTML = '<div>Loading…</div>'
    // — hardcoded English. Now reuses the cotton template's
    // {% trans "Loading…" %} HTML.
}
```

### 6c. Pass translated strings as `data-i18n-*` attributes when the JS needs strings the cotton component doesn't render visually

For strings the JS needs but the component doesn't visually render (e.g. legacy-shim defaults that interpolate into a multi-part message), expose them via `data-i18n-*` attrs on the cotton root rendered with `{% trans … as var %}` + `|escapejs`:

```django
{# cotton/confirm_modal.html #}
{% trans "Confirm Deletion" as legacy_delete_title %}
{% trans "Are you sure you want to delete" as legacy_delete_prefix %}
{% trans "This action cannot be undone." as legacy_delete_suffix %}
{% trans "Delete" as legacy_delete_label %}
<div id="uiConfirmModal"
     data-i18n-legacy-delete-title="{{ legacy_delete_title|escapejs }}"
     data-i18n-legacy-delete-prefix="{{ legacy_delete_prefix|escapejs }}"
     data-i18n-legacy-delete-suffix="{{ legacy_delete_suffix|escapejs }}"
     data-i18n-legacy-delete-label="{{ legacy_delete_label|escapejs }}">
  ...
</div>
```

```javascript
function _legacyI18n(key, fallbackEn) {
    const modal = document.getElementById('uiConfirmModal');
    return (modal && modal.dataset['i18nLegacyDelete' + key]) || fallbackEn;
}

window.confirmDelete = function (url, itemName) {
    return openConfirm({
        title: _legacyI18n('Title', 'Confirm Deletion'),
        message: _legacyI18n('Prefix', 'Are you sure you want to delete')
                 + ' "' + itemName + '"? '
                 + _legacyI18n('Suffix', 'This action cannot be undone.'),
        confirmText: _legacyI18n('Label', 'Delete'),
        // ...
    });
};
```

> **Django template gotcha**: `{% trans "..." as var %}` requires a variable name that does NOT begin with an underscore. Django template variable parsing rejects `_legacy_delete_title` with `TemplateSyntaxError: Variables and attributes may not begin with underscores`. Use `legacy_delete_title` (no leading underscore).

> **`|escapejs` is the right escape for data-attribute values** even though the attribute isn't strictly JSON. `escapejs` over-escapes for HTML-attribute context (over-escape is fine — HTML attribute parsers handle `'` correctly), and crucially it handles embedded quotes and backslashes that would otherwise break the attribute syntax.

### When to reach for which pattern

- **Mutation replaces a single text node, the cotton template already renders the translated value** → pattern 6a (`_captureDefaults`).
- **Mutation replaces an HTML fragment, the cotton template carries the translated structure** → pattern 6b (`_captureLoadingIndicator`).
- **JS needs strings the cotton template doesn't visually render** (legacy shims, multi-part interpolated messages, error strings used only on failure paths) → pattern 6c (`data-i18n-*` attrs).
- **Combination** — large components (modal primitives, form widgets) often need ALL THREE patterns simultaneously. They're complementary, not exclusive.

### Anti-patterns

- ❌ **Hardcoded English literal in `||` fallback chain**: `opts.title || 'Confirm'`, `messageEl.textContent = 'Are you sure?'`, `bodyEl.innerHTML = '<div>Loading…</div>'`. Every one of these clobbers the template's translated value when opts is partial.
- ❌ **"It's just a defensive fallback, the caller always passes opts.title"**: that's a runtime assertion that decays as the codebase grows. Two months later, a new caller forgets opts.title, the fallback fires, and non-English users see English. The defensive fallback is exactly the bug.
- ❌ **Adding the missing string to the translation map** when the bug is JS clobber. The map IS already populated. The fix is JS-side, not catalog-side. Bugbot's surface diagnosis frequently misdirects here — verify the catalog state before "filling the gap".

## 7. Event listeners installed before a refusable gate leak on refusal

When a function performs both side-effect installs (event listeners on DOM elements, classes added, references stored in module-level state) AND a gate check that may refuse the operation, install the side-effects **after** the gate check. Otherwise refused calls leak the side-effects forever.

The classic shape:

```javascript
// open() — gate may refuse if a modal is already open
function open(modalEl, opts) {
    // 1. Install side-effects (listener attached to DOM)
    cancelBtn.addEventListener('click', _state.cancelClickHandler = () => close());
    form.addEventListener('htmx:afterRequest', _state.afterRequestHandler = handleResponse);

    // 2. Gate check (may refuse)
    const accepted = coordinator.tryClaim(modalEl.id);
    if (!accepted) return false;
    //                ^^^ Listeners stay attached. _state.cancelClickHandler /
    //                    afterRequestHandler now point at the LATEST attached
    //                    handlers. close()'s teardown removes only those latest
    //                    refs — older handlers leak forever.
}
```

If the function is called repeatedly while the gate stays refused (e.g. user spam-clicks a "open modal" button while another modal is open), each call adds one more handler to `cancelBtn`/`form`. When the gate eventually opens and the user clicks Cancel:

1. ALL accumulated handlers fire (each calls `close()`)
2. The first `close()` succeeds and tears down `_state.cancelClickHandler`
3. The remaining handlers see `coordinator.openId === null` and early-return — but they STILL fired
4. Side effects from those leaked handlers (analytics, state updates, navigation) all happen N times for one user click

**Fix — install side-effects after the gate**:

```javascript
function open(modalEl, opts) {
    // 1. Gate check FIRST
    const accepted = coordinator.tryClaim(modalEl.id);
    if (!accepted) return false;

    // 2. Install side-effects only after the gate accepted
    cancelBtn.addEventListener('click', _state.cancelClickHandler = () => close());
    form.addEventListener('htmx:afterRequest', _state.afterRequestHandler = handleResponse);

    return true;
}
```

The discipline generalises beyond modals — any function whose body has the shape `(install side-effects, check whether to proceed, return false if not)` has the same leak. Reorder to `(check first, install only on success, return)`.

### How to detect the leak in code review

- Search for `function (` definitions where `addEventListener` / `Alpine.data` / `Alpine.store` / module-level state assignment occurs *before* an early-return / coordinator-check / gate condition.
- Verify that the side-effect installs are also paired with teardown in a corresponding close/cleanup function — and that the teardown uses the SAME reference the install captured (not the latest mutation of a shared `_state.X` field).
- If the function is called multiple times for the same component, ensure the first install is idempotent or the function checks `if (already installed) return` before installing.

References:

- The IDEA-138 toast surface (teisutis [PR #412](https://github.com/infohata/teisutis/pull/412)) hit gotchas 1-3 within a single afternoon's work — first two during manual smoke, third caught by bugbot.
- The IDEA-139 cotton primitives (teisutis [PR #413](https://github.com/infohata/teisutis/pull/413)) hit gotchas 4-5 in the same one-day cycle — gotcha 4 caught by manual smoke (Alpine reactive bridge from `hx-on` doesn't work), gotcha 5 caught by bugbot (lazy-fetch + hash-deeplink combo silently broken).
- The IDEA-141 modal primitives (teisutis [PR #423](https://github.com/infohata/teisutis/pull/423)) hit gotchas 6 + 7 across THREE bugbot cycles — every i18n finding shared the same root cause (JS clobber), each surface needing one of the three patterns to fix it. Gotcha 7's listener leak in `confirm()` surfaced when the dev-preview demo's spam-click-during-modal-from-modal-refusal scenario was finally exercised; the same PR's `form()` already had the correct ordering.

Each gotcha takes ≥30 minutes to diagnose because the symptoms always look unrelated to the actual cause.

## 8. Rebind-on-event listener migration is fragile — prefer permanent-bind + active-discriminator

When listening to per-X events (per-pane scroll, per-tab focus, per-region resize) where X changes over time, the natural pattern of "rebind listener on X-change-event" is fragile. Change events have edge cases that don't fire — sibling short-circuits, equality early-returns (`if (next === current) return` before the change-event dispatches), Alpine reactive equality bail-outs.

**Symptom**: listener bound to a stale element after a state transition. Behaviour silently dies for affected users; no JS error, no console warning.

**Fix**: bind permanently to ALL candidate sources at init. Each handler reads a discriminator (DOM attribute mirrored from reactive state, or a global selector match) at event time and short-circuits if its source isn't currently active.

```js
function bindAllPaneListeners() {
    ['workspace', 'center', 'preview'].forEach((paneName) => {
        const pane = document.querySelector(`[data-pane-name="${paneName}"]`);
        if (!pane) return;
        const scrollEl = resolveScrollContainer(pane);
        scrollEl.addEventListener('scroll', () => {
            // Discriminator: read the active-pane attribute at event time.
            const active = document.querySelector('.shell-pane-snap').dataset.activePane;
            if (paneName !== active) return;  // not us, short-circuit
            // ...do per-active-pane work.
        }, { passive: true });
    });
}
```

The active-discriminator is mirrored from reactive state via a single binding — Alpine `:data-active-pane="activePane"`, React `data-active-pane={activePane}`, Vue `:data-active-pane="activePane"`. Subscribers no longer migrate on `paneChanged` events; they self-route from a single source of truth.

Trade: more listeners pinned simultaneously (one per candidate source), but each is cheap and the discriminator short-circuit makes the inactive ones zero-cost. Net win is robustness — no class of "the change event didn't fire because of an upstream early-return" bug.

Surfaced: teisutis IDEA-143 M25 — `navbar-scroll.js` migrated its single scroll listener on `paneChanged`. Close paths whose `goToPane('center')` snap landed on a pane that was already `activePane='center'` short-circuited `paneChanged` (`next === activePane` early-return), so the rebind never fired. Listener stayed attached to the off-screen drawer's scroll container; nav-hide silently broke after every drawer close.

## 9. Alpine `x-init` / `x-effect` expressions must stay expression-only — `try/catch` and IIFEs both fail

`x-init` and `x-effect` attribute bodies are evaluated by Alpine via a `Function('with($data) { return <expr> }')`-style wrapper. The wrapping forces a few syntactic constraints that aren't documented:

| Inline form | Failure |
|---|---|
| `x-init="try { foo(); } catch(e) {}"` | `SyntaxError: Unexpected token 'try'` — statements aren't allowed at top level |
| `x-init="(() => { try { foo(); } catch(e) {} })()"` | Loses Alpine's `with($data)` scope inside nested arrows — bare reactive refs fail to resolve |
| `x-init="foo && bar()"` | Works (expression) |
| `x-init="$nextTick(() => { foo(); })"` | Works (Alpine provides `$nextTick`, arrow body is an expression-equivalent) |

The canonical fix when the body needs statement-level logic (try/catch, multi-statement init, error handling): **register a real `Alpine.data()` factory at `alpine:init` and call it from `x-data`**:

```js
// In a blocking <head> script, before Alpine's defer-init fires:
document.addEventListener('alpine:init', () => {
    Alpine.data('myWidget', () => ({
        loaded: false,
        async init() {
            try {
                await this.loadData();
                this.loaded = true;
            } catch (err) {
                console.warn('widget init failed', err);
            }
        },
        async loadData() { /* … */ },
    }));
});
```

```html
<div x-data="myWidget()"><!-- factory auto-calls init() once — no x-init needed --></div>
```

Even cleaner for bistable open/close state (collapsibles, accordions): drop Alpine entirely for that surface and use native `<details>` / `<summary>`. The browser owns the state machine; JS handles persistence (sessionStorage) + first-open lazy-fetch. Full pattern + the failure classes that become structurally impossible: [`COLLAPSIBLE_PATTERNS.md`](COLLAPSIBLE_PATTERNS.md) § *Native `<details>` defragilization*.

## 10. `htmx:afterSwap` `event.detail.target` is unreliable for outerHTML swaps — re-walk the document

For `hx-swap="outerHTML"` swaps, `event.detail.target` on `htmx:afterSwap` may reference the OLD removed element (HTMX's internal swap order varies by version). Listeners that try to `event.detail.target.querySelectorAll(...)` get an empty result because the target is detached from the document.

**Fix**: re-walk the document on every swap event (operations must be idempotent), and listen for BOTH `htmx:afterSwap` AND `htmx:load` for cross-version coverage:

```js
function _bindMySurfaceTo(root) {
    root.querySelectorAll('[data-my-surface]').forEach(el => {
        if (el.dataset.mySurfaceBound) return;       // idempotent
        el.dataset.mySurfaceBound = '1';
        // bind…
    });
}

// Bind on every swap event — both names cover all HTMX swap shapes
['htmx:afterSwap', 'htmx:load'].forEach(name => {
    document.addEventListener(name, () => _bindMySurfaceTo(document));
});
```

Two related rules:

- **Defer the listener-install to DOMContentLoaded** when the script loads in `<head>` (otherwise `document.body` may not exist yet — gotcha 3's territory).
- **Re-walk is cheap because of the `data-*-bound` sentinel**. The walk is O(N) over a slice scoped to live components; the sentinel makes already-bound elements no-ops.

Recurrence shape: a native-`<details>` migration where the bind chain trusted `event.detail.target` failed when an unrelated cotton swap replaced the collapsible's host element — the new hosts loaded unbound. Document re-walk + dual-event listening on both `htmx:afterSwap` and `htmx:load` recovered the contract.

## 11. Bootstrap a document-level listener on `document`, not `document.body`

When binding a global event listener (HTMX trigger, custom event, refresh walker) from a `<head>` blocking script, `document.body` doesn't exist yet at script parse time — `document.body.addEventListener(...)` throws `Cannot read properties of null`.

The fix is to bind on `document` itself, which exists from the moment the parser sees `<!DOCTYPE html>`. Custom events fired on any descendant bubble up through body → document, so document-level listeners catch them:

```js
// ❌ Wrong — script in <head>, body not parsed yet
document.body.addEventListener('entityChanged', handler);

// ✅ Right — document exists from parse-start; events bubble up
document.addEventListener('entityChanged', handler);
```

**Important corollary — events bubble UP, not DOWN.** A custom event fired on `document` does NOT propagate down to listeners bound to `document.body`. If you fire from a JS module, fire on the **swapped element** (or `document.body`); listeners on either `document.body` or `document` catch the bubble:

```js
// ❌ Wrong — document.body listener never fires
document.dispatchEvent(new CustomEvent('refresh', { bubbles: true }));

// ✅ Right — fire on swapped target; bubbles up through body → document
swappedEl.dispatchEvent(new CustomEvent('refresh', { bubbles: true }));
```

Mirrors HTMX's own dispatch behaviour (HTMX fires on the swapped target). The walker pattern in [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md) § *Walker rebind contract* embodies this.

## 10. Alpine `:class="cond && 'str'"` short-circuit doesn't remove SSR-applied classes

When an element layers Alpine's `:class` binding **on top of** a server-rendered `class="…"` attribute, the binding's syntax determines whether Alpine can REMOVE classes that the server applied. The short-circuit pattern (`:class="cond && 'foo'"`) only ADDS — it cannot remove. Object syntax (`:class="{ foo: cond }"`) tracks both directions.

### The trap

A nav cotton renders both static + reactive class bindings on the same `<a>`:

```django
<a class="navbar-item shell-nav__item{% if active_surface == item.slug %} shell-nav__item--active{% endif %}"
   :class="$store.shellNav.activeSurface === '{{ item.slug }}' && 'shell-nav__item--active'">
   …
</a>
```

The intent: SSR satisfies cold-load no-FOUC; Alpine takes over post-`alpine:init` and keeps the marker in sync across every hot-swap. Looks right at a glance — both sides reference `shell-nav__item--active`.

**The trap**: Alpine's `:class="expr"` directive evaluates `expr`. For `cond && 'foo'`:

- `cond` truthy → expression returns `'foo'` → Alpine adds the class.
- `cond` falsy → expression returns `false` (or `0`, `''`, `null`) → Alpine treats it as a no-op. **It does NOT remove `'foo'` from the static `class` attribute.**

Alpine only tracks the classes IT has added (via prior reactive evaluations). The server-rendered `shell-nav__item--active` was never added by Alpine — so Alpine has no record of it and won't remove it when the reactive expression flips false.

Symptom: directional asymmetry. The nav item that was active at SSR-time stays highlighted forever (its `--active` class survives every hot-swap because the short-circuit can only add, not remove). The nav item that becomes active later correctly gains the class via Alpine. Hot-swap of an active surface back to its original cold-load state appears to work; hot-swap AWAY from the cold-load active surface leaves the stale marker.

### The fix — object syntax

```django
<a class="navbar-item shell-nav__item{% if active_surface == item.slug %} shell-nav__item--active{% endif %}"
   :class="{ 'shell-nav__item--active': $store.shellNav.activeSurface === '{{ item.slug }}' }">
   …
</a>
```

Object syntax `{ 'foo': cond }` is a class-toggle directive Alpine understands as bidirectional. When `cond` flips false, Alpine REMOVES `'foo'` from the element's class list — including when `'foo'` was originally server-applied. The SSR class correctly hands off to Alpine's reactive control on first evaluation.

### Why `:aria-current` doesn't have this problem

The asymmetry is `:class`-specific. Alpine's `:attr` binding (used for any attribute name except `class` / `style`) uses different semantics: a `null` / `undefined` return value REMOVES the attribute, a string return value SETS it.

```django
{% if active_surface == item.slug %}aria-current="page"{% endif %}
:aria-current="$store.shellNav.activeSurface === '{{ item.slug }}' ? 'page' : null"
```

This ternary works correctly even though the same `cond && 'page'` syntax would NOT — `:aria-current` will SET to `'page'` when truthy and REMOVE the attribute when null, regardless of whether the attribute was server-applied. Class binding's add-only short-circuit is the outlier.

### Detection

After landing any dual-bound SSR + Alpine class binding, walk a state transition that should REMOVE the class (e.g. nav-swap from active surface A to active surface B). Visually verify the previously-active marker clears. If it doesn't, the binding is the short-circuit form — convert to object syntax.

A render-and-assert test that ONLY checks the truthy case (active item carries `--active`) won't catch this — both syntaxes pass that assertion. The failing case is the previously-active item AFTER a state change, which static render tests can't reach without a JS execution layer. Manual eval or Playwright is the gate.

### The same lesson generalises to `:style`

Object syntax is also the safe default whenever a static attribute might carry the value the reactive binding is supposed to control. `:style="cond && 'display: none'"` has the same asymmetry as `:class`; `:style="{ display: cond ? 'none' : '' }"` is the bidirectional form.

### When to skip this pattern entirely

The cleanest variant is the [`ACTIVE_STATE_TRACKING.md`](ACTIVE_STATE_TRACKING.md) pattern: drop `:class` entirely, use `aria-current="true"` (or another semantic attribute) as the single source of truth, style via CSS `:has()`. Single attribute, no SSR / reactive sync to manage, no syntax trap to remember. The dual-bound pattern above is for cases where `:has()` styling isn't viable (parent-styling chain too deep, or browser-support constraints).

---

**Last Updated**: 2026-05-16
