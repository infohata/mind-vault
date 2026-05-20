# mind-vault Ideas Index

_Two locations per [`RULE_ideas-location-status`](../../skills/idea/references/IDEAS_LOCATION_STATUS.md): `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

_(none)_

## 💡 High Priority (backlog)

### IDEA-167: Review-loop shared core — unify /bugbot-loop + /copilot-loop with engine adapters

**Status**: 💡 Backlog · **Created**: 2026-05-20 · **See**: [IDEA-167](idea-167/IDEA-167-review-loop-shared-core.md).
`/bugbot-loop` and `/copilot-loop` are ~90% structurally identical. PR #129 (IDEA-166) made the duplication cost concrete — every bugbot-finding fix touched mirrored sections in both `commands/bugbot-loop.md` + `commands/copilot-loop.md` (cycle 1: 4 edits for 2 logical changes; cycle 2: 6 edits for 3 logical changes). Two options captured: **(1)** shared `skills/review-loop/` skeleton + per-engine adapters in `references/engine-*.md`, with `/bugbot-loop` + `/copilot-loop` as thin wrappers and `/review-loop` as direct multi-engine entry point — preferred because dual-engine concurrent execution becomes first-class, not a coincidence of running two loops with an ad-hoc sync block; **(2)** shared `references/review-loop-core.md` both skills `[[link]]` into — lower-risk fallback, fits references/ pattern, but doesn't make dual-engine concurrency first-class. Rename-before-drop sequencing applies: shared skill lands first, wrappers cut over second, legacy prose removed in a follow-up sprint.

## 💡 Medium Priority (backlog)

_(none)_

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

_(none)_

## ✅ References — Implemented

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
