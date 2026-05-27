# HTMX widget lifecycle — (re-)init, teardown, idempotency across swaps

A JS widget (vendored editor, diagram renderer, autocomplete, drag-handle) that lives inside an
HTMX-swapped region must survive the swap lifecycle: its DOM is replaced on every swap, so it must
(re-)initialize when its DOM arrives and clean up when its DOM is removed. This contract is the
shared substrate under both eagerly-loaded integration glue
([`VENDORING_JS_BUNDLES.md`](VENDORING_JS_BUNDLES.md)) and lazily-injected binders
([`LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md`](LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md)) — both reference
this rather than restating it.

## The contract

### 1. Re-init on `htmx:afterSwap`

```js
document.addEventListener('htmx:afterSwap', function (evt) {
    if (!evt.detail || !evt.detail.target) return;
    if (evt.detail.target.id !== 'my-region') return;          // gate: ignore unrelated swaps
    var node = document.getElementById('my-region');           // FRESH node, not evt.detail.target
    initWidgetsIn(node);                                        // umbrella → each widget type's init<Widget>In(root), §4
});
```

- **Subscribe on `document`, not `document.body`** — a script loaded blocking from `<head>` runs while `document.body` is still `null`.
- **Read the FRESH node from the live DOM** — after an `outerHTML` swap, `evt.detail.target` is the *detached* old node, so its attributes/children are stale.
- **Gate on the region id** so unrelated swaps elsewhere on the page don't re-trigger.

### 2. Idempotent (re-)init

Init must be safe to call on already-mounted DOM and safe to call twice from one trigger. Guard on a
mounted-set (`Map<HTMLElement, Handle>`) or consume the source nodes on mount (a re-scan finds
nothing). Then a double-call is a harmless no-op.

### 3. Teardown on `htmx:beforeSwap` / `htmx:beforeSettle`

Before a region is replaced, `handle.destroy()` every tracked element about to be removed — otherwise
you leak event listeners and DOM-detached widget cores forever. This is why mounts are tracked in a
`Map<HTMLElement, Handle>` (§2): the map is both the idempotency guard and the teardown roster.

### 4. Container-scoped init — honor the `root` arg

Each widget type exposes its own `init<Widget>In(root)` (e.g. `initEditorIn`, `initDiagramIn` — the
`initXIn(root)` referenced in §5 and the consuming refs). The §1 `htmx:afterSwap` umbrella
(`initWidgetsIn`) calls each of them on the fresh region.

```js
window.initEditorIn = function (root) { root.querySelectorAll('[data-editor]').forEach(mount); };
```

ALWAYS scope queries to `root`. A wrapper that hardcodes `document` silently widens per-region init to
the whole page — re-mounting every widget on every swap.

### 5. `readyState`-safe boot (mandatory for scripts that may load after `DOMContentLoaded`)

A binder that registers its initial mount **and** its own `htmx:afterSwap` listener on
`DOMContentLoaded` never fires if the script is injected *after* DCL (lazy loading) — so neither the
initial init nor the listener registration happens, and subsequent swaps break too. Wrap the boot so
it self-runs whenever it loads:

```js
function boot() { initImmediately(); registerHtmxListeners(); }
if (document.readyState !== 'loading') boot();
else document.addEventListener('DOMContentLoaded', boot);
```

Eagerly-loaded scripts (cold-load `<head>` / `extra_js`) hit DCL normally and don't strictly need
this — but writing every binder readyState-safe makes it reusable in both load modes for free.

### 6. Synthetic swap events from a custom body-replacer (drawer / preview surface)

A custom drawer or preview surface that replaces its body via `innerHTML` is **not** a real HTMX
swap, so HTMX fires no lifecycle events for it. To get widgets to (re-)mount in the new subtree,
the body-replacer typically **dispatches a synthetic `htmx:afterSettle` itself**. Two shape
mismatches bite here, and they compound into a silent, latent break:

1. **Dispatch on `document`, not `document.body`.** The replacer does
   `document.dispatchEvent(new CustomEvent('htmx:afterSettle', …))`. A binder that listens on
   `document.body` **never receives it** — an event dispatched *on* `document` doesn't travel down
   to `body` (capture then bubble move between the event target and the root; `body` sits *below*
   `document`, so it's never on the path). §1 already says subscribe on `document` for a
   head-load-timing reason; this is a second, independent reason to do the same thing.

2. **The host arrives as `detail.elt`, not `detail.target`.** Real HTMX swaps put the swapped
   node on `evt.detail.target` (§1). A synthetic dispatch from a body-replacer commonly follows the
   editor-widget convention and puts it on `evt.detail.elt`. A binder that only reads
   `detail.target` early-returns on the synthetic event. **Read `evt.detail.elt || evt.detail.target`**
   so one listener handles both the real-swap and synthetic-swap shapes.

```js
document.addEventListener('htmx:afterSettle', function (evt) {
    var root = (evt.detail && (evt.detail.elt || evt.detail.target)) || document;
    initWidgetsIn(root);               // idempotent per §2 — safe if this fires twice
});
```

**Failure mode** — a binder that gets *both* wrong (listens on `document.body` AND reads only
`detail.target`) is dead inside the drawer, and dies *silently*: it still works on a cold full-page
load (real `DOMContentLoaded` + real HTMX paths fire there), so the bug only appears when the widget
is opened in the drawer. Worse, it's **latent across surfaces** — a binder written for surface A's
inline form keeps working there but is dead the instant the same widget first appears in a
drawer-hosted form on surface B. Binders that already followed the editor convention "just work" in
the drawer; the one that diverged is the one that breaks.

**Contract for the body-replacer side:** pick one shape and hold it. If you dispatch a synthetic
`htmx:afterSettle`, dispatch it on `document`, set `detail.elt` to the new body host, and make every
widget binder read `elt || target`. Idempotency (§2) matters doubly here — a synthetic settle can
fire alongside or twice with other settle events; the mounted-set guard turns the extra calls into
no-ops.

## Who relies on this

- **[`VENDORING_JS_BUNDLES.md`](VENDORING_JS_BUNDLES.md)** — the always-loaded integration glue follows §§1–4.
- **[`LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md`](LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md)** — the lazily-injected binder *additionally* requires §5 (it loads after DCL), and layers injection-specific concerns on top (sequential inject, in-flight dedupe, `ready()` validating the last global).
- **[`HTMX_WIDGETS.md`](HTMX_WIDGETS.md)** — the custom-widget cookbook; each widget's "re-init after swap" note is this contract.
