# RULE_mobile-ux-polish-discipline

Cross-cutting patterns surfaced by surface-touching IDEAs that ship mobile + tablet + desktop interaction polish on a single shell. The work isn't intellectually deep but its bug-density is — a 26-issue manual-eval cycle on a single shell-mobile IDEA isn't anomalous, it's the steady-state cost of mobile UX work that touches scroll-snap + touch + flex + sticky + Alpine reactive bindings simultaneously.

Each pattern below is a tested defence against a class of mobile-UX bug that recurs every time a project adds or modifies a shell-extending surface. Apply the pattern at first authoring, not in the post-bugbot iteration.

## When this rule applies

Any IDEA whose plan includes ≥2 of: bottom-tab nav, swipe gestures, scroll-snap panes, sticky-on-scroll header/nav, touch-driven drawer dismiss, mobile-specific routing of cluster widgets (theme/lang/user-menu), iOS Safari quirk handling.

Trigger phrasings: "mobile shell", "pane swipe", "iOS gotchas", "touch gesture", "scroll-snap", "navbar hide on scroll", "drawer dismiss", "mobile dropdown".

## The patterns

### 1. CSS `min-height > max-height` clamps `max-height` upward

When you set `max-height: 0` on an element to collapse its layout slot, ANY inherited or framework-default `min-height` greater than 0 will silently defeat the collapse. Per CSS spec ([CSS Box Sizing Module Level 3 § 6.6](https://www.w3.org/TR/css-sizing-3/#min-size-properties)): "If `max-height` is less than `min-height`, max-height is set to min-height."

**Symptom**: layout slot doesn't collapse despite `max-height: 0` in the computed styles. Element disappears visually (via `transform` or `overflow: hidden` + `opacity: 0`) but takes its full reserved height.

**Probe**: in DevTools, check the element's `min-height` computed value. If non-zero, you've hit this trap.

**Fix**: when collapsing via max-height, also set min-height: 0 + padding-{top,bottom}: 0 + overflow: hidden. Apply to the modifier class, not the base — don't break the visible state.

```scss
.navbar.navbar--hidden {
    transform: translateY(-100%);
    min-height: 0;       // override Bulma's 3.25rem min on .navbar
    max-height: 0;
    padding-top: 0;
    padding-bottom: 0;
    overflow: hidden;
}
```

Frameworks that bite this trap by default: Bulma (`.navbar { min-height: 3.25rem }`), Bootstrap (`.navbar { min-height: 56px }` in some themes), any Tailwind config that adds a navbar utility with min-height.

Surfaced: teisutis IDEA-143 M20 cycle 5 — empty 3.25rem strip remained at top when navbar's `--hidden` class fired, despite `max-height: 0; transform: translateY(-100%)`. Cycles 1-4 chased the wrong trees (overflow:hidden on base broke dropdowns; margin-top: -3.25rem on shell-main broke sticky scroll context). The actual fix took 4 lines.

### 2. Drag-vs-tap discriminator (dual-signal)

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
    // Defer the clear — see pattern 3.
    dragPendingClear = true;
});
```

Surfaced: teisutis IDEA-143 M24 cycles 3-6 — close-on-swipe-out logic mis-fired on click-driven preview opens because the touch flag was set, then mid-animation _onScroll ticks were classified as drags. Threshold-only solved 99% but missed dirty-screen/short-fast swipe (M24 c6); scroll-delta backup closed it.

### 3. `_dragPendingClear` deferred-clear (NOT wall-clock timeout)

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

Surfaced: teisutis IDEA-143 M24 cycle 5 — fast swipe ending at workspace took ~600ms from touchend to scroll-stop; 500ms timeout cleared `isDragging` before the settle-timer fired, close was skipped, user stranded with broken state.

### 4. Settle-timer debounce on scroll-snap state updates

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

Surfaced: teisutis IDEA-143 M24 cycle 3 — Alpine.effect synchronously set `activePane='preview'` on previewSurface depth change, then mid-animation `_onScroll` ticks read `scrollLeft` still at centre, reset to `'center'`, fired close logic. URL "blinked" — preview opened, immediately closed.

### 5. Permanent-bind + active-discriminator (NOT rebind-on-event)

When listening to per-X events (per-pane scroll, per-tab focus, per-region resize) where X changes over time, the natural pattern of "rebind listener on X-change-event" is fragile. Change events have edge cases that don't fire (short-circuits, equality early-returns, race conditions).

**Symptom**: listener bound to a stale element after a state transition. Behaviour silently dies for affected users.

**Fix**: bind permanently to ALL candidate sources at init. Each handler reads a discriminator (DOM attribute mirrored from state, or a global selector match) at event time and short-circuits if its source isn't currently active.

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

The active-discriminator is mirrored from reactive state via a single binding (Alpine `:data-active-pane="activePane"`, React `data-active-pane={activePane}`, etc.). Subscribers no longer migrate on `paneChanged` events — they self-route from a single source of truth.

Surfaced: teisutis IDEA-143 M25 — `navbar-scroll.js` migrated its single scroll listener on `paneChanged`. Close paths whose `goToPane('center')` snap landed on a pane that was already `activePane='center'` short-circuited `paneChanged` (`next === activePane` early-return), so the rebind never fired. Listener stayed attached to the off-screen drawer's scroll container; nav-hide silently broke after every drawer close.

### 6. Cold-start `instant` vs runtime `smooth` scroll

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

Surfaced: teisutis IDEA-143 M24 cycle 3 — user reported "cold opens= reload plays animations from workspace through center to open preview on load". Single param flip fixed it.

### 7. State-lag on close-paths to preserve animation

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

Surfaced: teisutis IDEA-143 M23 — clicking the preview's close-X dismissed the drawer instantly. `previewSurface.depth=0` triggered both the goToPane('center') smooth-scroll and the SCSS class collapse simultaneously. State-lag bound the class to a delayed signal; smooth-scroll plays cleanly.

### 8. List-scoped HTMX swap to retain form focus

When an HTMX swap target wraps a form input, every keystroke that triggers a hx-fetch swaps the form node — focus drops, IME state lost, caret position lost. `hx-preserve` on the input is fragile; the surrounding form's trigger re-bind around the wholesale swap drops focus regardless.

**Fix**: scope the swap to a sibling element (the result list) that does NOT include the form. Use `hx-target` + `hx-select` to extract the relevant slice from the same fragment endpoint response.

```html
<form hx-get="{% url '...' %}"
      hx-target="#result-list"          <!-- swap target: just the list -->
      hx-select="#result-list"          <!-- which part of response to swap -->
      hx-swap="outerHTML"
      hx-trigger="keyup changed delay:200ms from:input[name='q']">
    <input type="text" name="q" placeholder="..." />
</form>

<ul id="result-list">
    {% for item in items %}…{% endfor %}
</ul>
```

The form/input is never touched across requests; focus + caret + IME state are preserved by structure, not by preservation tricks.

Surfaced: teisutis IDEA-143 M14 cycles 1-2 — initial fix was `hx-preserve="true"` on the input; focus still dropped after 1-2 keystrokes (form's trigger re-bind via outerHTML on the wrapper id swapped the form node anyway). List-scoped target retained focus indefinitely.

### 9. WCAG luminance with sRGB linearization

The W3C-correct relative luminance formula requires gamma-decoded RGB values before applying the BT.709 coefficients. Most hand-written shortcuts skip the linearization step and produce wrong contrast picks for medium-tone colours.

**Wrong** (non-linear):

```python
r, g, b = [c / 255.0 for c in rgb]
luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b   # WRONG — gamma-encoded
return '#181818' if luminance > 0.179 else '#ffffff'
```

**Right** (linearized per W3C spec):

```python
def _linearize(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

r_lin, g_lin, b_lin = [_linearize(c / 255.0) for c in rgb]
luminance = 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
return '#181818' if luminance > 0.179 else '#ffffff'
```

The 0.179 crossover threshold is calibrated against linearized luminance. Without the linearization step, medium-tone backgrounds (#444–#666 range) get wrong-contrast foreground picks — `#555555` returns dark text at ~2.1:1 contrast when WCAG AA requires the white-text pick at ~7.6:1.

Reference: [WCAG 2.1 § Relative luminance](https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).

Surfaced: teisutis IDEA-143 — bugbot review 4240346456 caught the gamma-encoded shortcut in the project's `on_color` template filter. The luminance computation is a recurring need (avatar foreground, badge foreground, alert text on themed backgrounds); the W3C-spec implementation should be a project-local helper, not re-derived per surface.

## Manual-eval issues tracker pattern

For any IDEA whose plan includes a manual-evaluation gate (eval-gate flag in frontmatter, OR plan section listing manual scenarios), maintain an in-archive `MANUAL_EVAL_ISSUES.md` tracker with stable identifiers across cycles. Pattern:

```markdown
| ID | Surface / scope | Severity | Description | Status | Fix SHA |
|---|---|---|---|---|---|
| M0 | Bugbot review | medium | Scroll events don't bubble; drilling fix. | 🟢 VERIFIED | abc1234 — confirmed 2026-05-06 |
| M1 | Centre / drawer panes | high | Long Lithuanian compounds overflow narrow panes. | 🟢 VERIFIED | def5678 |
| ... |
```

User reports regressions with stable IDs (`M3 reproduces on iPhone Safari`, `M14 still broken`); agent fixes; user verifies in-place by changing emoji + appending commit SHA. The cycle continues until all rows are 🟢. The tracker artefact lives in the IDEA's archive dir alongside the plan + manual-eval-checklist.

Why this works: stable identifiers cut ambiguity in fast back-and-forth ("M17 cycle 11" is unambiguous; "the user-menu thing" requires cross-referencing). Multi-cycle entries capture history (M17 went through 11 cycles before the right Bulma-touch-range vs `@include mobile` split landed). Severity column (high / medium / low) lets the human prioritise verification order; low-severity polish can defer.

Surfaced: teisutis IDEA-143 — 26-issue, 60+-commit cycle. The tracker was retroactively introduced when ad-hoc "user reports a thing → I fix → user reports a different thing" descriptions started getting confused. After introduction, no further confusion; every reference was unambiguous.

## Anti-patterns

- ❌ "Mobile UX is just CSS" — interaction patterns above are 70% JS, 30% CSS. Touch-event semantics + scroll-snap timing + Alpine reactive bindings dominate.
- ❌ Assuming the bug is in the obvious surface — M20 was actually a CSS spec compliance issue (min/max-height clamping), not a navbar problem. Probe computed styles before assuming the root cause.
- ❌ Reaching for `--force` or `!important` to escape a bug class. Most patterns above are about right-shaped abstractions, not stronger overrides.
- ❌ Skipping the manual-eval-tracker artefact "because it's just for this cycle" — once back-and-forth gets confused, you've already lost the cycle to ambiguity. Introduce the tracker at first regression, not at the fifth.
- ❌ Wall-clock timeouts for state cleanup (clear `isDragging` after 500ms). Mobile momentum + animation duration combinatorics outrun any reasonable wall-clock estimate; flag-based deferred-clear scales correctly.

## Relationship to other rules

- [`RULE_self-sweep-before-push`](RULE_self-sweep-before-push.md) — pre-push pyflakes + dead-import sweep applies inside mobile-UX-polish cycles too; the bugbot-cycle math is even more painful when manual-eval iteration is happening in parallel.
- [`RULE_cross-idea-amendments`](RULE_cross-idea-amendments.md) — mobile-UX-polish IDEAs almost always amend earlier shell IDEAs' SCSS/JS; the bidirectional documentation contract is load-bearing here.
- [`RULE_rename-before-drop`](RULE_rename-before-drop.md) — when a mobile cycle touches shared helpers (e.g. `goToPane` signature gains a `behavior` parameter), the per-commit-compilability discipline catches missed callers.

## Provenance

Surfaced 2026-05-07 in teisutis project, IDEA-143 (mobile bottom-tab nav + pane swipe + iOS Safari gotchas), [PR #432](https://github.com/infohata/teisutis/pull/432). 60+ commits, 26-issue manual-eval cycle (M0-M25), all 9 patterns above were lessons from specific finding cycles. The cumulative cost of *not* having this rule was the 60+ commits; the cost of having had it would have been ~15 commits with the same final state.

---

**Last Updated**: 2026-05-07
