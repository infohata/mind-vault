# IDEA-<NNN> — manual evaluation checklist

**Surface**: `<one-line description of the surface or behaviour shipped, e.g. "modal primitives — confirm/error variants">`
**Plan**: [`YYYY-MM-DD-<slug>-plan.md`](./YYYY-MM-DD-<slug>-plan.md)
**PR**: <#NNN>
**Date authored**: YYYY-MM-DD

This checklist covers what render-and-assert tests cannot verify: visual correctness, focus & keyboard behaviour, screen-reader semantics, animation timing, and interaction nuance. **Walk every scenario in a real browser before the integration PR is merged.** Tick boxes as you go; jot notes on anything that surprises you. Deviations are not blockers — they are signal for the reviewer.

## Setup

1. Open the integration PR's preview deploy, or run the integration worktree locally (project-specific — typically `cd <integration-worktree-path> && make up` or equivalent).
2. Browser baseline: <chosen browser, e.g. `Chromium 124+`>. For a11y residue, also walk under <screen reader, e.g. `NVDA on Windows`, `VoiceOver on macOS`, or `Orca on Linux`>.
3. Viewport: cover both desktop (1280×800) and mobile (375×667) wherever the surface adapts. If the surface is desktop-only, drop the mobile pass and note why here.

## Scenarios

### 1. <Scenario name>

**Trigger**: <how to invoke — click X, navigate to /Y, submit form Z, …>

**Expected**:
- <bullet 1>
- <bullet 2>
- <bullet 3>

**Walked**: [ ]

**Notes**:
> _(write any deviations from expected — or leave empty if the scenario walked clean)_

### 2. <Scenario name>

**Trigger**:
**Expected**:
- 

**Walked**: [ ]

**Notes**:
> 

<!-- Repeat per scenario. Aim for one scenario per distinct interaction path; a surface with 3 variants × 2 trigger sources = ~6 scenarios. -->

## Cross-cutting checks

These apply to most interactive surfaces — keep the box if relevant, drop the line entirely if not (don't leave N/A residue).

- [ ] **Focus trap** — Tab cycles within the surface only; Shift+Tab reverses; no hidden focusable element receives focus.
- [ ] **Esc closes** (where applicable) — releases focus to the trigger element.
- [ ] **Initial focus** — first focusable element receives focus on open (or the explicit `autofocus` target if one is designated).
- [ ] **Screen reader** — heading/landmark structure announced correctly; live-region updates surfaced (if any); no orphan text fragments.
- [ ] **Touch target** — interactive elements ≥44×44 CSS pixels on mobile.
- [ ] **Mobile gesture** — swipe-to-dismiss / pull-to-refresh / long-press behave as designed. Drop this line if the surface doesn't use gestures.
- [ ] **Animation timing** — entry/exit transitions feel snappy at 60 FPS; no jank under throttled CPU (Chrome devtools 4× slowdown).
- [ ] **Z-index sanity** — the surface stacks correctly against existing overlays (drawers, toasts, modals, sticky headers); no obscured controls.
- [ ] **Reduced-motion** — animations respect `prefers-reduced-motion: reduce` (skip / shorten / cross-fade instead of slide).
- [ ] **High-contrast** — focus rings remain visible under Windows High Contrast or `forced-colors: active`.

## After walk-through

- [ ] Every scenario above is ticked OR has a notes deviation logged.
- [ ] Cross-cutting checks: every applicable box is ticked.
- [ ] If anything was wrong, the next two boxes are filled in.

**Follow-ups created** (only if a scenario revealed a defect — otherwise leave `_(none)_`):

- _(none)_

**Decision**:

- [ ] ✅ Ready to merge — no blockers.
- [ ] ⚠️ Merge anyway, follow-up tickets above will catch the deviations.
- [ ] ❌ Hold merge — at least one deviation is a blocker; comment on the integration PR with the reasoning.

---

_Walked by_: <name>
_Walked on_: YYYY-MM-DD
