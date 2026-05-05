# Sprint-auto handoff — `auto_safe_with_eval_gate` amendment proposal

**Status**: handoff doc — the maintainer will take over from within mind-vault when implementing the amendment.

**Date opened**: 2026-05-05

**Context**: Captured during teisutis IDEA-141 (`/compound` from PR #423). The IDEA-141 plan documented the proposal in its Out-of-band notes as a candidate sprint-workflow improvement; this doc is the mind-vault-side handoff with full context for the eventual sprint-auto skill amendment.

## Problem the amendment solves

Sprint-auto's current `auto_safe: true | false` gate is binary. IDEAs that need human eyes on visual / a11y / interaction review (most UX-overhaul IDEAs — modal primitives, drawers, file uploaders, etc.) are flagged `auto_safe: false` and excluded from sprint-auto, even though:

1. The IDEA's *implementation* is mechanical (cotton template + JS API + tests). Sprint-auto could run `/plan → /work → /bugbot-loop → /wrap → /bugbot-loop` autonomously.
2. The *human gate* needed isn't "approve every commit" or "review code quality" — bugbot already does that. It's "walk a structured eval checklist before merge" (focus-trap behaviour, screen-reader semantics, mobile gesture nuance — things render-and-assert tests can't catch).
3. **The merge gate is already HITL** per `RULE_git-safety` — the integration PR is the SINGLE PR that targets a protected branch, and the human reviews it. Sprint-auto v3.2 explicitly stops at this gate.

So the work being deferred to manual `/plan` + `/work` is the *implementation*, not the *review*. The implementation could be sprint-auto'd and the human's pre-merge review could simply consume the eval-checklist artefact the IDEA's `/wrap` step emitted. Same merge gate, much cheaper review.

## The amendment

Introduce a third frontmatter mode:

```yaml
auto_safe: false
auto_safe_with_eval_gate: true   # NEW
```

Sprint-auto's behavior:

- **Stage S0 (cohort selection)**: include `auto_safe_with_eval_gate: true` IDEAs alongside `auto_safe: true` IDEAs. Both run autonomously.
- **Stages S1–S5 (per-IDEA loop)**: identical to today's `auto_safe: true` path. `/plan → /work → /bugbot-loop (deliverables) → /wrap (idea-only)`.
- **Stage S6 (`/wrap` idea-only emission)** for `auto_safe_with_eval_gate` IDEAs: additionally emit `docs/archive/<dir>/YYYY-MM-DD-manual-evaluation.md` (the R17-style deliverable from teisutis IDEA-141). Format mirrors IDEA-138's `2026-05-04-smoke-test.md` precedent — annotated walkthrough of every R16-equivalent dev-preview scenario with expected outcomes + checkbox per scenario + space for user notes.
- **Stage S6 (`/bugbot-loop` docs)**: identical to today.
- **Stage S11.7 (batch wrap on integration branch)**: aggregate each `auto_safe_with_eval_gate` IDEA's eval-checklist URL into the integration PR's body — so the human reviewing the integration PR sees a single landing page of "things to walk before merging".
- **No mid-implementation pause**. Sprint-auto goes all the way through `/wrap` and into the integration phase. The eval is at the integration-PR-merge gate (the only true HITL gate per `RULE_git-safety`), where the human is already reviewing the integration anyway.

The integration PR's body template grows:

```markdown
## Per-IDEA evaluation checklists

The following IDEAs in this batch ship behaviours that need human eyes on visual/a11y/interaction review before merge. Walk each checklist, tick boxes, then merge.

- [ ] [IDEA-141 — modal primitives](https://github.com/.../docs/archive/.../YYYY-MM-DD-manual-evaluation.md)
- [ ] [IDEA-145 — dashboard surface migration](https://github.com/.../docs/archive/.../YYYY-MM-DD-manual-evaluation.md)
...
```

## Why this isn't a Teisutis-only concern

Multiple Teisutis sprint cohorts (UX-overhaul 134–158 specifically) are blocked from sprint-auto because of this binary gate. Generalising:

- Any project with a UX/a11y review burden hits the same gate.
- Any project where reviewer time is the scarcest resource benefits from "sprint-auto produced N PRs, here are N checklists, walk + merge".
- The `auto_safe_with_eval_gate` mode is *additive* — it doesn't change behaviour for IDEAs that don't opt in.

## Pair with browser-testing automation

Captured separately as a Teisutis-side IDEA candidate (when it materialises): Playwright integration in the dev-image so render-and-assert tests can be supplemented by browser-driven a11y + interaction tests for the residue (focus, click-through, animations, z-index hit-testing). Together with the eval-gate amendment:

- Browser automation **shrinks** the manual checklist to genuinely-HITL residue (screen-reader semantics, mobile gesture nuance).
- The eval-gate mode makes the residue **cheap to walk** at integration-PR review time.

Together they could flip the entire UX-overhaul cohort from "needs interactive `/plan` per IDEA" to "sprint-auto-able with one integration-PR walk."

## Implementation sketch

Files to touch when implementing:

1. `skills/sprint-auto/SKILL.md` — add `auto_safe_with_eval_gate` to the frontmatter parsing in S0 cohort-selection. Update the description's IDEA-allowlist semantics.
2. `skills/sprint-auto/references/STAGE_GUIDE.md` (or wherever stage definitions live) — add the eval-checklist emission to S6's `/wrap (idea-only)` step.
3. `skills/sprint-auto/references/integration-stage.md` — add the eval-checklist aggregation to S11.7's integration PR body template.
4. `skills/wrap/SKILL.md` — add a new sub-mode that emits the manual-evaluation checklist when invoked with `--mode=eval-gate` (or detected via the IDEA frontmatter). The checklist template can be cribbed from teisutis IDEA-141's `2026-05-05-manual-evaluation.md`.
5. `skills/wrap/assets/manual-evaluation-template.md` (NEW) — the template, generic across projects (placeholders for surface-name, scenario-table, etc.).
6. `commands/sprint-auto.md` — describe the new mode in the user-facing help.

Test plan when implementing:

- Run sprint-auto on a small batch with one `auto_safe_with_eval_gate` IDEA, verify the eval-checklist artefact lands in the per-IDEA archive dir AND its URL appears in the integration PR's body.
- Verify the IDEA's frontmatter remains `auto_safe: false` AND `auto_safe_with_eval_gate: true` post-completion (the gate didn't override the safe flag — both are true together).
- Verify mid-implementation pause does NOT happen — sprint-auto runs straight through the per-IDEA loop without waiting for human input.

## References

- Teisutis IDEA-141 plan Out-of-band notes (sprint-auto compatibility section): `<teisutis>/docs/archive/2026-05-idea-141-modal-primitives-consolidation/2026-05-05-modal-primitives-consolidation-plan.md`
- Teisutis IDEA-141 manual evaluation checklist (the canonical R17-style template this proposal generalises): `<teisutis>/docs/archive/2026-05-idea-141-modal-primitives-consolidation/2026-05-05-manual-evaluation.md`
- Teisutis IDEA-141 PR: https://github.com/infohata/teisutis/pull/423
- Sprint-auto v3.2 SKILL.md (current state): `skills/sprint-auto/SKILL.md`
- Browser-testing automation companion proposal: surfaces in same plan; would warrant its own IDEA in Teisutis backlog if/when implemented.

## What this handoff doc IS NOT

- Not a binding spec — when implementing, refine based on what the sprint-auto skill's current shape supports.
- Not a sprint-auto-able task itself (this is the meta-amendment to sprint-auto; it requires human design judgment).
- Not an IDEA file — mind-vault doesn't track per-project IDEAs (per-project numbering would collide). This handoff doc is the mind-vault-native equivalent.

**Last Updated**: 2026-05-05
