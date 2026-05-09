---
id: 1
title: Playwright Direction-1 plumbing — assets, gate, preflight
status: complete
priority: high
supersedes: []
superseded_by: null
depends_on: []
related: [002]
created: 2026-05-09
completed: 2026-05-09
auto_safe: false
auto_safe_reason: "Touches sprint-auto + wrap skill semantics + introduces a new IDEA-level eligibility gate (`requires_playwright`). Wants human review before unattended runs depend on it."
sensitive_paths_cleared: false
sensitive_paths_cleared_reason: "Edits skills that gate sprint-auto execution (SKILL.md, safety-gates.md, AGENT_architect.md). Misconfiguration could let an IDEA fall through the gate; needs eyes-on review."
---

# IDEA-001: Playwright Direction-1 plumbing — assets, gate, preflight

**Status**: 🚧 In Progress
**Priority**: High

**Problem**: `skills/sprint-auto/ROADMAP.md` (PR #105) describes Direction-1 (Playwright-driven browser tests in the dev image) at near-plan depth — bootstrap script shape, IDEA-level gate semantics, cross-reference contract — but none of the assets exist yet. Until the assets land, every forward-looking pointer in the ROADMAP is a dangling reference, the IDEA-level `requires_playwright` gate is documented behaviour with no implementation, and the first project to adopt Direction-1 has no `setup_playwright.sh.template` to copy.

**Proposal**: Land the mind-vault-side plumbing for Direction 1 in one IDEA — no first-pilot Playwright tests, no project-side adoption. Just the assets, the gate, the preflight, and the cross-reference contract, all wired together so a downstream "first project to adopt" IDEA (filed in a real consumer like teisutis) has a working surface to copy from.

**Why now**:
- ROADMAP (PR #105) is plan-depth. Treating it as the plan and skipping `/plan` is the right shape — the discovery work is already done and architectural-reviewed.
- Every cycle spent NOT shipping these assets is a cycle where the ROADMAP's forward-looking pointers stay dangling. Inconsistency rots references.
- Direction 2 (`auto_safe_with_eval_gate`) shipped already. Direction 1 is the planned uplift that shrinks Direction 2's manual-walk surface — the longer the gap, the more linear cost the cohort eats per IDEA.

**Non-goals**:
- Not authoring the first concrete Playwright tests. That's a downstream IDEA in a real project (teisutis is the natural pilot — it has the most Cotton/Alpine/HTMX surface).
- Not running the bootstrap script against any project. The script template lives in mind-vault; running it is the consumer project's first Direction-1 IDEA.
- Not changing visual-regression workflow conventions beyond what [`VISUAL_BASELINE_BUMPS`](../../../skills/django-frontend/references/VISUAL_BASELINE_BUMPS.md) formalises.
- Not auto-detecting projects that already have Playwright infra (out of scope; current convention is "consumer project copies from mind-vault asset, runs once").

**Approach** (treating ROADMAP as plan, this section is the deliverables list):

| # | File | Action | Notes |
|---|------|--------|-------|
| 1 | `skills/django-frontend/references/VISUAL_BASELINE_BUMPS.md` | New | Visual-snapshot bump discipline — when to regenerate baselines, what to commit, review etiquette. (Initially landed as `rules/RULE_visual-baseline-bumps.md`; later moved to skill references in this same PR's tail commit alongside the broader rules-reorg.) |
| 2 | `skills/django-frontend/references/HTMX_ALPINE_WAITS.md` | New | The four-class HTMX wait recipe + Alpine settled-state pattern. Referenced from ROADMAP. |
| 3 | `skills/django-frontend/references/MULTI_TENANT_PLAYWRIGHT.md` | New | django-tenants + Playwright fixtures (host header, schema seeding, DB cleanup). |
| 4 | `skills/sprint-auto/assets/setup_playwright.sh.template` | New | Idempotent bootstrap — auto-detects Docker stack, CI shape, tenant model, locales. The meaty deliverable. |
| 5 | `skills/sprint-auto/SKILL.md` | Edit | Preflight: probe for Playwright in target project; route IDEAs by `requires_playwright` frontmatter + probe outcome. |
| 6 | `skills/sprint-auto/references/safety-gates.md` | Edit | Add `requires_playwright` flag to per-IDEA gate matrix; document three-branch noop semantics. |
| 7 | `agents/AGENT_architect.md` | Edit | At `/plan` time, probe project for Playwright presence + ask architect whether IDEA needs it; emit `requires_playwright` in plan. |
| 8 | `skills/wrap/SKILL.md` (Step 7) + `skills/wrap/assets/manual-evaluation-template.md` | Edit | `/wrap` reads `playwright_test_coverage` YAML block from plan, drops automated rows from eval checklist. |
| 9 | `skills/sprint-auto/ROADMAP.md` | Edit | Sync forward-looking references — turn `(planned)` into pointers at the now-existing files. |

**Commit ordering** (per `RULE_rename-before-drop` discipline, generalised to "stable references first, edits to consumers later"):

1. Commits 1–4 (new files) — independent, no edits to existing skills yet, references in ROADMAP still dangle.
2. Commits 5–8 (edits to existing skills) — reference the now-existing new files; ROADMAP still says "(planned)".
3. Commit 9 (ROADMAP sync) — flip every "(planned)" to a live link, last so the index is consistent in one move.

**Test strategy**: This IDEA ships docs + scripts + skill edits, no executable Python/JS. The validation surface is:
- Markdown lint (clean across all new/edited `.md`).
- Bash shellcheck on `setup_playwright.sh.template` (no execution; it's a template the consumer project parameterises).
- Cross-reference audit at the end: every link in the ROADMAP resolves; every reference from skill files resolves; every flag mentioned in `safety-gates.md` is consumed somewhere.

**Eval-gate** (`auto_safe_with_eval_gate` is shipped; this IDEA inherits Direction-2 semantics):
- Manual-evaluation rows: review the bootstrap script's auto-detection branches (Docker compose v1 / v2, GitHub Actions vs alternatives, django-tenants vs single-tenant) for sensible defaults.
- Sprint-auto eligibility: this IDEA itself is NOT auto-safe. Touching gate logic is exactly the class of change that wants human review before unattended runs depend on it.

**Related**: [ROADMAP.md](ROADMAP.md) (sibling artefact in this archive — was `skills/sprint-auto/ROADMAP.md` while IDEA-001 was in flight, archived alongside this IDEA file at PR #106 wrap). Roadmap-revision PR #105 (merged 2026-05-09). Architect critique + OSS research surfaced during PR #105 review cycle.
