---
id: 002
title: Skill debloat — extract over-budget SKILL.md bodies into references/
status: in-progress
priority: high
supersedes: []
superseded_by: null
depends_on: []
related: [001]
created: 2026-05-09
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "Mechanically straightforward (move section bodies from SKILL.md → references/<NAME>.md and replace with one-paragraph stubs), but the stub wording is a judgment call — the stub must preserve enough context for the skill to remain self-contained while pointing at the reference for mechanics. /plan will resolve which stubs read cleanly enough to flip this to true."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches skills/wrap/, skills/django-frontend/, skills/django/ — entirely outside auth, permission, schema, infra, secrets, and payment paths. No project source code or runtime config involved."
---

# IDEA-002: Skill debloat — extract over-budget SKILL.md bodies into references/

**Status**: 🚧 In Progress (Phase 1 shipped; Phase 2 + 3 queued)
**Priority**: High

## Progress

- ✅ **Phase 1** — `skills/wrap/SKILL.md`: shipped 2026-05-09 in [PR #107](https://github.com/infohata/mind-vault/pull/107). Body 546 → 310 lines (-43%, -236L). Three new references emitted: `WORKTREE_TEARDOWN.md`, `EVAL_GATE_EMISSION.md`, `ATOMIC_MERGE.md`. Architect-review verdict REQUIRES ABSTRACTION integrated (filename concept-scoping + internal forward-ref rewrite + foregone-conclusion Q1/Q2 collapse). Note: the inline audit's "Step 8 atomic merge (100L)" estimate was off — actual extracted body was 73L; minor variance, target line count met (≤350L).
- ⏳ **Phase 2** — `skills/django-frontend/SKILL.md`: queued. ~373L = 40% of body extractable across six section moves.
- ⏳ **Phase 3** — `skills/django/SKILL.md`: queued. Lowest priority — distributed bloat, harder per-section judgment.

**Problem** (or opportunity): Three skills currently exceed the ~500-line soft body budget set by `docs/SKILL_SPECIFICATION.md`. Every `Skill` tool invocation loads the full SKILL.md body into the consuming agent's context, so bloat is paid as a per-activation token cost — and `wrap` is invoked twice per IDEA under sprint-auto, multiplying the cost.

Audit captured 2026-05-09 (post-PR-#106):

| Skill | Lines | Lead extract candidates |
| --- | --- | --- |
| `skills/wrap/SKILL.md` | 546 | Step 5 worktree teardown (107L), Step 7 eval-gate emission (77L), Step 8 atomic merge (100L) — ~285L = **52%** of body |
| `skills/django-frontend/SKILL.md` | 920 | App-shell layout (110L), Alpine.store coordinators with onRegister (84L), Active-state via aria-current + :has() (66L), Template comment syntax (43L), SCSS vendor-import hazard (43L), JS sibling-comment trap (27L) — ~373L = **40%** of body |
| `skills/django/SKILL.md` | 802 | Distributed bloat — Cross-entity session-filter (78L), LLM output post-processing (65L), FileField MIME (54L), Env-driven allowlists (53L), ManifestStaticFilesStorage (50L). Harder to extract cleanly. |

**Proposal** (or idea): Move long inline patterns out of SKILL.md bodies and into `skills/<owner>/references/<UPPERCASE_NAME>.md` files. Replace each extracted section in SKILL.md with a one-paragraph stub explaining when the pattern fires + a load-on-demand pointer at the reference. Apply same discipline used in PR #106's rules-reorg split (always-on vs load-on-demand).

Sequence (mechanically simplest → most cross-references):

1. **`skills/wrap/SKILL.md`** Steps 5/7/8 → `references/{POST_MERGE_TEARDOWN,EVAL_GATE_EMISSION,ATOMIC_MERGE}.md`. Highest-leverage: ~285L savings × 2-invocations-per-IDEA-under-sprint-auto.
2. **`skills/django-frontend/SKILL.md`** large patterns → `references/{APP_SHELL_LAYOUT,ALPINE_STORE_COORDINATORS,ACTIVE_STATE_TRACKING,TEMPLATE_COMMENT_SYNTAX,SCSS_VENDOR_IMPORT,JS_SIBLING_COMMENT_TRAP}.md`. Multiple section moves; more cross-references to update across teisutis archives + sibling skills.
3. **`skills/django/SKILL.md`** distributed bloat. Lower priority — judgement call per section on whether the inline body earns its keep.

**Why now**:
- Token cost compounds across every skill activation; sprint-auto runs invoke `wrap` twice per IDEA, so the trim multiplies.
- Same curation discipline as PR #106 rules-reorg — extending the always-on / load-on-demand pattern from `rules/` to `skills/`.
- Three concrete budget breaches identified with line counts; nothing speculative.
- Post-PR-#106 we have a clean main with no in-flight sprint work blocking the SKILL.md edits.

**Non-goals**:
- Not rewriting any skill's logic or contract — purely a reorg.
- Not enforcing a hard 500-line cap on every skill — the SPECIFICATION's budget is a soft target, and a few skills (e.g. `bugbot-loop` if/when it crosses) can stay over budget if every line earns its keep.
- Not extracting tiny sections (<30L) — extraction overhead exceeds the load-cost savings.
- Not touching the four surviving `rules/` files — those are always-on by design (PR #106's curation already settled this).

**Related**: IDEA-001 (Playwright Direction-1 plumbing — the precedent for clean-extraction PRs from SKILL.md bodies into references/, e.g. visual baseline bumps + multi-tenant playwright + HTMX/Alpine waits all landed as fresh references in PR #106).
