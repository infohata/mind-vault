# SCSS responsive patterns — shared styling that changes at a breakpoint

Three patterns for the recurring problem "a visual treatment must be shared between a desktop control and a mobile control, but the dimension or rule differs at a breakpoint." All surfaced together while building a mobile edge-affordance that mirrored a desktop drawer edge-control. Sibling to `CSS_DISPLAY_CONTENTS_SELECTOR_TRAPS.md` (CSS layout traps) and `SCSS_VENDOR_IMPORT.md` (SCSS import order).

This is the **SCSS slice** of a mobile edge-affordance rail. The placement doctrine (reserved gutter, permanent-vs-gated sides) is in [`APP_SHELL_LAYOUT.md`](APP_SHELL_LAYOUT.md) § *Edge-affordance lips*; the JS/UX/architecture half (decouple from the snap engine, iOS fixed-ancestor trap, z-index ladder, adjacent-pane reveal model, ship-static-defer-animation) is in [`mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md`](../../mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md).

## 1. `@extend` cannot cross a `@media` boundary — use a `@mixin`

When two selectors should share a block of declarations AND at least one of them lives inside a `@media` query, **you cannot `@extend` a placeholder** — use a `@mixin` and `@include` it in both places.

```scss
// ❌ BROKEN — placeholder defined outside @media, extended from inside it
%edge-lip { background: transparent; &::before { … } }

.drawer__edge-control { @extend %edge-lip; }     // top-level — fine

@media (max-width: 768px) {
  .pane-lip { @extend %edge-lip; }               // ERROR: "You may not @extend
}                                                 // selectors across media queries"
```

```scss
// ✅ CORRECT — a mixin inlines the declarations at each call site
@mixin edge-lip { background: transparent; &::before { … } }

.drawer__edge-control { @include edge-lip; }      // desktop

@media (max-width: 768px) {
  .pane-lip { @include edge-lip; }                // media-gated consumer — fine
}
```

**Why**: `@extend` works by *grouping selectors* onto a shared declaration block in the compiled output. Selectors in different `@media` contexts compile to different at-rule scopes that can't be grouped, so Sass refuses (rather than silently duplicating). A `@mixin` sidesteps this entirely — it copies the declarations into each call site, so each lands in its own (possibly media-gated) scope.

**Rule of thumb**: the moment a shared style block has even one media-gated consumer, reach for `@mixin`, not `%placeholder`. Placeholders are for grouping top-level selectors only.

### The compile-path-masking trap (verify on the STRICT compiler)

This error is **compiler-path-dependent**. One build path (e.g. a permissive `make static` / libsass invocation) can tolerate or silently drop the cross-media `@extend`, while a stricter path (e.g. the dart-sass recompile a Playwright/e2e harness runs) hard-errors. If your fast inner-loop build is the permissive one, the failure won't surface until CI / e2e — late and confusing.

**Mitigation**: when touching shared SCSS, run the project's *strictest* SCSS compile before pushing (the one the e2e/CI gate uses), not just the dev-loop build. A green `make static` is necessary but not sufficient.

## 2. Cascading CSS custom property = one source for a responsive footprint

When a single dimension must (a) change at a breakpoint AND (b) be consumed by multiple components, define it once as a custom property on the root element with a `@media` override — don't scatter the breakpoint across every consumer's own media query.

```scss
html.app-shell {
  --edge-gutter: 1.5rem;                          // desktop default
}
@media (max-width: 768px) {
  html.app-shell { --edge-gutter: 1rem; }         // single override point
}

// Consumers reference the token — no per-component @media needed:
.drawer__body   { padding-inline: var(--edge-gutter); }
.drawer__header { padding-inline: var(--edge-gutter); }
.pane-lip       { width: var(--edge-gutter); }
.shell-center   { padding-inline: var(--edge-gutter); }  // mobile gutter for the lip
```

**Why it beats per-component media queries**: the breakpoint value lives in exactly one place, so changing it (or adding a third breakpoint) is a one-line edit instead of N. Consumers stay declarative and breakpoint-agnostic. The cascade does the work — a custom property set on the root re-resolves for every consumer when the `@media` override fires.

**When NOT to**: if only one consumer needs the value, a plain variable or inline media query is simpler — the token earns its keep when ≥2 consumers share the responsive dimension.

## 3. Additive-padding collapse — designate ONE gutter owner, zero the rest

Nested padded containers **stack** their horizontal padding. On a wide viewport the sum looks fine; on a narrow pane (≤~360px) the same nesting crushes content into a thin column. The fix is not "shave each layer a bit" — it's to designate a single owner of the horizontal gutter and zero every nested layer at the constrained breakpoint.

```scss
// Symptom: drawer body 1.5rem + inner card-content 1.5rem + an ad-hoc .p-4 (1rem)
//          = ~4rem of stacked horizontal padding on a 320px pane.

@media (max-width: 768px) {
  // The PANE BODY owns the one horizontal gutter (= the responsive token):
  .drawer__body { padding-inline: var(--edge-gutter); }   // 1rem
  // Every nested layer zeros horizontal padding so it doesn't add:
  .drawer__body .card-content { padding-inline: 0; }
  .inner-preview__body        { padding-inline: 0; }
  // (and drop ad-hoc .p-4 / px-* wrappers in the markup)
}
```

**Principle**: in a nested-container layout, exactly one element owns the horizontal gutter; all descendants get `0` horizontal at the breakpoint where space is tight. Vertical padding can stay (it doesn't compound a width problem). When a deeply-nested surface still "feels padded" on mobile, this is almost always the cause — find the owner, zero the rest.

**Decision heuristic**: the gutter owner should be the outermost element that defines the surface's edge (the pane/drawer body), so the single gutter equals the edge clearance you actually want; everything inside fills to it.
