# Scroll-spy active-highlight patterns

**Scope**: keeping an in-page "active section" indicator (chip strip, TOC nav, sticky sub-nav) in sync with the user's scroll position. Two non-obvious gotchas that bite first implementations: choice of observer mechanism, and conditional state that mutates layout.

## Gotcha 1 — IntersectionObserver flickers; scroll-driven is monotonic

The natural-feeling first implementation uses `IntersectionObserver` to detect section visibility:

```js
const observer = new IntersectionObserver((entries) => {
    // BUG — entries only carries sections that JUST crossed the threshold,
    // not all observed sections. Picking "best from entries" bounces between
    // adjacent sections at every threshold crossing.
    const visible = entries.filter((e) => e.isIntersecting);
    const best = visible[0] || entries[0];
    setActiveChip(best.target.id);
}, { threshold: [0, 0.25, 0.5, 0.75, 1] });
```

Symptom: as the user scrolls past a section boundary, the active chip flickers back-and-forth between the leaving and entering sections — sometimes for hundreds of milliseconds before settling. Worse on slower devices.

Root cause: `entries` in an IO callback only contains targets whose intersection ratio *just* changed. If section A is leaving (ratio dropping from 0.5 → 0.25) and section B is entering (0.0 → 0.25), they both appear in `entries` but the "best" pick is non-deterministic. The callback fires once per threshold crossing, and consecutive crossings select different "best" entries.

**Fix — rAF-throttled scroll handler that reads ALL targets every frame**:

```js
function recomputeActive() {
    const targets = document.querySelectorAll('[data-shell-section-jump]');
    let activeId = null;
    let bestDistance = Infinity;
    targets.forEach((chip) => {
        const sectionId = chip.dataset.shellSectionJump;
        const section = document.getElementById(sectionId);
        if (!section) return;
        // Pick the section whose top is closest to (but not below) a fixed
        // anchor offset (e.g. 80px from viewport top).
        const rect = section.getBoundingClientRect();
        const distance = Math.abs(rect.top - 80);
        if (rect.top <= 80 && distance < bestDistance) {
            bestDistance = distance;
            activeId = sectionId;
        }
    });
    setActiveChip(activeId);
}

let rafScheduled = false;
function onScroll() {
    if (rafScheduled) return;
    rafScheduled = true;
    requestAnimationFrame(() => {
        rafScheduled = false;
        recomputeActive();
    });
}

paneEl.addEventListener('scroll', onScroll, { passive: true });
```

Why scroll-driven is monotonic: every frame reads the SAME data (geometry of all targets); there's no "best from changes" ambiguity. The picked active section is a pure function of scroll position. As scroll progresses, the picked section advances or retreats by one monotonically — no oscillation.

`{ passive: true }` ensures the scroll handler doesn't block scrolling; rAF batches geometry reads to once per frame. Performance is comparable to IO for typical chip counts (~5-10 sections).

## Gotcha 2 — layout-stable conditional state (no font-weight changes on active)

The natural-feeling first implementation makes the active chip bolder:

```scss
.shell-chip {
    color: var(--text-secondary);
    font-weight: 400;
    transition: color 200ms;
}
.shell-chip--active {
    color: var(--color-brand);
    font-weight: 600;          // BUG — wider letters shift sibling widths
}
```

Symptom: as the active chip changes during scroll, sibling chips visibly shift position by a few pixels. The visual ripple feels "buggy" even when the scroll-spy logic is correct.

Root cause: font-weight is a layout-affecting property — heavier weights have wider glyph metrics. In a flex/inline-flex chip strip, a chip's intrinsic width depends on its rendered weight. Toggling active state mid-scroll re-flows the strip; siblings move.

**Fix — use color-only differentiation for any conditional state**:

```scss
.shell-chip {
    color: var(--text-secondary);
    font-weight: 500;          // fixed weight
    transition: color 200ms, background-color 200ms;
}
.shell-chip:hover {
    color: var(--text-primary);
    background-color: var(--bg-tertiary);
}
.shell-chip--active {
    color: var(--color-brand);     // color shift only
    background-color: var(--bg-tertiary);
}
```

The broader principle: any CSS property that affects intrinsic dimensions of the conditionally-styled element MUST be excluded from the conditional state, OR compensated by a same-axis reservation. Properties to avoid (or pre-reserve) in scroll-spy / hover active states:

- `font-weight` (glyph widths)
- `font-style: italic` (slanted glyphs are slightly wider on some font families)
- `font-size` (obvious — but sometimes hidden in `font-shorthand` declarations)
- `padding` / `margin` (own-element width)
- `border-width` (own-element width unless `box-sizing` accounts + outline used instead)
- `letter-spacing` (cumulative)
- `text-transform: uppercase` (some font families have different uppercase widths)

Properties that are layout-safe:
- `color` (text only)
- `background-color` (no extrinsic effect)
- `box-shadow` (extrinsic; doesn't affect layout flow)
- `outline` (doesn't take layout space, unlike border)
- `text-decoration` (underline/strikethrough; visual but layout-neutral)
- `opacity` (visual; no layout effect)

When semantic emphasis NEEDS more weight than color alone (accessibility, brand voice), use a same-axis compensation:

```scss
.shell-chip {
    font-weight: 500;
}
.shell-chip--active {
    font-weight: 600;
}
// Reserve width for the heaviest state so layout doesn't flow:
.shell-chip::before {
    content: attr(data-label);
    visibility: hidden;
    height: 0;
    overflow: hidden;
    font-weight: 600;          // pre-claim the heaviest variant
    display: block;
}
```

This is more code than is usually justified. Default: color-only.

## Related references

- [`LISTENER_REBIND_ON_SWAP.md`](LISTENER_REBIND_ON_SWAP.md) — when the scroll-spy chip strip lives outside a swap target but the section cards live inside one, the chips → sections binding needs an `htmx:afterSwap` rebind. Adjacent failure mode (scroll container ownership after a flex-stretch fix) also breaks scroll-spy silently.
- [`HTMX_SCROLL_PRESERVATION.md`](HTMX_SCROLL_PRESERVATION.md) — preserving the scroll position across a swap is orthogonal: scroll-spy worries about *where the user scrolled to*, scroll preservation worries about *not losing that position when a swap fires*.
