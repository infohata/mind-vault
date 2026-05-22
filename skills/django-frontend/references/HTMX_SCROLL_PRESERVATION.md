# HTMX scroll-position preservation on prepend swaps

A complete primitive for the "Load older" / inverse-pagination class of UI: when an HTMX swap prepends content to the top of a scrolling region, the user's reading position should not jump. The naive approaches all have failure modes; this reference catalogues them and presents the robust pattern.

Load this reference when:

- Building a "Load older" / "Show previous" / chat-history-style pagination flow.
- Implementing infinite scroll that prepends rather than appends.
- Reviewing any HTMX swap that uses `hx-swap="afterbegin"` against a scrollable container.

## The problem

Default browser behaviour: when a scrolling container's `scrollHeight` grows because content was prepended, the visible items shift downward by exactly the height of the prepend. The user's reading position (which they were anchored on visually) moves out of view. For a 1-item prepend this looks like a small jitter; for a 10-item Load-older click it looks like the page content jumps two screens away.

Goal: after the swap, every item that was previously visible is still in the same on-screen position. The user perceives the prepend as new content appearing above the fold, not as their reading position changing.

The mechanic: capture some reference position before the swap, measure the same reference after the swap, compute the delta, adjust `scrollTop` by the delta.

## Three approaches, three failure modes

### Approach A: scrollHeight diff

```javascript
// onBeforeSwap
oldScrollHeight = scrollContainer.scrollHeight;
oldScrollTop = scrollContainer.scrollTop;

// onAfterSwap
const delta = scrollContainer.scrollHeight - oldScrollHeight;
scrollContainer.scrollTop = oldScrollTop + delta;
```

Looks clean. **Breaks under concurrent mutation.** If anything else modifies the container between beforeSwap and afterSwap — a websocket-appended message at the bottom, an out-of-band size change, a deferred image load completing — `scrollHeight` grows from BOTH the prepend AND the unrelated mutation. The delta conflates the two and over-adjusts, yanking the user downward. In a chat surface (websocket-driven appends arriving constantly), this happens basically every Load-older click during peak conversation.

### Approach B: previousElementSibling offsetHeight summation

```javascript
// onBeforeSwap: mark the swap target's first child as the reference point.
target.firstElementChild?.setAttribute('data-anchor-old-top', '1');

// onAfterSwap: sum every sibling now appearing before the marker.
const marker = target.querySelector('[data-anchor-old-top]');
let delta = 0;
let sibling = marker.previousElementSibling;
while (sibling) {
    delta += sibling.offsetHeight;
    sibling = sibling.previousElementSibling;
}
scrollContainer.scrollTop = oldScrollTop + delta;
```

Robust to concurrent mutations BELOW the marker (those don't appear in the previousElementSibling walk). **Breaks when the prepend subtree contains a `display: contents` wrapper.** Per CSS spec, elements with `display: contents` generate no principal box; their `offsetHeight`, `offsetWidth`, and `getBoundingClientRect()`-derived height/width all return `0`. The wrapper's children DO participate in layout, but the wrapper itself contributes nothing to the `offsetHeight` summation. Result: `delta = 0` regardless of how much content was prepended, scroll position unchanged, the bug is silent (no error, no warning, no console log).

The HTMX OOB-swap pattern frequently uses `display: contents` wrappers when a single response needs to deliver TWO independent root elements (one for the actual swap, one for `hx-swap-oob="true"`) — the wrapper's role is to make HTMX treat them as siblings without polluting layout. So this pattern shows up specifically in the kind of pagination response shape this reference is solving for.

### Approach C: marker offsetTop diff (recommended)

```javascript
// onBeforeSwap
const oldTop = target.firstElementChild;
if (oldTop) {
    oldTop.setAttribute('data-anchor-old-top', '1');
    scrollContainer.dataset.anchorOldOffset = String(oldTop.offsetTop);
}
scrollContainer.dataset.anchorScrollTop = String(scrollContainer.scrollTop);

// onAfterSwap
const oldOffsetTop = Number(scrollContainer.dataset.anchorOldOffset);
const oldScrollTop = Number(scrollContainer.dataset.anchorScrollTop);
delete scrollContainer.dataset.anchorOldOffset;
delete scrollContainer.dataset.anchorScrollTop;

const marker = target.querySelector('[data-anchor-old-top]');
if (!marker) return;

const delta = marker.offsetTop - oldOffsetTop;
marker.removeAttribute('data-anchor-old-top');

scrollContainer.scrollTop = oldScrollTop + delta;
```

`offsetTop` is the marker's position relative to its `offsetParent` (the scrollable container, in this layout). It's computed from layout, which means:

- The marker itself must be a regular box (the only constraint — don't put `display: contents` on the FIRST item of the list).
- Any wrappers, nested or not, between the marker and the offsetParent get accounted for as part of layout. `display: contents` wrappers contribute the height of THEIR children (because the children participate in layout even though the wrapper doesn't).
- Concurrent mutations BELOW the marker don't change `marker.offsetTop` (the marker is positioned by what's ABOVE it, which is what we want).

So `delta = marker.offsetTop_after - marker.offsetTop_before` measures exactly the height that was prepended above the marker, regardless of subtree shape, regardless of below-marker mutations.

The one residual exposure: a foreign script that prepends ABOVE the marker BETWEEN beforeSwap and afterSwap WOULD shift `marker.offsetTop`, and we'd compensate for both our prepend and theirs. This is rare (single HTMX swap windows are short) and arguably correct (if foreign content lands above the marker, the user expects to scroll past it too). Approach B has identical exposure here. Approach A has WORSE exposure because it conflates above- and below-marker mutations.

## Reference implementation

```javascript
/**
 * Generic HTMX scroll-position-preservation primitive. Listens at
 * ``document.body`` for ``htmx:beforeSwap`` and ``htmx:afterSwap``;
 * adjusts ``scrollTop`` of the nearest ``[data-scroll-anchor]``
 * ancestor of the swap target so the user's visual position is
 * preserved across prepend swaps.
 *
 * Markup contract:
 *
 *   <div data-scroll-anchor style="overflow-y: auto;">
 *     <ul id="message-list" hx-swap-oob="afterbegin" ...>
 *       ...messages...
 *     </ul>
 *   </div>
 *
 * The ``data-scroll-anchor`` ancestor is the scrolling container (the
 * element whose ``scrollTop`` we adjust). The swap target's first
 * child is marked as the reference point on beforeSwap; on afterSwap
 * we read its new ``offsetTop`` and adjust by the diff.
 */
(function () {
    'use strict';

    var ANCHOR_ATTR = 'data-scroll-anchor';
    var MARKER_ATTR = 'data-anchor-old-top';
    var SCROLLTOP_KEY = 'anchorScrollTop';
    var MARKER_OFFSET_KEY = 'anchorOldOffset';

    function findAnchor(startEl) {
        if (!startEl || !startEl.closest) return null;
        return startEl.closest('[' + ANCHOR_ATTR + ']');
    }

    function onBeforeSwap(evt) {
        var target = evt && evt.detail && evt.detail.target;
        if (!target) return;
        var anchor = findAnchor(target);
        if (!anchor) return;

        var oldTop = target.firstElementChild;
        if (oldTop) {
            oldTop.setAttribute(MARKER_ATTR, '1');
            anchor.dataset[MARKER_OFFSET_KEY] = String(oldTop.offsetTop);
        }
        anchor.dataset[SCROLLTOP_KEY] = String(anchor.scrollTop);
    }

    function onAfterSwap(evt) {
        var target = evt && evt.detail && evt.detail.target;
        if (!target) return;
        var anchor = findAnchor(target);
        if (!anchor) return;

        var rawTop = anchor.dataset[SCROLLTOP_KEY];
        delete anchor.dataset[SCROLLTOP_KEY];
        if (rawTop === undefined) return;

        var oldScrollTop = Number(rawTop);
        if (isNaN(oldScrollTop)) return;

        var rawOffset = anchor.dataset[MARKER_OFFSET_KEY];
        delete anchor.dataset[MARKER_OFFSET_KEY];
        if (rawOffset === undefined) return;

        var oldOffsetTop = Number(rawOffset);
        if (isNaN(oldOffsetTop)) return;

        var marker = target.querySelector('[' + MARKER_ATTR + ']');
        if (!marker) return;

        var delta = marker.offsetTop - oldOffsetTop;
        marker.removeAttribute(MARKER_ATTR);
        anchor.scrollTop = oldScrollTop + delta;
    }

    function attach() {
        if (!document.body) return;
        document.body.addEventListener('htmx:beforeSwap', onBeforeSwap);
        document.body.addEventListener('htmx:afterSwap', onAfterSwap);
    }

    if (document.body) attach();
    else document.addEventListener('DOMContentLoaded', attach);
})();
```

## Robustness checklist (what this primitive handles correctly)

| Scenario | Handled? |
|---|---|
| Single-prepend swap (Load older clicked once) | ✅ |
| Multi-prepend (Load older clicked rapidly N times) | ✅ — each swap is a fresh beforeSwap/afterSwap pair |
| `display: contents` wrapper anywhere in the prepend subtree | ✅ — marker offsetTop diff sees wrapper's children's contribution to layout |
| Nested wrappers (multiple `<div>` levels around the items) | ✅ — same reason |
| Concurrent mutations BELOW the marker (websocket appends in chat) | ✅ — they don't change marker.offsetTop |
| Image lazy-loading completes during the swap window | Depends on where: above-marker → counted in delta, below-marker → ignored. The above-marker case is rare and arguably-correct. |
| Empty initial list (no firstElementChild → no marker) | ✅ — primitive no-ops; afterSwap finds no marker, returns early |
| Marker removed by a different handler before afterSwap | ✅ — primitive no-ops; marker.querySelector returns null, return early |
| Multiple `[data-scroll-anchor]` containers on the page | ✅ — each swap target finds its closest ancestor anchor |

## Things this primitive does NOT do

- **Animate the scroll adjustment.** The change is instantaneous because the user's visual position should not change at all. Adding a smooth-scroll easing would create a brief jitter where the user IS moving relative to content.
- **Auto-attach to specific containers.** Consumers opt in by adding `data-scroll-anchor` to the scrolling element. This is by design — random page-level swaps shouldn't trigger scroll-position math; the consumer marks which containers care.
- **Handle `hx-swap` other than ones that mutate the swap target's child list.** The primitive's contract is: target is a container whose `firstElementChild` becomes the marker. `outerHTML` and `replaceWith` swaps replace the entire target, eliminating the marker. Use a different pattern for those (typically `hx-preserve` on the marker if it's a stable element).

## Test pattern

The math is unit-testable in JSDOM with a fake layout. The trickier verification is end-to-end against a real browser — JSDOM doesn't compute layout, so `offsetTop` values are all 0 in tests, defeating the math. Strategy:

- Unit-test the **directive emission** (markup-level — does the consumer's swap target carry `data-scroll-anchor`? does the marker get applied? does the swap response contain the right structure?).
- Manual smoke for the actual scroll-preservation behaviour. Three test cases:
  1. Single Load-older click — note where a visible item is centred before, click, confirm item still centred after.
  2. Multi-page traversal to terminal state — click N times, terminal label appears, no further fetches.
  3. Browser console hygiene — no JS errors, no `htmx:targetError` events, throughout.

If the project supports Playwright/Selenium, automate (1)-(3). Otherwise the manual checklist is the merge gate.

The lesson generalises beyond HTMX: any DOM math that walks `previousElementSibling`/`nextElementSibling` summing `offsetHeight` is fragile to `display: contents` wrappers. The `offsetTop`-diff approach (capture before, measure after, subtract) is the more robust idiom — works for any "how much did THIS element move" question regardless of subtree shape.
