---
id: "015"
title: "Split /wrap into /wrap (docs) + /land (merge + teardown)"
status: complete          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: ["006", "008", "013", "002"]             # list of IDEA ids that share context, or []
created: 2026-06-06
completed: 2026-06-06
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Cross-cutting skill refactor with judgment calls (per-step seam placement, deprecation-redirect mechanics, workflow prose rewrites across ~12 live surfaces) AND it rewires sprint-auto's own orchestration call sites — too much design latitude for an unattended run."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "The new /land skill owns the atomic-merge HITL gate (RULE_git-safety merge boundary) and sprint-auto's teardown/orchestration contract — exactly the 'human eyeballs it' zone the gate exists to flag."
---

# IDEA-015: Split /wrap into /wrap (docs) + /land (merge + teardown)

**Status**: ✅ Complete (2026-06-06)
**Priority**: Medium

**Problem** (or opportunity): Two coupled problems in the finish of the sprint workflow.

1. **`/wrap` carries two structurally different concerns under one trigger** — **documentation finalization** (frontmatter flip, ideas-index re-sort, devlog, version-bump, downstream-docs scan, README currency audit, eval-gate checklist) and **merge/teardown operations** (atomic squash-merge, post-merge worktree/volume teardown, sprint-auto batch teardown). The coupling shows up as: a ~900-word frontmatter `description` loaded into context every session, a `--scope=full` value whose *only* purpose is to glue merge onto the tail of a docs pass, and a 420-line SKILL.md mixing non-destructive idempotent docs steps with destructive post-merge operations. Different blast radii, different HITL gates, different timing — one skill.
2. **The workflow runs a redundant double-review ceremony.** The canonical chain (IDEA-013) is `work → review (deliverables) → wrap (docs) → review (docs) → compound` — review runs *before* docs are finalized, then wrap, then a *second* review of the docs. But every review engine expects documentation already in order on the PR, and `/review-loop` already iterates (re-reviews on every fix push). So the deliverables-first pass is premature and the second pass is ceremony: wrapping once up front and running **one** review over the complete PR (code + docs together, in final shape) does the same job in one pass. The double-review is encoded across `WRAP_BEFORE_REVIEW.md`, wrap's pass-1/pass-2 language, and sprint-auto's S3–S7 state machine (separate deliverables/docs passes with split 20/5 escalation caps).

**Proposal** (or idea): Carve `/wrap` along its seam into two skills, **retire the double-review ceremony to a single post-wrap review**, and reconcile the whole documented workflow to match.

- **`/wrap` — documentation finalization** (pre-merge, non-destructive, idempotent): Steps 1 resolve · 2 frontmatter flip · 3 ideas-index re-sort · 4 devlog · 4b version-bump · 6 downstream-docs scan · 6b README currency audit · 7 eval-gate checklist. Post-merge fallback (the `docs/idea-NNN-wrap` cleanup branch) stays here — it's a docs concern. Retains references `IDEA_COMPLETENESS_AUDIT.md`, `README_CURRENCY.md`, `EVAL_GATE_EMISSION.md`, `MANUAL_EVAL_TRACKER.md`, `WRAP_BEFORE_REVIEW.md`. Frontmatter shrinks dramatically (merge/teardown prose leaves).
- **`/land` — merge + teardown operations** (new `skills/land/`, no `commands/` wrapper needed): Step 8 atomic merge (squash-merge non-protected target after a review re-clearance pass; protected target → hand back PR URL per `RULE_git-safety`) · Step 5 post-merge worktree/volume teardown · `--integration <batch-iso>` sprint-auto batch teardown. Takes references `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md`. Opens with a **precondition guard** ("is frontmatter `complete`? devlog present?") so it refuses to merge un-wrapped work instead of silently doing it — this replaces the old `--scope=full` idempotent docs re-run.
- **`--scope` enum**: keep the three-value spelling for migration safety. `--scope=docs` (default, normal docs pass) and `--scope=idea-only` (sprint-auto narrowing) stay. `--scope=full` becomes **deprecated**: emits a loud deprecation notice and redirects to `/land` (the graceful-migration path, not a hard error; never auto-merges).
- **Retire the double-review → single post-wrap review.** Collapse `work → review (deliverables) → wrap → review (docs)` into `work → wrap → review`. Wrap finalizes docs first so the PR carries finalized docs into a single `/review-loop` over the whole PR; the loop's own fix-iteration absorbs both code and doc findings. Touches `WRAP_BEFORE_REVIEW.md` (rewrite from two-pass to single-pass), wrap's pass-1/pass-2 language, `review-loop`'s pre-flight, and **sprint-auto's S3–S7 state machine** (deliverables pass S3/S4 + docs pass S6/S7 collapse to one review+escalation pass after S5 wrap; split 20/5 caps merge to a single budget).
- **New canonical workflow chain** (the whole reconciliation goal): `/idea → /plan → /work → /wrap (docs) → /review-loop → /land (merge) → /compound`. **Single** review, positioned after wrap and before land. No review-before-wrap pass.

**Why now**:
- Wrap's two-concern overload + ~900-word frontmatter is friction on every session load and every wrap invocation; the seam is clean and well-understood.
- The wrap-before-review principle (IDEA-006/008/013) is already canonical — taken to its logical end, if wrap always precedes review there is no reason to review twice; the deliverables-first pass and the named *merge* stage both deserve to be made explicit (one review, one `/land`).
- `sprint-auto/references/escalation-policy.md` already references a `/wrap-docs` name (lines 11, 57) that doesn't exist — prior intent for a docs/ops naming split, currently a dangling reference to fix either way.

**Non-goals**:
- Not renaming the docs skill — it stays `/wrap` (renaming it would multiply the blast radius across `work/SKILL.md`, sprint-auto S5, and every workflow doc).
- Not changing sprint-auto's own S11 integration-merge logic — it never invoked `/wrap --scope=full`; only its S11.13 teardown call (`/wrap --integration` → `/land --integration`) moves.
- Not touching frozen historical record under `docs/archive/**` or `docs/plans/**`.
- Not adding a `commands/land.md` wrapper — `/wrap` has none either; both resolve as skills directly.
- Not changing sprint-auto's integration-stage merge logic (S11.x) — only its per-IDEA review cadence (S3–S7 collapse) and its teardown call (`/land --integration`).
- Not removing `/review-loop`'s ability to run mid-`/work` (a Claude pass before wrap is still allowed for early signal) — retiring the double-review removes the *mandatory ceremonial* second pass, not the option to review more than once.

**Execution notes** (for `/plan`): see the emitted plan for the full sequence. Ships as **one PR** (commit-ordered C1–C5 under `RULE_rename-before-drop`: add `/land` → collapse sprint-auto cadence → reconcile all chain docs → drop legacy from `/wrap` → re-sweep). One PR keeps the change atomic — both the wrap/land split and the double-review retirement land together, so no doc/behaviour contradiction window. **Sequencing:** run `/work` *after* the sprint-auto stability verification, so the cadence change is made against a proven-stable baseline.

**Related**: Extends [IDEA-013](../archive/2026-06-idea-013-wrap-readme-currency-backfill/IDEA-013-wrap-readme-currency-backfill.md) (two-pass workflow-ordering reconciliation this builds on) and [IDEA-008](../archive/2026-05-idea-008-wrap-doc-finalization-scope/IDEA-008-wrap-doc-finalization-scope.md) (the `--scope` enum this modifies). Completes the direction of [IDEA-006](../archive/2026-05-idea-006-review-surface-collapse/IDEA-006-review-surface-collapse.md) (single review entry → now a single, named *merge* entry too). Thematically advances [IDEA-002](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md) (skill debloat — wrap's frontmatter + body both shrink).
