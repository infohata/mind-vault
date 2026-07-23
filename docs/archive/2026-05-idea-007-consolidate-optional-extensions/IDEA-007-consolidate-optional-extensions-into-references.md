---
id: "007"
title: Consolidate `Optional extensions` blocks into `## References` across feature-dense skills
status: complete
priority: medium
supersedes: []
superseded_by: null
depends_on: []
related: ["002"]
created: 2026-05-22
completed: 2026-05-22
auto_safe: true
auto_safe_reason: "Purely mechanical bullet relocation between two markdown lists in three SKILL.md files. Fully additive→subtractive (move + dedupe), reversible by git revert, no design unknowns. No code paths exercised."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches only `skills/{deployment,django,django-frontend}/SKILL.md` — markdown documentation. Zero auth, permission, schema, infra, or secret-bearing surface."
---

# IDEA-007: Consolidate `Optional extensions` blocks into `## References` across feature-dense skills

**Status**: ✅ Complete
**Priority**: Medium

**Problem**: Three feature-dense skills — `deployment`, `django`, `django-frontend` — carry **two** parallel index blocks pointing at the same `references/*.md` files: a top-of-file `**Optional extensions** (load on demand):` list and a bottom-of-file `## References` section. Every line of `SKILL.md` is loaded into context on every activation, so the duplicate index doubles the token cost for the same information. The skill-writer spec (just-codified, PR #134) defines only **one** canonical body section — `## References` — for "links to `./references/*.md`, external docs, related skills". The `Optional extensions` block is a non-spec addition that predates the consolidation.

**Proposal**: Sweep the three offenders. For each:

1. Merge entries from `Optional extensions` into `## References` (de-duplicating where the same reference appears in both — preserve the longer/more-recent description).
2. Delete the `Optional extensions` block entirely.
3. Verify that any inline foreshadowing of a reference earlier in the body (e.g. inside `## Critical hazards` or `## Pattern`) links directly to the `references/<NAME>.md` file at point of mention, not via the deleted top-of-file block.

**Why now**:
- Codification just landed in `skills/skill-writer/SKILL.md` body §"Body structure" item 5 — the rule exists, the three skills are the only known violators. Close the gap while the policy is fresh.
- Each `SKILL.md` activation pays the duplicate-index token tax. `django-frontend` is ~620 lines, `django` ~802, `deployment` ~? — the saving compounds at sprint-auto invocation rates.
- Direct continuation of IDEA-002 (skill debloat) precedent. Same lever — load-on-demand discipline applied at the index level rather than the body level.

**Non-goals**:
- Touching any other skill not currently carrying an `Optional extensions` block — no proactive renames or restructures.
- Editing the `references/*.md` files themselves (descriptions in `## References` may be lightly polished; full reference-doc edits out of scope).
- Changing the body content of `SKILL.md` — only the duplicate index block is removed.
- Adopting any new index-section name as a replacement (e.g. `## Further reading`) — the spec names exactly one section.

**Estimated trim**:

| Skill | `Optional extensions` block lines (approx) | Notes |
| --- | --- | --- |
| `django-frontend` | ~20 lines (lines 28–46) | Largest skill body in the repo; most entries already mirrored in `## References` |
| `django` | TBD — audit during /plan | |
| `deployment` | TBD — audit during /plan | |

Net trim: ~40-60 lines across three files; token-cost saving > line count since every line is fully-loaded markdown.

**Related**: [IDEA-002](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md) — prior skill-debloat sweep that established the load-on-demand precedent at the body level. Pattern extends to the index level here.

**Implementation note**: Each skill is independent; sweep can fan out as three parallel commits on a single feature branch, or one commit per skill. No cross-file dependencies. Suitable for sprint-auto unattended execution given the gate-clearance above — but the visual-diff sanity check on a 620-line SKILL.md is light enough that solo `/work` also fits.
