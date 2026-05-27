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
swap, so HTMX fires no lifecycle events for it. To get widgets to (re-)mount in the new subtree, the
body-replacer **dispatches the lifecycle events itself**. This section is the **binder side** — what
a widget binder must do to (re-)mount robustly when a body-replacer it doesn't control swaps the DOM
under it. A binder has to get *three* things right, and each one is an independent silent-death axis:

1. **Listen on an event the body-replacer actually dispatches.** A body-replacer commonly fires
   `htmx:afterSettle` and/or `htmx:load` — and often **not** `htmx:afterSwap`. A binder wired only to
   `htmx:afterSwap` (plus `DOMContentLoaded`) mounts on cold load and on real HTMX swaps but is dead
   in the drawer. `htmx:afterSettle` is the safe single choice — both real swaps and the body-replacer
   fire it.

2. **Bind on `document`, not `document.body`.** A body-replacer commonly dispatches *on `document`
   itself* (`document.dispatchEvent(…)`); an event dispatched on `document` never reaches a
   `document.body` listener (`body` sits *below* `document`, so it's not on the propagation path even
   with `bubbles: true` — see [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 3). Binding on
   `document` catches that dispatch *and* the bubbled real-swap. §1 says this for a head-load-timing
   reason; this is a second, independent reason.

3. **Read `evt.detail.elt || evt.detail.target` (or ignore detail and rescan).** A real HTMX swap
   puts the host on `detail.target` (§1); a synthetic dispatch from a body-replacer commonly follows
   the editor-widget convention and puts it on `detail.elt`. A scoped binder must read both (elt
   first) or it early-returns on the other shape. A binder that *ignores* detail and re-scans the
   whole `document` for un-mounted nodes (idempotency guard per §2) sidesteps this axis entirely —
   both strategies are valid; scoping just avoids a whole-page walk on every swap.

```js
document.addEventListener('htmx:afterSettle', function (evt) {
    var root = (evt.detail && (evt.detail.elt || evt.detail.target)) || document;
    initWidgetsIn(root);               // idempotent per §2 — safe if this fires twice
});
```

**Failure mode** — get *any* of the three wrong and the widget is dead inside the drawer, *silently*:
it still works on a cold full-page load (real `DOMContentLoaded` + real HTMX paths fire there), so the
bug only appears when the widget first opens in the drawer. It's **latent across surfaces** — a binder
written for surface A's inline form keeps working there but is dead the instant the same widget first
appears in a drawer-hosted form on surface B. Binders that already matched the body-replacer's event +
target + detail shape "just work" there; the one that diverged on any axis is the one that breaks.

**The dispatch side — two shapes exist in the wild, which is *why* the binder must be robust:**

- **`document`-dispatch + `detail.elt`** — a body-replacer following the editor-widget convention
  dispatches `htmx:beforeSwap` / `htmx:afterSettle` / `htmx:load` on `document`, scoping the rebind to
  the host via `detail.elt`. Reaches `document` listeners only. (This is what a per-frame body-restore
  surface typically does.)
- **Element-dispatch + `bubbles: true` + both `detail.elt` and `detail.target`** — the more forgiving
  shape: bubbles up to `document` *and* `document.body`, serves both keys. If you're writing a
  state-refresh walker that re-fires events after a manual swap, prefer this — it's the
  [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md) § *Walker rebind contract* (see also
  [`DRAWER_FORM_STATE_PRESERVATION.md`](DRAWER_FORM_STATE_PRESERVATION.md) § *Restore*).

You usually don't control the body-replacer, so the binder rule above (listen on `afterSettle`, bind
on `document`, read `elt || target`) is correct under either dispatch shape *and* under real swaps.
Idempotency (§2) matters doubly — a synthetic settle can fire alongside or twice with other settle
events; the mounted-set guard turns the extra calls into no-ops.

## Who relies on this

- **[`VENDORING_JS_BUNDLES.md`](VENDORING_JS_BUNDLES.md)** — the always-loaded integration glue follows §§1–4.
- **[`LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md`](LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md)** — the lazily-injected binder *additionally* requires §5 (it loads after DCL), and layers injection-specific concerns on top (sequential inject, in-flight dedupe, `ready()` validating the last global).
- **[`HTMX_WIDGETS.md`](HTMX_WIDGETS.md)** — the custom-widget cookbook; each widget's "re-init after swap" note is this contract.
