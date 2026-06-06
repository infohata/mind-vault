---
id: 015
title: "Split /wrap into /wrap (docs) + /land (merge + teardown)"
status: in-progress          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: [6, 8, 13, 2]             # list of IDEA ids that share context, or []
created: 2026-06-06
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Cross-cutting skill refactor with judgment calls (per-step seam placement, deprecation-redirect mechanics, workflow prose rewrites across ~12 live surfaces) AND it rewires sprint-auto's own orchestration call sites — too much design latitude for an unattended run."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "The new /land skill owns the atomic-merge HITL gate (RULE_git-safety merge boundary) and sprint-auto's teardown/orchestration contract — exactly the 'human eyeballs it' zone the gate exists to flag."
---

# IDEA-015: Split /wrap into /wrap (docs) + /land (merge + teardown)

**Status**: 💡 Idea
**Priority**: Medium

**Problem** (or opportunity): The `/wrap` skill carries two structurally different concerns under one trigger — **documentation finalization** (frontmatter flip, ideas-index re-sort, devlog, version-bump, downstream-docs scan, README currency audit, eval-gate checklist) and **merge/teardown operations** (atomic squash-merge, post-merge worktree/volume teardown, sprint-auto batch teardown). The coupling shows up as: a ~900-word frontmatter `description` loaded into context every session, a `--scope=full` value whose *only* purpose is to glue merge onto the tail of a docs pass, and a 420-line SKILL.md mixing non-destructive idempotent docs steps with destructive post-merge operations. The two halves have different blast radii, different HITL gates, and different timing (pre-merge vs post-merge), but share one skill.

**Proposal** (or idea): Carve `/wrap` along its natural seam into two skills, and reconcile the whole documented workflow to match.

- **`/wrap` — documentation finalization** (pre-merge, non-destructive, idempotent): Steps 1 resolve · 2 frontmatter flip · 3 ideas-index re-sort · 4 devlog · 4b version-bump · 6 downstream-docs scan · 6b README currency audit · 7 eval-gate checklist. Post-merge fallback (the `docs/idea-NNN-wrap` cleanup branch) stays here — it's a docs concern. Retains references `IDEA_COMPLETENESS_AUDIT.md`, `README_CURRENCY.md`, `EVAL_GATE_EMISSION.md`, `MANUAL_EVAL_TRACKER.md`, `WRAP_BEFORE_REVIEW.md`. Frontmatter shrinks dramatically (merge/teardown prose leaves).
- **`/land` — merge + teardown operations** (new `skills/land/`, no `commands/` wrapper needed): Step 8 atomic merge (squash-merge non-protected target after a review re-clearance pass; protected target → hand back PR URL per `RULE_git-safety`) · Step 5 post-merge worktree/volume teardown · `--integration <batch-iso>` sprint-auto batch teardown. Takes references `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md`. Opens with a **precondition guard** ("is frontmatter `complete`? devlog present?") so it refuses to merge un-wrapped work instead of silently doing it — this replaces the old `--scope=full` idempotent docs re-run.
- **`--scope` enum**: keep the three-value spelling for migration safety. `--scope=docs` (default, normal docs pass) and `--scope=idea-only` (sprint-auto narrowing) stay. `--scope=full` becomes **deprecated**: emits a deprecation notice and redirects to `/land` (the graceful-migration path, not a hard error).
- **New canonical workflow chain** (the whole reconciliation goal): `/idea → /plan → /work → /review-loop (deliverables) → /wrap (docs) → /review-loop (docs) → /land (merge) → /compound`. Inserts `/land` after the docs-review pass; preserves the wrap-before-review ordering established in IDEA-013.

**Why now**:
- Wrap's two-concern overload + ~900-word frontmatter is friction on every session load and every wrap invocation; the seam is clean and well-understood.
- The wrap-before-review two-pass model (IDEA-006/008/013) is already canonical but the *merge* step is still buried as a `--scope=full` tail rather than a named final stage — splitting makes the workflow's shape match its documentation.
- `sprint-auto/references/escalation-policy.md` already references a `/wrap-docs` name (lines 11, 57) that doesn't exist — prior intent for a docs/ops naming split, currently a dangling reference to fix either way.

**Non-goals**:
- Not renaming the docs skill — it stays `/wrap` (renaming it would multiply the blast radius across `work/SKILL.md`, sprint-auto S5, and every workflow doc).
- Not changing sprint-auto's own S11 integration-merge logic — it never invoked `/wrap --scope=full`; only its S11.13 teardown call (`/wrap --integration` → `/land --integration`) moves.
- Not touching frozen historical record under `docs/archive/**` or `docs/plans/**`.
- Not adding a `commands/land.md` wrapper — `/wrap` has none either; both resolve as skills directly.

**Execution notes** (for `/plan`):
- **Sequencing per `RULE_rename-before-drop`**: (1) add `/land` skill referencing the *moved* `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md`; (2) rewire call sites (sprint-auto S11.13 teardown, work/SKILL.md hand-off, all workflow-chain depictions); (3) consistency-verify (grep sweep: no dangling `--scope=full` without deprecation handling, every `/land` ref resolves, `/wrap-docs` dead refs fixed); (4) add the `--scope=full`→`/land` deprecation redirect + strip Step 5/8 prose from `/wrap`; (5) re-sweep.
- **Live refactor surfaces** (workflow-ordering + wrap-merge): `README.md` (mermaid + glyph chains ~L5/19/38/68/71/109), `docs/guides/SPRINT_WORKFLOW.md`, `docs/guides/ONBOARDING.md`, `docs/ideas/README.md` (mermaid), and skills `wrap`, `work`, `review-loop` (+`engine-claude.md`), `sprint-auto` (SKILL + `integration-stage`, `post-pr-sequence`, `worktree-lifecycle`, `safety-gates`, `integration-conflict-resolutions`, `escalation-policy`, `auto-run-log-template`), `plan`, `ideate`, `idea/references/IDEAS_LOCATION_STATUS.md`, `django-frontend`.

**Related**: Extends [IDEA-013](../archive/2026-06-idea-013-wrap-readme-currency-backfill/IDEA-013-wrap-readme-currency-backfill.md) (two-pass workflow-ordering reconciliation this builds on) and [IDEA-008](../archive/2026-05-idea-008-wrap-doc-finalization-scope/IDEA-008-wrap-doc-finalization-scope.md) (the `--scope` enum this modifies). Completes the direction of [IDEA-006](../archive/2026-05-idea-006-review-surface-collapse/IDEA-006-review-surface-collapse.md) (single review entry → now a single, named *merge* entry too). Thematically advances [IDEA-002](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md) (skill debloat — wrap's frontmatter + body both shrink).
