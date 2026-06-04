# Listener rebind on HTMX swap — per-container/per-pane listeners that DON'T survive `outerHTML`

**Scope**: JavaScript event listeners bound directly to a container element (not via document delegation) that an HTMX `outerHTML` swap or shell-fragment swap replaces. Distinct from `HTMX_WIDGET_LIFECYCLE.md` §6 (which covers widget re-mount inside a swap target via synthetic events) — this reference is about the **listener** dying when its **binding element** is swapped out.

## The failure mode

```
js: el.addEventListener('scroll', handler)   // bound at init to a specific element
htmx:           outerHTML swap of #shell-swap-target  → el is now a NEW node
result: handler is GONE on the new node; old el is GC-eligible
```

Symptom: works on cold load + same-surface partial swaps, **dies silently after the first cross-surface shell-nav**. The handler was attached to a specific DOM node; the swap replaced that node; the new node has no listeners. Diagnostic clue: scroll-hide of a sticky bar, active-state toggle, or filter-pill click handler is fully functional on first page load, then "doesn't work" after navigating between surfaces.

DOM scroll events do NOT bubble — a `scroll` listener bound on `document` won't fire for inner-element scroll. So you can't sidestep with document delegation when the event class itself doesn't bubble. Click handlers can use document delegation, but they sometimes don't because the handler reads `event.target.closest(...)` which requires DOM presence.

## The fix — `htmx:afterSwap` rebind keyed off the swap target

```js
function bindAllPaneListeners() {
    document.querySelectorAll('[data-pane-name]').forEach((pane) => {
        // idempotent: skip if already bound (dataset marker or WeakSet)
        if (pane.dataset.scrollBound) return;
        pane.dataset.scrollBound = '1';
        pane.addEventListener('scroll', onScroll, { passive: true });
    });
}

document.addEventListener('DOMContentLoaded', bindAllPaneListeners);
document.addEventListener('htmx:afterSwap', (evt) => {
    // Limit rebind to swaps that actually replaced the binding parent or its subtree.
    const target = evt.detail.target;
    if (!target) return;
    if (target.id === 'shell-swap-target' || target.closest('[data-pane-name]')) {
        bindAllPaneListeners();
    }
});
```

Three axes the rebind needs right:

1. **Listen on `document`** (the only element that survives every swap). `evt.detail.target` tells you what got swapped.
2. **Gate the rebind by target** — re-running `bindAllPaneListeners()` on every `htmx:afterSwap` is wasteful when the swap was a partial that didn't replace the binding element. Gate on `target.id === 'shell-swap-target'` (or whatever your shell-nav swap target is) or `target.closest('[data-pane-name]')`.
3. **Idempotent rebind** — the bind function must short-circuit on already-bound elements (dataset marker / `WeakSet`). Otherwise a re-fired `htmx:afterSwap` (or a synthetic swap from a drawer/preview replacer per `HTMX_WIDGET_LIFECYCLE.md` §6) attaches a second listener and the handler fires twice.

## Recurrence — pattern matured across three independent surfaces

This class has appeared three times in independent surfaces of the same shell-architecture project:

1. **Tag-filter pill click handler** (per-checkbox local CSS-class toggle, not document-delegated) — pill DOM arrives via shell-fragment swap, click handler stuck. Resolved with document-level delegated `change` listener on `#filter-tags input[name="tags"]` + form-trigger dispatch.
2. **Navbar scroll-hide** — `navbar-scroll.js` binds `scroll` listeners to each `[data-pane-name]` pane at init. `outerHTML` swap of `#shell-swap-target` (the shell-nav swap container) replaces panes that contain the binding elements; navbar stays visible because no scroll fires. Resolved with `htmx:afterSwap` rebind.
3. **Sticky section-nav scroll-spy** — scroll-driven active-highlight (`shell-section-nav.js`) reads `[data-shell-section-jump]` chips that disappear when section-card surface gets shell-nav swapped. Resolved with the same `htmx:afterSwap` rebind pattern, plus a teardown branch that hides the affordance when no chips match the new centre surface.

Pattern is robust across DOM scroll, change events on dynamically-added inputs, and any class-list toggle on swap-replaced elements.

## Adjacent failure mode — scroll container ownership after a flex-stretch fix

Sometimes the listener IS still bound to the right element, but the **scroll itself** stopped happening on that element because a CSS layout change moved the `overflow: auto` to an inner child.

```scss
// Original — .shell-center owns overflow-y:auto, listener fires on it
.shell-center { overflow-y: auto; }

// Naive fix to stretch a content card on short content
.shell-center {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
}
.content-card {
    flex: 1 1 auto;
}
.content-card .card-content {
    overflow-y: auto;       // BUG — moved the scroll container off .shell-center
}
```

After this change, the user's scroll happens on `.card-content`, not `.shell-center`. The listener bound to `[data-pane-name="center"]` (= `.shell-center`) never fires. Symptom is **identical** to the listener-rebind class above (scroll-hide stops working) but the diagnosis path is different.

**Fix**: keep the scroll container on the pane parent. Use `flex: 1 0 auto; min-height: 100%` on the stretching child so the card stretches but overflow spills back to the pane parent.

```scss
.shell-center {
    display: flex;
    flex-direction: column;
    overflow-y: auto;       // PANE owns the scroll container
}
.content-card {
    flex: 1 0 auto;
    min-height: 100%;       // stretches but doesn't claim the overflow
}
// .card-content does NOT get overflow:auto
```

Checklist before any flex-stretch refactor inside a pane that owns a scroll listener:

- [ ] After my changes, does **the pane parent** still resolve to the user's scroll container? `findScrollContainer(innerEl)` walking up via `getComputedStyle(el).overflow` should land on the pane.
- [ ] If I'm tempted to add `overflow-y: auto` to an inner element to "make it scrollable", I'm probably re-claiming the scroll container — verify the pane listener still fires by scrolling and watching the listener's handler in the console.

This is the more diagnostically hostile of the two — the listener IS bound, the swap rebind IS running, but the user's scroll just happens elsewhere.

## What this reference doesn't cover

- **Widget re-init after a swap** — that's `HTMX_WIDGET_LIFECYCLE.md` §1–§5 (TipTap, mermaid, file-uploader, etc. — content INSIDE the swap target needs to re-bind itself).
- **Drawer/preview replacer synthetic events** — that's `HTMX_WIDGET_LIFECYCLE.md` §6 (custom body-replacer that fires `htmx:afterSettle` itself; binder needs to read `evt.detail.elt || evt.detail.target`).
- **Scroll position preservation across swap** — that's `HTMX_SCROLL_PRESERVATION.md` (preserving `scrollTop` of the entire pane, not the listener binding).

## Who relies on this

- Sticky-bar scroll-hide patterns in shell-architecture UIs (per-pane scroll observers).
- Per-list filter input handlers whose DOM gets `outerHTML`-swapped on form submit.
- Scroll-spy active highlights for in-page chip strips / TOCs.
- Any document-level binder added by a deferred-loaded module (per `LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md` — those binders also need the rebind contract if their target subtree can be swapped).
