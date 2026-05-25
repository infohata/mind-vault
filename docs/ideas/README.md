# mind-vault Ideas Index

_Two locations per [`RULE_ideas-location-status`](../../skills/idea/references/IDEAS_LOCATION_STATUS.md): `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

_(none)_

## 💡 High Priority (backlog)

_(none)_

## 💡 Medium Priority (backlog)

_(none)_

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

_(none)_

## ✅ References — Implemented

### IDEA-006: v4.3 review-surface collapse — single `/review-loop` entry ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-25 · **See**: [Archive](../archive/2026-05-idea-006-review-surface-collapse/IDEA-006-review-surface-collapse.md), [PR #139](https://github.com/infohata/mind-vault/pull/139) + [PR #140](https://github.com/infohata/mind-vault/pull/140).
Deleted `AGENT_bugbot.md` + `AGENT_copilot.md` (sub-agent profiles) and the deprecated `/bugbot-loop` + `/copilot-loop` command wrappers, leaving `/review-loop <PR> <engine>` as the sole review entry point. The two **word-for-word identical** Tier-1 catalogues consolidated into one shared [`common-review-findings.md`](../../skills/review-loop/references/common-review-findings.md) (deduplicated against existing vault homes, not just across engines). `sprint-auto` now dispatches a single multi-engine `/review-loop` call (concurrent sync, N-engine-general). Shipped in two PRs per [`rename-before-drop`](../../rules/RULE_rename-before-drop.md): #139 prepare (migrate + rewire), #140 drop (delete) — ships as **v4.3**. Extends [IDEA-005](../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md)'s shared-core refactor to the agent + command surfaces.

### IDEA-007: Consolidate `Optional extensions` blocks into `## References` across feature-dense skills ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-22 · **See**: [Archive](../archive/2026-05-idea-007-consolidate-optional-extensions/IDEA-007-consolidate-optional-extensions-into-references.md), [PR #135](https://github.com/infohata/mind-vault/pull/135).
Swept the three feature-dense skills (`deployment`, `django`, `django-frontend`) that carried a duplicate index of `references/*.md` files — top-of-file `**Optional extensions** (load on demand):` block + bottom-of-file `## References` section. Per file: diffed top vs bottom, promoted any richer descriptions down, added genuinely-unique top entries, deleted the top block. **-39 lines total** (-12 django, -8 deployment, -19 django-frontend) — savings on every per-activation context load of three of the highest-frequency skills in the vault. Also dropped the same `Optional extensions` terminology from `skills/deployment/README.md`'s tree-diagram comment. Index-level continuation of [IDEA-002](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md)'s body-level debloat lever; the single-References-block rule had just been codified during PR #134 in `skills/skill-writer/SKILL.md` body §"Body structure" item 5.

### IDEA-005: Review-loop shared core — unify /bugbot-loop + /copilot-loop with engine adapters ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-20 · **See**: [Archive](../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md), [PR #131](https://github.com/infohata/mind-vault/pull/131).
Extracted the duplicated Phase 0/1/2/3/4 orchestrator from `commands/bugbot-loop.md` + `commands/copilot-loop.md` into a single `skills/review-loop/SKILL.md` driven by per-engine adapter references (`engine-bugbot.md`, `engine-copilot.md`, `engine-adapter-contract.md`, `dual-engine-sync.md`). New `commands/review-loop.md` is the canonical multi-engine entry; the two existing commands cut from ~260L each to ~15L thin wrappers. Dual-engine concurrent execution is now a first-class supported mode with explicit per-engine spacing, asymmetric-clearance hand-back, and N-engine generalisation in the adapter contract. The rename absorbed from PR #130 was bundled into the same merge; cross-project numbering guard added in `skills/idea/SKILL.md` to prevent recurrence of the IDEA-167 → IDEA-005 confusion that motivated the rename. **Dogfood validation**: 10 cycles of `/review-loop 131 bugbot,copilot` on the implementation PR surfaced ~50 findings across 7 files, demonstrating the dual-engine value (each engine consistently caught issues the other missed). Spinoff: [IDEA-006](../archive/2026-05-idea-006-review-surface-collapse/IDEA-006-review-surface-collapse.md) extends the same delegation treatment to `AGENT_bugbot.md` + `AGENT_copilot.md`.

### IDEA-004: ONBOARDING — full dev-environment walkthrough ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-20 · **See**: [Archive](../archive/2026-05-idea-004-onboarding-walkthrough/IDEA-004-onboarding-dev-env-walkthrough.md), [PR #128](https://github.com/infohata/mind-vault/pull/128).
Shipped the ONBOARDING expansion as a landing-page + companion-docs structure (chosen over single-page-with-TOC for progressive-disclosure fit). `docs/guides/ONBOARDING.md` gained an inline § 2 "AI concepts — rules vs skills vs agents vs commands" comparison table, § 5 "Useful Claude Code commands" toolbox (`/context`, `/usage`, `/effort`, `/compact`, `/new`, `/resume`, `/init`, `/help`) with a "context window vs subscription limits" callout disambiguating the two budgets, a top-of-file TOC, and § 7 deep-dives index. Four new companion guides under `docs/guides/`: `GIT_WORKFLOW.md` (branch-per-IDEA, dual-engine review, integration branches, force-push hygiene), `WORKTREE_PRACTICES.md` (parallel worktrees, port-offset discipline, `.env` isolation exception, sprint-auto integration-worktree pattern), `SKILL_AUTHORING_WALKTHROUGH.md` (process companion to SKILL_SPECIFICATION: decision tree for skill-vs-rule-vs-command-vs-agent, 500-line body budget, anti-patterns, `/compound` route), `MEMORY_MANAGEMENT.md` (four-layer persistence model — auto-memory / `CLAUDE.md` / skills+rules / project docs — rot detection + pruning cadence, verify-before-acting). Coupled structural move: relocated all 8 top-level guides into `docs/guides/` so `docs/` root stays a clean index; 16 cross-referencing files updated. CHANGELOG order corrected to reverse-chrono with `## v4` → `## v4.0.1` rename (aligns with actual git tag); shipped as v4.0.4.

### IDEA-003: Version-tag automation post-`/wrap` ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-19 · **See**: [Archive](../archive/2026-05-idea-003-version-tag-automation/IDEA-003-version-tag-automation.md), [PR #124](https://github.com/infohata/mind-vault/pull/124).
Shipped Option 1 — `Makefile` `release` target + `extract-version` + `test-release` + `help`, with version-extraction covering the six sources `/wrap` Step 4b detects (`VERSION` / `pyproject.toml` / `package.json` / `Cargo.toml` / `setup.py` / `CHANGELOG.md` with both `## v<N>` and Keep-a-Changelog `## [<N>]` header forms). Explicit `VERSION=v<N>` override for projects whose CHANGELOG header version differs from the intended tag (mind-vault itself: CHANGELOG `## v4` but tags `v4.0.1`, `v4.0.2`, ...). Idempotency via `git rev-parse --verify --quiet refs/tags/$ver`. Ten-case bash test harness (`tests/test_release_extraction.sh`) covers seven source-format paths + two `VERSION=` override paths + one no-source error case; all green on first run. `/wrap` Step 4b § "Mechanics when a bump is warranted" gained sub-bullet 6 surfacing `make release` as the canonical post-merge hand-back (with manual-fallback mention for Makefile-less projects). Option 2 (GHA auto-tag-on-merge) intentionally deferred to a follow-up IDEA pending empirical evidence the manual step gets forgotten.

### IDEA-002: Skill debloat — extract over-budget SKILL.md bodies into references/ ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md), [PR #107](https://github.com/infohata/mind-vault/pull/107) (Phase 1 — wrap), [PR #109](https://github.com/infohata/mind-vault/pull/109) (Phase 2 — django-frontend), [PR #110](https://github.com/infohata/mind-vault/pull/110) (Phase 3 — django).
Three-phase debloat across `wrap/SKILL.md` (-43%, -236L), `django-frontend/SKILL.md` (-33%, -307L), and `django/SKILL.md` (-26%, -205L). **748L total saved across 2,268L of original SKILL.md bodies (-33%)**. Twelve new `references/*.md` files emitted, each loading on demand only when the consuming agent's task touches the relevant pattern. Token cost reclaimed per skill activation roughly proportional to body savings — meaningful at sprint-auto-scale invocation rates. Pattern matches PR #106's rules-reorg precedent (always-on vs load-on-demand) extended from `rules/` to `skills/<owner>/SKILL.md`.

### IDEA-001: Playwright Direction-1 plumbing — assets, gate, preflight ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-001-playwright-plumbing/IDEA-001-playwright-plumbing.md), [PR #106](https://github.com/infohata/mind-vault/pull/106).
Direction-1 (in-stack browser automation) plumbing landed — `setup_playwright.sh.template` bootstrap script, three new `skills/django-frontend/references/` files (`HTMX_ALPINE_WAITS.md`, `MULTI_TENANT_PLAYWRIGHT.md`, `VISUAL_BASELINE_BUMPS.md`), three-branch IDEA-level `requires_playwright` gate, `/wrap` Step 7 Playwright-coverage pre-fill algorithm, `AGENT_architect` /plan-time project probes, and a rules-reorg moving 6 domain-specific RULE files into `skills/<owner>/references/` (saving ~14K tokens off unconditional load). Ships the precedent that IDEA-002 Phase 1 extends.
