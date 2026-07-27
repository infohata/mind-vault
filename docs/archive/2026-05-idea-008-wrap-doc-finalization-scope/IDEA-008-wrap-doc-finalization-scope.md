---
id: "008"
title: Separate wrap's doc-finalization phase from its merge phase (--scope=docs mode)
status: complete          # idea | in-progress | complete | superseded
priority: high   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: []       # list of IDEA ids required before starting, or []
related: []             # list of IDEA ids that share context, or []
created: 2026-05-25
completed: 2026-05-25
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Touches wrap SKILL.md control flow (scope-mode gating, Step 8 interaction) and the sprint-auto S5 contract; flag semantics and ATOMIC_MERGE re-clearance are design decisions, not mechanical edits. Resolve the open questions in /plan before flipping."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Modifies a core sprint-workflow skill (wrap) that every project's release flow depends on; warrants a human eyeball even though no auth / permission / schema / infra / secret paths are touched."
---

# IDEA-008: Separate wrap's doc-finalization phase from its merge phase (--scope=docs mode)

**Status**: ✅ Complete (2026-05-25)
**Priority**: High

**Problem** (or opportunity): `/wrap` bundles three phases that have different timing relative to review:

| Phase | Steps | Correct timing |
| --- | --- | --- |
| Doc-finalization | 1–4, 6, 7 | **pre-review** (reviewers read the final docs) |
| Merge | 8 (atomic, non-protected) | **post-review-clear** |
| Teardown | 5 | post-merge |

The wrap-before-review pattern (shipped as v4.3.1, PR #141) requires the doc-finalization phase to run *before* `/review-loop` so doc-reviewing engines see docs at shipped state. But today they're one invocation with conditional gating: on a **non-protected** target a full `/wrap` falls through to **Step 8 (atomic merge)**, whose `ATOMIC_MERGE.md` gate requires a clean review signal at HEAD. Pre-review there is none, so the pre-review pass would block (re-trigger + wait) or abort. Surfaced as a Copilot finding on PR #141; resolved there only by a documented operational workaround ("run wrap, stop before Step 8").

**Proposal** (or idea): a dedicated **`--scope=docs`** wrap mode that runs the doc-finalization steps (1–4, 6, 7) and **structurally cannot reach Step 8 or Step 5** — making the wrap-before-review pre-review pass a single clean invocation instead of a "remember to stop" footgun. The post-review pass then runs Step 8 (non-protected) or hands to the human (protected). Distinct from the existing `--scope=idea-only`, which *also* skips Steps 3 (ideas-index) and 4 (devlog) — exactly the steps a pre-review pass *wants* finalized.

**Why now**:
- The wrap-before-review pattern just shipped (v4.3.1) carrying an operational workaround that `skills/wrap/references/WRAP_BEFORE_REVIEW.md` explicitly forward-references as "tracked as a follow-up". This IDEA is that follow-up.
- The workaround relies on operator/agent discipline to stop before Step 8 — a latent footgun on non-protected targets every doc-heavy PR now hits.

**Non-goals**:
- Changing the merge HITL gate — `RULE_git-safety` (protected-branch merge is the human gate) is unchanged.
- Changing Step 5 teardown timing (stays post-merge).
- Reworking `--scope=idea-only`'s sprint-auto S5 semantics unless the design finds `--scope=docs` is the better fit there.

**Open questions for /plan**:
- Flag name: `--scope=docs` vs `--no-merge` vs `--pre-review`.
- Relationship to `--scope=idea-only`: is `docs` = `idea-only` + Steps 3/4, or an orthogonal axis?
- sprint-auto S5 currently invokes `--scope=idea-only`; does it migrate to `--scope=docs`, or stay (its batch wrap defers index/devlog by design)?
- Post-review pass: does it re-run doc-finalization idempotently then Step 8, or a merge-only invocation? ATOMIC_MERGE re-clearance must account for the pre-review pass having moved HEAD.

**Related**: Follow-up to the v4.3.1 wrap-before-review compound (PR #141) and `skills/wrap/references/WRAP_BEFORE_REVIEW.md`, which documents the two-pass workaround this IDEA would make structural. Touches `skills/wrap/SKILL.md` scope-detection + Step 8 gating and `skills/sprint-auto/` S5.
