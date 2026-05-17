---
name: mobile-ux-polish
description: Apply mobile + tablet touch-interaction patterns when authoring shell-extending surfaces with swipe gestures, scroll-snap panes, swipe drawers, sticky-on-scroll navbars, or iOS Safari quirk handling. Covers touch drag-vs-tap dual-signal discriminator, scroll-snap settle-timer debounce, deferred-clear flag vs wall-clock timeouts, cold-start instant vs runtime smooth scrollIntoView, and animation-preserving state-lag on close-paths. Pairs with django-frontend for HTMX/Alpine/Bulma fundamentals.
license: MIT
metadata:
  author: mind-vault
  version: '1.0'
---

# mobile-ux-polish

Touch + scroll-snap + animation-timing patterns for shell-extending mobile surfaces. The work isn't intellectually deep but its bug-density is — a 26-issue manual-eval cycle on a single shell-mobile IDEA isn't anomalous, it's the steady-state cost of mobile UX work that touches scroll-snap + touch + flex + reactive bindings simultaneously. Each pattern below is a tested defence against a class of bug that recurs every time a project adds or modifies a shell-extending touch surface. Apply at first authoring, not in the post-PR-review iteration.

**Pairs with:** [django-frontend](../django-frontend/SKILL.md) for HTMX / Alpine / Bulma / theming fundamentals — broader patterns surfaced in the same cycle (CSS min/max-height clamp, list-scoped HTMX swap, WCAG luminance picker, permanent-bind active-discriminator listeners) live in its references and apply beyond mobile work.

## When to use

TRIGGER when: an IDEA's plan or the live work touches ≥2 of — bottom-tab nav, swipe gestures, scroll-snap panes, sticky-on-scroll header/nav, touch-driven drawer dismiss, mobile-specific routing of cluster widgets (theme/lang/user-menu), iOS Safari quirk handling. Trigger phrasings: "mobile shell", "pane swipe", "iOS gotchas", "touch gesture", "scroll-snap", "drawer dismiss", "swipe to close", "responsive shell".

SKIP for: pure desktop UI work, backend-only work, content/copy edits, translation runs, deployment work, anything that doesn't touch a touch-input or scroll-snap surface.

## Patterns

### 1. Drag-vs-tap discriminator (dual-signal)

Pure `touchstart`/`touchend` flag tracking marks every tap as a drag. Click-driven actions then fire drag-only side effects. The discriminator must be set **only on touchmove past a small threshold** OR a structural signal change.

**Single-signal approach (insufficient)**: `touchmove` past 5-10px → `_isDragging = true`. Fails for short-fast swipes that fire too few touchmove events to trip the threshold (iOS Safari can deliver one or two touchmoves between touchstart and touchend on quick flicks). Also fails for "dirty screen" interrupted swipes that produce repeated few-pixel touchmoves none of which exceed the threshold.

**Dual-signal (correct)**:

1. `touchmove` past 5px → `_isDragging = true`.
2. ON `touchend`: if container's structural state (`scrollLeft`, `scrollTop`, `transform`, etc.) **changed** between touchstart-captured baseline and now → `_isDragging = true`. Catches everything the touchmove threshold misses.

```js
let dragStartX = null;
let dragStartScrollLeft = 0;
let isDragging = false;

el.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) return;
    dragStartX = e.touches[0].clientX;
    dragStartScrollLeft = el.scrollLeft;
    isDragging = false;
}, { passive: true });

el.addEventListener('touchmove', (e) => {
    if (dragStartX === null || e.touches.length !== 1) return;
    if (Math.abs(e.touches[0].clientX - dragStartX) > 5) isDragging = true;
}, { passive: true });

el.addEventListener('touchend', () => {
    if (el.scrollLeft !== dragStartScrollLeft) isDragging = true;
    // Defer the clear — see pattern 2.
    dragPendingClear = true;
});
```

Failure mode this addresses: close-on-swipe-out logic mis-fires on click-driven preview opens because the touch flag is set, then mid-animation `_onScroll` ticks get classified as drags. A pure threshold gate solves 99% but misses dirty-screen / short-fast swipes; the scroll-delta backup closes the last 1%.

### 2. `_dragPendingClear` deferred-clear (NOT wall-clock timeout)

Drag-state flags must persist through the entire snap-settle phase post-touchend. Wall-clock timeouts (`setTimeout(() => isDragging = false, 500)`) race with momentum-driven scroll: fast-flicks can keep the snap engine animating for 700ms+ on iOS, beyond any reasonable timeout shorter than the application's normal interaction cadence.

**Wrong**: timeout-based clear races with momentum.

```js
// DON'T
el.addEventListener('touchend', () => {
    setTimeout(() => { isDragging = false; }, 500);
});
```

**Right**: `_dragPendingClear` flag set on touchend; the next state-acting callback (settle-timer, paneChanged handler, etc.) reads `isDragging`, then clears both flags in one atomic step.

```js
// DO
el.addEventListener('touchend', () => {
    dragPendingClear = true;
});

// In your settle-timer / state callback:
if (someCondition && isDragging) {
    fireDragAction();
}
if (dragPendingClear) {
    isDragging = false;
    dragPendingClear = false;
}
```

The `dragPendingClear` flag survives ANY momentum duration and clears precisely when the snap settles, regardless of how long that takes.

Failure mode this addresses: a fast swipe ending at workspace can take ~600 ms from touchend to scroll-stop; a 500 ms wall-clock timeout clears `isDragging` before the settle-timer fires, the close is skipped, and the user is stranded with broken state.

### 3. Settle-timer debounce on scroll-snap state updates

When using CSS scroll-snap with programmatic `scrollIntoView({ behavior: 'smooth' })`, mid-animation `scroll` events read intermediate `scrollLeft` values that pass through other snap points. Acting on every scroll event causes spurious state transitions.

**Symptom**: state bouncing during smooth-scroll animations. E.g., setting `activePane = 'preview'` synchronously, then a mid-animation tick reads `scrollLeft = 1×width` (centre snap point) and resets to `'center'`, then settles at `2×width` and goes back to `'preview'`. Visible flicker; downstream side-effects fire on the transient state.

**Fix**: debounce state-acting reads behind a 100ms settle-timer. Reset on every scroll event; fire only when scroll has been stable for the timeout duration.

```js
function onScroll() {
    // Side effects safe to fire per-tick (visual-only, no state writes):
    updateLiveDimFeedback();

    // State-acting reads behind settle-timer:
    if (scrollSettleTimer) clearTimeout(scrollSettleTimer);
    scrollSettleTimer = setTimeout(() => {
        scrollSettleTimer = null;
        const idx = Math.round(el.scrollLeft / el.clientWidth);
        // ...read settled position, update activePane, dispatch events.
    }, 100);
}
```

100ms is a good default — long enough to let smooth-scroll animations finish (typically 200-400ms but the LAST scroll event fires once at settle), short enough to feel responsive on user-driven swipes.

Failure mode this addresses: `Alpine.effect` synchronously sets `activePane='preview'` on previewSurface depth change, then mid-animation `_onScroll` ticks read `scrollLeft` still at centre, reset to `'center'`, fire close logic. URL "blinks" — preview opens, immediately closes.

### 4. Cold-start `instant` vs runtime `smooth` scroll

`scrollIntoView({ behavior })` should be `'instant'` for mount-time placement and `'smooth'` for runtime user-driven moves. The default `'smooth'` looks great for runtime but visibly pans through intermediate panes during cold-start placement.

**Symptom**: cold-start with `?open=preview-id` URL animates the snap container from workspace (idx=0) through centre (idx=1) all the way to preview (idx=2). Looks like a movie reel; user expected the page to mount with preview already shown.

**Fix**: pass `'instant'` for cold-start callsites, `'smooth'` for runtime callsites. Most APIs have this as a parameter, not a global.

```js
goToPane(name, behavior /* 'smooth' | 'instant' */) {
    const target = el.querySelector(`[data-pane-name="${name}"]`);
    target.scrollIntoView({
        behavior: behavior || 'smooth',
        inline: 'start',
        block: 'nearest',
    });
}

// At init (cold-start):
goToPane(initialTarget, 'instant');

// At runtime (link click → previewSurface.open()):
goToPane('preview');  // smooth default
```

Failure mode this addresses: a user reports "cold opens / reload plays animations from workspace through centre to open preview on load". A single `behavior` param flip fixes it.

### 5. State-lag on close-paths to preserve animation

When a state change (`depth = 0`) triggers two simultaneous reactions:

- A: a CSS class binding that collapses the element's flex slot to 0
- B: a smooth-scroll-back animation

Reaction A applied immediately yanks reaction B's animation target (the now-zero-width pane is no longer a valid snap target). User sees an instant-vanish, not a smooth animation.

**Fix**: lag reaction A by ~animation-duration (300-400ms) via a separate state binding that delays the collapse until smooth-scroll completes.

```js
Alpine.data('previewWrapperCollapse', () => ({
    shouldCollapse: false,
    _collapseTimer: null,
    _prevDepth: 0,
    init() {
        const store = Alpine.store('previewSurface');
        const initialDepth = store ? store.depth : 0;
        this.shouldCollapse = initialDepth === 0;  // cold-start: collapse immediately
        this._prevDepth = initialDepth;
        Alpine.effect(() => {
            const depth = store ? store.depth : 0;
            if (depth > 0) {
                if (this._collapseTimer) clearTimeout(this._collapseTimer);
                this.shouldCollapse = false;
            } else if (this._prevDepth > 0) {  // closing, not cold-start
                this._collapseTimer = setTimeout(() => {
                    this.shouldCollapse = true;
                    this._collapseTimer = null;
                }, 350);
            }
            this._prevDepth = depth;
        });
    },
}));
```

Then bind the collapse class to `shouldCollapse` (not directly to depth):

```html
<div :class="{ 'pane--collapsed': shouldCollapse }">
```

Cold-start case (depth=0 from the start) collapses immediately on init — no animation needed when there's nothing to fade out.

Failure mode this addresses: clicking the preview's close-X dismisses the drawer instantly. `previewSurface.depth=0` triggers both the `goToPane('center')` smooth-scroll and the SCSS class collapse simultaneously. State-lag binding the class to a delayed signal lets the smooth-scroll play cleanly first.

## Anti-patterns

- ❌ "Mobile UX is just CSS" — patterns above are 70% JS, 30% CSS. Touch-event semantics + scroll-snap timing + reactive bindings dominate.
- ❌ Wall-clock timeouts for state cleanup (clear `isDragging` after 500ms). Mobile momentum + animation-duration combinatorics outrun any reasonable wall-clock estimate; flag-based deferred-clear scales correctly.
- ❌ Reaching for `--force` or `!important` to escape a bug class. Most patterns above are about right-shaped abstractions, not stronger overrides.
- ❌ Skipping the [manual-eval issues tracker](../wrap/references/MANUAL_EVAL_TRACKER.md) artefact "because it's just for this cycle" — once back-and-forth gets confused, you've already lost the cycle to ambiguity. Introduce the tracker at first regression, not at the fifth.

## When NOT to use these patterns

- Pure desktop UI with no touch / scroll-snap / sticky concerns — the touch-event and momentum patterns are noise there.
- Native-app surfaces (React Native, SwiftUI, Jetpack Compose) — these have their own gesture systems; the patterns here are browser-specific (CSS scroll-snap, DOM touchmove events).
- Static-site or SSR-only flows with no client interactivity — none of the patterns apply.

## Related material elsewhere

Patterns surfaced in the same IDEA-143 cycle but applicable beyond mobile work — routed to their broader homes:

- **CSS `min-height > max-height` clamps `max-height` upward** (Bulma/Bootstrap navbar collapse trap) → [django-frontend BASE_TEMPLATE.md § CSS spec hazards](../django-frontend/references/BASE_TEMPLATE.md#css-spec-hazards-min-height--max-height-clamp).
- **List-scoped HTMX swap to retain form focus** (sibling target + `hx-select`) → [django-frontend HTMX_PATTERNS.md § Form focus preservation via list-scoped swap](../django-frontend/references/HTMX_PATTERNS.md#form-focus-preservation-via-list-scoped-swap).
- **Permanent-bind + active-discriminator listeners** (don't migrate listeners on event; bind once, gate at event time) → [django-frontend ALPINE_HTMX_GOTCHAS.md § Gotcha 8](../django-frontend/references/ALPINE_HTMX_GOTCHAS.md#8-rebind-on-event-listener-migration-is-fragile--prefer-permanent-bind--active-discriminator).
- **WCAG luminance with sRGB linearization** (theme contrast picker) → [django-frontend BASE_TEMPLATE.md § Theme contrast picker (WCAG luminance)](../django-frontend/references/BASE_TEMPLATE.md#theme-contrast-picker-wcag-luminance).
- **Manual-eval issues tracker artefact** (stable Mn IDs across cycles) → [wrap MANUAL_EVAL_TRACKER.md](../wrap/references/MANUAL_EVAL_TRACKER.md).

## Relationship to rules

- [`RULE_self-sweep-before-push`](../../rules/RULE_self-sweep-before-push.md) — pre-push pyflakes / dead-import sweep applies inside mobile-UX-polish cycles too; the PR-review-cycle math is even more painful when manual-eval iteration is happening in parallel.
- [`RULE_cross-idea-amendments`](../../rules/RULE_cross-idea-amendments.md) — mobile-UX-polish IDEAs almost always amend earlier shell IDEAs' SCSS/JS; the bidirectional documentation contract is load-bearing here.
- [`RULE_rename-before-drop`](../../rules/RULE_rename-before-drop.md) — when a mobile cycle touches shared helpers (e.g. `goToPane` signature gains a `behavior` parameter), the per-commit-compilability discipline catches missed callers.

## Provenance

Surfaced during a mobile-shell sprint (bottom-tab nav + pane swipe + iOS Safari gotchas, 60+ commits, 26-issue manual-eval cycle). The five patterns above were lessons from the closing M23-M25 segment of that cycle; sibling patterns that surfaced alongside but apply beyond mobile work live in their proper homes (see Related material elsewhere).

Initial mind-vault landing was as `RULE_mobile-ux-polish-discipline` (PR #103); reshaped into a progressive-disclosure skill in the same PR — the trigger surface (touch + scroll-snap + drawer + iOS quirks) is narrow enough that on-demand activation is the right tradeoff against context-budget spend on every conversation, and the broader patterns belong with their stack-mates rather than bundled under a "mobile" rubric.

---

**Last Updated**: 2026-05-07
