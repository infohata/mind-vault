# CSS `display: contents` doesn't make children selector-transparent

**When this fires**: you wrap a group of flex / grid children in an intermediate `<div id="…">` so an HTMX `outerHTML` swap can replace them as one atomic unit, and you set the wrapper to `display: contents` so the flex / grid layout still treats the children as direct items of the outer container. Then your existing `.parent > .child` rules silently stop matching half the children.

The trap is the gap between two CSS subsystems: `display: contents` affects the **box tree** (which is what layout uses) but does NOT affect the **DOM tree** (which is what selectors evaluate against). They disagree, and selectors silently lose.

## The shape

The pre-wrapper structure:

```html
<div class="snap-container">              <!-- flex parent -->
  <div class="pane-wrapper-A">…</div>     <!-- direct flex child -->
  <section class="center-pane">…</section> <!-- direct flex child -->
  <div class="pane-wrapper-B">…</div>     <!-- direct flex child -->
</div>
```

```scss
.snap-container > .pane-wrapper-A,
.snap-container > .center-pane,
.snap-container > .pane-wrapper-B {
    flex: 0 0 100%;
    scroll-snap-align: start;
}
```

You decide to wrap two of those children in a swap-target `<div>` for HTMX:

```html
<div class="snap-container">
  <div id="hot-swap-target">              <!-- NEW intermediate; display: contents -->
    <div class="pane-wrapper-A">…</div>
    <section class="center-pane">…</section>
  </div>
  <div class="pane-wrapper-B">…</div>
</div>
```

```scss
.snap-container > #hot-swap-target {
    display: contents;
}
```

**What happens**:

- **Box tree** (layout): `display: contents` removes `#hot-swap-target`'s own box. Its children become flex items of `.snap-container` for layout purposes. Flex / grid / scroll-snap behaviour continues working as before. So far so good.
- **DOM tree** (selectors): the intermediate `<div>` is fully present. The selector `.snap-container > .pane-wrapper-A` no longer matches — `.pane-wrapper-A`'s parent is now `#hot-swap-target`, not `.snap-container`. The original SCSS rules silently no-op for the wrapped children.

Symptom shape: `pane-wrapper-B` (the unwrapped sibling) keeps its `flex: 0 0 100%` + `scroll-snap-align: start`. `pane-wrapper-A` and `center-pane` lose theirs — they collapse to intrinsic width, scroll-snap stops engaging on them, swipes feel "broken" or "stuck" because only one snap target is properly sized.

## The fix — symmetric widening, across every breakpoint

Widen every affected selector to also match through the intermediate:

```scss
.snap-container > .pane-wrapper-A,
.snap-container > .center-pane,
.snap-container > .pane-wrapper-B,
.snap-container > #hot-swap-target > .pane-wrapper-A,
.snap-container > #hot-swap-target > .center-pane {
    flex: 0 0 100%;
    scroll-snap-align: start;
}
```

The original direct-child selectors stay (so `pane-wrapper-B` and any future direct-child variants still match). The widened branch adds the through-the-intermediate path for the wrapped children.

## The asymmetric-fix anti-pattern (the actual bug surface)

The bug typically lands NOT when the wrapper is introduced and the developer forgets to widen anything, but when **only some breakpoints get the widening** while others are missed.

The teisutis IDEA-172 → IDEA-173 sequence is the canonical example:

1. IDEA-172 introduces `<div id="shell-swap-target">` with `display: contents` to enable shell-level HTMX `outerHTML` swaps.
2. The desktop pane-snap SCSS gets widened in the same commit:
   ```scss
   > .shell-pane-snap__workspace-wrapper,
   > .shell-pane-snap__preview-wrapper,
   > #shell-swap-target > .shell-pane-snap__workspace-wrapper { … }
   ```
3. The mobile pane-snap SCSS in a sibling `@media` block is **missed** — its selectors only listed direct-child variants.
4. Tests pass (no SCSS test layer; render-and-assert lives at the HTML level).
5. Desktop works fine. Mobile drawer-pane swipe is broken at ~50px; cold-load workspace pane is dead.
6. Symptom appears unrelated to the wrapper introduction. Initial diagnosis chases a JavaScript drawer-coordinator bug (visible side effect: drawer "wedged" state); a JS band-aid recovers the user-visible symptom by full-reloading the page. The actual CSS-selector-miss stays invisible for the entire PR cycle.
7. Months later, when the JS band-aid is investigated for retirement, the mobile SCSS selector miss is the load-bearing finding.

**Cost**: a JS band-aid that fires `window.location.reload()` on every popstate-with-frames (destroying every UX continuity guarantee the application makes), plus a multi-cycle IDEA filed to "investigate the drawer-coordinator wipe" that doesn't exist. All from one SCSS rule block missed during a structural insertion.

**Lesson**: when you insert a `display: contents` intermediate, audit **every** breakpoint's selectors that match the wrapped children — not just the breakpoint you happen to be testing in. Grep for the affected class names across the full SCSS tree:

```bash
grep -rn 'shell-pane-snap__workspace-wrapper\|shell-pane-snap__preview-wrapper\|shell-center' web/<app>/static/<app>/scss/
```

For each hit, check whether the selector path includes a route through the new intermediate. If not, widen it.

## Related selector-vs-box-tree mismatches

The same gap surfaces for any CSS feature that operates on the box tree:

- **`display: contents` and parent-state selectors**: `.parent:has(> .child)` doesn't match a child that lives one level deeper through a `display: contents` intermediate. The `:has()` selector still uses DOM hierarchy.
- **`display: contents` and `:nth-child`**: indexing is over the DOM siblings, not the effective flex siblings. A child that's index 1 in the intermediate is NOT index 1 of the outer container even though layout treats it as one.
- **CSS Counters / `counter-increment`**: counts up the DOM tree, not the box tree.

When in doubt: `display: contents` makes children **layout-transparent**, not **selector-transparent**. Anything CSS does at selector-evaluation time still sees the full DOM.

## When NOT to introduce the `display: contents` intermediate

If the layout doesn't require the children to be siblings of the outer container (i.e. you don't need flex / grid / scroll-snap to see them as direct items), don't use `display: contents` — wrap them in a normal block-level intermediate that has its own selector path you can target intentionally. The selector-vs-layout split only matters when layout DEMANDS sibling-of-parent semantics. For HTMX swap-target wrapping around content that doesn't participate in a flex / grid / scroll-snap parent, plain `display: block` (or `contents` only if the parent layout needs it) is the right default.

## Detection

Add to the structural-change checklist for any commit that introduces or moves a `display: contents` intermediate:

- [ ] List every CSS selector that previously matched the wrapped children's parent path.
- [ ] For each, decide: does the rule still apply through the new intermediate? If yes, widen. If no, leave unchanged.
- [ ] Walk EVERY breakpoint that has its own selector block. Mobile-specific media queries are the most common miss site (they're often last to be updated because they're at the bottom of the file).
- [ ] If the project has a CSS audit tool (stylelint, postcss-purify), run it on the affected breakpoints.

---

**Last Updated**: 2026-05-16 (initial — sourced from teisutis IDEA-173 root-cause attribution of the mobile pane-snap selector miss introduced during IDEA-172)
