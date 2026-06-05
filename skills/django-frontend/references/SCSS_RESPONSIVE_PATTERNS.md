# SCSS responsive patterns — shared styling that changes at a breakpoint

Four patterns for the recurring problem "a visual treatment must be shared across surfaces (or between a desktop and a mobile control), but the dimension or rule differs at a breakpoint, or a new surface must opt into it." Patterns 1–3 surfaced together while building a mobile edge-affordance that mirrored a desktop drawer edge-control; pattern 4 surfaced later — twice in one session — while migrating a new surface onto an established app-shell. Sibling to `CSS_DISPLAY_CONTENTS_SELECTOR_TRAPS.md` (CSS layout traps) and `SCSS_VENDOR_IMPORT.md` (SCSS import order).

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

## 4. Shared rule via an enumerated selector list (or per-surface inline copy) FAILS OPEN on a new surface — use ONE base class / mixin every surface opts into

A visual rule that must apply to *every* shell surface, but is wired as **(a) an enumerated `.surfaceA-role, .surfaceB-role, … { … }` selector list**, or **(b) a per-surface inline copy of the same declarations**, is a trap: when a new surface is added, the developer must remember to extend the list / re-copy the block — and if they forget, the surface **renders wrong, not broken**. No error, no failed build, no test failure — just a silently mis-styled surface. This is *failing open*, and it's the worst kind of regression because nothing flags it but a human's eyes on that specific surface.

This pattern fired **twice in one session** migrating a single new surface onto an established app-shell:

```scss
// ❌ Instance A — enumerated selector list. Full-width-select rule scoped to a
//    hand-maintained list of per-surface workspace classes:
.articles-filters-workspace,
.events-filters-workspace,
.faq-filters-workspace,
.chat-filters-workspace { .select, .input { width: 100%; } }
// The new `.dashboard-filters-workspace` was never appended → its selects
// collapsed to content width. The list compiled fine; nothing complained.

// ❌ Instance B — per-pane inline copy. A negative-margin "table bleed" (so a
//    min-width table scrolls edge-to-edge inside a full-width card) had its
//    mobile RESET copied inline into each pane that re-houses the card:
@include mobile {
  [data-org-section]   .card-content > .table-scroll-container { margin-inline: 0; width: 100%; }
  [data-billing-section] .card-content > .table-scroll-container { margin-inline: 0; width: 100%; }
  .shell-drawer__body  .card-content > .table-scroll-container { margin-inline: 0; width: 100%; }
}
// The new `.dashboard-center` pane re-housed the same card but got no reset
// → the table bled past the card edge on mobile.
```

```scss
// ✅ FIX A — one shared base class every surface OPTS INTO (adds the class):
.shell-filters-workspace { .select, .input { width: 100%; } }
// Each workspace form carries BOTH its per-surface class (JS/id hook) AND the
// shared base: class="dashboard-filters-workspace shell-filters-workspace".
// A new surface gets the rule by adding one class — impossible to "forget the
// list" because there is no list.

// ✅ FIX B — one mixin every pane @includes (declarations live once):
@mixin neutralize-card-table-bleed {
  .card-content > .table-scroll-container { margin-inline: 0; width: 100%; }
}
@include mobile {
  [data-org-section]     { @include neutralize-card-table-bleed; }
  [data-billing-section] { @include neutralize-card-table-bleed; }
  .shell-drawer__body    { @include neutralize-card-table-bleed; }
  .dashboard-center      { @include neutralize-card-table-bleed; }  // new surface, one line
}
```

**The smell**: a comma-list of `.<surface>-<role>` selectors sharing one declaration block, or the *same* declaration block pasted under ≥2 surface scopes. Both encode "every surface needs this" as a manually-maintained enumeration — and enumerations fail open. Extract to a base class surfaces opt into (preferred when the consumer is a class you control on the element) or a mixin surfaces `@include` (when the consumer is a structural/attribute selector).

**Base class vs mixin**: use a **base class** when you can add a class to the element (`class="<surface>-x shell-x"`) — adoption is one token, and the rule body exists exactly once in the compiled CSS. Use a **mixin** when the consumer is an attribute/structural selector you can't add a class to (`[data-org-section]`, `.shell-drawer__body`) — the declarations still live once in source, copied per call site at compile.

**Checklist item when adding a new shell surface**: *"which shared visual conventions do existing surfaces opt into that this new one must too?"* Grep for enumerated `.<surface>-` selector lists and per-pane inline blocks (table-bleed resets, workspace-filter widths, sticky-nav offsets, etc.). This audit is cheap; the silent-mis-style it prevents costs a human-eyes debugging round per surface. Pairs with pattern 1 (the mixin mechanic) and pattern 3 (the gutter-owner single-source principle) — all three are the same instinct: **a rule shared across N surfaces lives in ONE place every surface references, never N copies / an N-entry list.**
