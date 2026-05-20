# mind-vault Ideas Index

_Two locations per [`RULE_ideas-location-status`](../../skills/idea/references/IDEAS_LOCATION_STATUS.md): `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

_(none)_

## 💡 High Priority (backlog)

_(none)_

## 💡 Medium Priority (backlog)

### IDEA-004: ONBOARDING — full dev-environment walkthrough

**Status**: 💡 **idea** · **Created**: 2026-05-19 · **See**: [`IDEA-004-onboarding-dev-env-walkthrough.md`](IDEA-004-onboarding-dev-env-walkthrough.md).
Extend `docs/ONBOARDING.md` from a 30-minute mind-vault tour into a full clone-and-go dev-environment walkthrough: IDE install (VSCode / Cursor), Claude Code CLI + VSCode plugin, mind-vault setup script, productive Claude Code settings (auto-mode, plugin set), per-stack add-ons, **plus dev-env hygiene best practices** (`.env` isolation, `.gitignore` baseline, secret-handling discipline, `docker compose` conventions, branch hygiene, hook/permission setup). Target: green-field engineer productive in ≤ 90 min. Motivated by v4 going OSS-release candidate while ONBOARDING still assumes the reader already has the stack set up.

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

_(none)_

## ✅ References — Implemented

### IDEA-003: Version-tag automation post-`/wrap` ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-19 · **See**: [Archive](../archive/2026-05-idea-003-version-tag-automation/IDEA-003-version-tag-automation.md), [PR #124](https://github.com/infohata/mind-vault/pull/124).
Shipped Option 1 — `Makefile` `release` target + `extract-version` + `test-release` + `help`, with version-extraction covering the six sources `/wrap` Step 4b detects (`VERSION` / `pyproject.toml` / `package.json` / `Cargo.toml` / `setup.py` / `CHANGELOG.md` with both `## v<N>` and Keep-a-Changelog `## [<N>]` header forms). Explicit `VERSION=v<N>` override for projects whose CHANGELOG header version differs from the intended tag (mind-vault itself: CHANGELOG `## v4` but tags `v4.0.1`, `v4.0.2`, ...). Idempotency via `git rev-parse --verify --quiet refs/tags/$ver`. Ten-case bash test harness (`tests/test_release_extraction.sh`) covers seven source-format paths + two `VERSION=` override paths + one no-source error case; all green on first run. `/wrap` Step 4b § "Mechanics when a bump is warranted" gained sub-bullet 6 surfacing `make release` as the canonical post-merge hand-back (with manual-fallback mention for Makefile-less projects). Option 2 (GHA auto-tag-on-merge) intentionally deferred to a follow-up IDEA pending empirical evidence the manual step gets forgotten.

### IDEA-002: Skill debloat — extract over-budget SKILL.md bodies into references/ ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md), [PR #107](https://github.com/infohata/mind-vault/pull/107) (Phase 1 — wrap), [PR #109](https://github.com/infohata/mind-vault/pull/109) (Phase 2 — django-frontend), [PR #110](https://github.com/infohata/mind-vault/pull/110) (Phase 3 — django).
Three-phase debloat across `wrap/SKILL.md` (-43%, -236L), `django-frontend/SKILL.md` (-33%, -307L), and `django/SKILL.md` (-26%, -205L). **748L total saved across 2,268L of original SKILL.md bodies (-33%)**. Twelve new `references/*.md` files emitted, each loading on demand only when the consuming agent's task touches the relevant pattern. Token cost reclaimed per skill activation roughly proportional to body savings — meaningful at sprint-auto-scale invocation rates. Pattern matches PR #106's rules-reorg precedent (always-on vs load-on-demand) extended from `rules/` to `skills/<owner>/SKILL.md`.

### IDEA-001: Playwright Direction-1 plumbing — assets, gate, preflight ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-001-playwright-plumbing/IDEA-001-playwright-plumbing.md), [PR #106](https://github.com/infohata/mind-vault/pull/106).
Direction-1 (in-stack browser automation) plumbing landed — `setup_playwright.sh.template` bootstrap script, three new `skills/django-frontend/references/` files (`HTMX_ALPINE_WAITS.md`, `MULTI_TENANT_PLAYWRIGHT.md`, `VISUAL_BASELINE_BUMPS.md`), three-branch IDEA-level `requires_playwright` gate, `/wrap` Step 7 Playwright-coverage pre-fill algorithm, `AGENT_architect` /plan-time project probes, and a rules-reorg moving 6 domain-specific RULE files into `skills/<owner>/references/` (saving ~14K tokens off unconditional load). Ships the precedent that IDEA-002 Phase 1 extends.
