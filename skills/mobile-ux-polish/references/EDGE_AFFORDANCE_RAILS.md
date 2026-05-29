# Edge-affordance rails on a scroll-snap pane shell

How to add a discoverability affordance (a slim edge rail / lip that hints an off-screen pane is
swipe-able and gives a tap target to reveal it) to a tuned mobile scroll-snap shell — **without
re-introducing the snap/gesture race class** that the [parent skill's patterns 1–5](../SKILL.md)
exist to tame.

Three facets, all from one build: **(1)** how to attach the chrome without perturbing the snap engine,
**(2)** the wayfinding model that decides which rail reveals which pane, **(3)** the build-vs-defer call
on the animated version. The SCSS slice of the rail itself (the shared `--edge-gutter` token + the
`edge-lip` mixin) lives in
[`django-frontend/references/SCSS_RESPONSIVE_PATTERNS.md`](../../django-frontend/references/SCSS_RESPONSIVE_PATTERNS.md)
— this file is the JS/UX/architecture half; it cross-refs that file rather than restating any SCSS.

**When this fires**: you're adding an edge lip / pane handle / reveal rail to a horizontal
scroll-snap shell (workspace · centre · preview style), or any fixed chrome that overlays the edges of
a gesture-tuned surface.

## 1. Render the chrome `position: fixed` OUTSIDE the snap container — never mutate snap geometry

The snap container's swipe/settle behaviour is delicately tuned (see patterns 1–5). The temptation is
to carve the rail's space out of the snap geometry — `scroll-padding`, a negative margin, a
`clip-path` on the container. **Don't.** Any geometry change to the snap container risks the
fast-swipe-overshoot / settle-ordering tuning you already paid for.

Instead render the rail as a `position: fixed` overlay element that is **not a descendant of the snap
container**:

- **No `stopPropagation` needed.** The swipe handler binds to the snap container; the rail is never
  inside it, so a tap on the rail is never seen by the gesture handler — it can't be misread as the
  start of a drag. (Contrast: a rail placed *inside* a pane would need careful drag-vs-tap
  disambiguation — pattern 1's whole problem.)
- **Reserve a gutter so the rail never overlays content.** A fixed rail at the very edge would hijack
  edge taps on content beneath it. Inset the content by the rail width into a reserved channel — see
  the reserved-gutter placement doctrine in
  [`django-frontend/references/APP_SHELL_LAYOUT.md`](../../django-frontend/references/APP_SHELL_LAYOUT.md)
  § *Edge-affordance lips* and the additive-padding mechanics in `SCSS_RESPONSIVE_PATTERNS.md` §3.

### iOS Safari fixed-in-transformed-ancestor trap

A `position: fixed` element nested under **any** ancestor with a `transform`, `filter`, or
`perspective` becomes positioned relative to *that ancestor*, not the viewport (CSS containing-block
rule). On iOS Safari this silently breaks edge anchoring — the rail drifts or clips.

**Fix**: place the fixed rail where no transformed/filtered ancestor exists — e.g. directly in
`<body>` after `</main>`, as a sibling of the main shell rather than a descendant of an animated pane.

### z-index ladder discipline

A new fixed overlay must slot into the existing stacking ladder deliberately, or it falls behind (or
on top of) the wrong things. Pin it **above pane content but below every interactive overlay**. A
worked ladder from one shell:

| Layer | z-index |
| --- | --- |
| edge rail / lip | 10 |
| section-nav trigger | 28 |
| bottom-nav | 30 |
| more-sheet | 50 |
| modal | 50–51 |
| toast | 60 |

Verify against the live ladder before picking a number — don't guess.

## 2. The adjacent-pane reveal model (wayfinding)

For a three-pane snap shell, each edge rail reveals **only the pane adjacent to the active pane in
that direction** — not "always the workspace on the left." This both fixes discoverability *and*
gives a way back:

| Active pane | Left rail reveals | Right rail reveals |
| --- | --- | --- |
| workspace (left) | — | centre (return) |
| centre | workspace | preview *(if it has content)* |
| preview (right) | centre (return) | — |

So the **centre** shows up to two reveal rails; a **side pane** shows exactly one "back to centre"
rail. Implement as a per-rail factory that reads the active pane index against an ordered pane list
(`['workspace','center','preview']`) and derives `leftTarget` / `rightTarget` (null when there's no
neighbour in that direction).

- **Content-gated neighbour.** The conditional neighbour (preview) is only reachable when it actually
  holds content — gate the right rail on `Alpine.store('previewSurface').depth > 0`. A rail that
  reveals an empty pane is a dead affordance.
- **Read the active pane race-free.** The rail factory typically initialises *after* the snap
  authority and will miss the cold-load snap if it relies on an init-seed + a `paneChanged` event —
  the event fires before it subscribes, leaving it stuck on the default pane (wrong rails shown). Mirror
  the authority's `data-active-pane` attribute via a `MutationObserver` instead. Full failure-mode +
  mechanism:
  [`django-frontend/references/ALPINE_HTMX_GOTCHAS.md`](../../django-frontend/references/ALPINE_HTMX_GOTCHAS.md)
  § gotcha 8.
- **Reveal goes through the snap component's scoped method, not a store.** The rail lives outside the
  snap component's `x-data`, so it can't call `goToPane()` directly. Dispatch an inbound-command
  CustomEvent the snap component listens for — the symmetric counterpart to its outbound state event.
  The bridge-vs-promote-to-store tradeoff:
  [`django-frontend/references/ALPINE_STORE_COORDINATORS.md`](../../django-frontend/references/ALPINE_STORE_COORDINATORS.md)
  § *inbound-command bridge*.

### Re-fire the reveal on replace-while-open

If a surface is re-opened *while its pane is already open but the user has swiped away to centre*, the
open is a no-op on depth (it was already > 0) — so nothing re-snaps and the user stays on centre,
seemingly ignored. **Re-issue the reveal command on replace-while-open** so the pane re-snaps into
view. Completeness detail: the reveal is a command on every open, not only on the depth 0 → 1
transition.

## 3. Ship the static affordance; defer the animated one (build-vs-defer heuristic)

The instinct after building a static rail is to add a pulse / bounce to draw the eye. **Resist it for
v1** when the animation would introduce the feature's *only* race-prone JS into an otherwise pure
visibility-gating feature.

The cost ledger that justified deferring a pulse-chevron on one build:

- a **first-visible state machine** — a CSS animation on a `display:none` element can't fire at init,
  so you need JS to detect "now actually visible" and trigger it;
- a **`localStorage` "seen" flag** — which *throws* in Safari private mode, so it needs its own guard;
- **mark-seen-only-when-actually-played** semantics — to handle deep-loading straight onto the pane
  the animation was meant to advertise.

None of that touches the snap engine, but it's all net-new edge-case surface in a feature that was
otherwise pure declarative visibility gating. The persistent static rail *is already* the
discoverability affordance.

**Rule**: ship static; defer the animation as an **isolated, eval-gated fast-follow** — add it later
only if the manual-eval walk shows discoverability is still weak. The keyframes + gated trigger drop
in without touching the rest. The mechanics for *when you do* commit to a stateful animation safely
live next door — patterns 2–5 (deferred-clear, settle-timer, cold-start instant-vs-smooth,
state-lag-on-close).

**When NOT to apply**: if the animation is core to the feature's *function* (not just a discoverability
nicety), or it adds no net-new race/persistence surface, just build it — this heuristic is about
declining brittle polish, not declining animation per se.
