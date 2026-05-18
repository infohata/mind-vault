# mind-vault Ideas Index

_Two locations per [`RULE_ideas-location-status`](../../skills/idea/references/IDEAS_LOCATION_STATUS.md): `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

_(none)_

## 💡 High Priority (backlog)

_(none)_

## 💡 Medium Priority (backlog)

### IDEA-003: Version-tag automation post-`/wrap`

**Status**: 💡 **idea** · **Created**: 2026-05-18 · **See**: [`IDEA-003-version-tag-automation.md`](IDEA-003-version-tag-automation.md).
Automate the `git tag v<N>` + `gh release create` step that currently lives outside `/wrap`. Step 4b (introduced in [PR #121](https://github.com/infohata/mind-vault/pull/121)) updates the in-repo version source on merge, but the git tag remains manual. Two options surfaced during PR #121 review: Makefile `release` target (cheap, opt-in) vs GitHub Action `release-on-version-bump.yml` (hands-off). Recommendation: ship Option 1 first, layer Option 2 on later if the manual step proves forgettable in practice.

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

_(none)_

## ✅ References — Implemented

### IDEA-002: Skill debloat — extract over-budget SKILL.md bodies into references/ ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md), [PR #107](https://github.com/infohata/mind-vault/pull/107) (Phase 1 — wrap), [PR #109](https://github.com/infohata/mind-vault/pull/109) (Phase 2 — django-frontend), [PR #110](https://github.com/infohata/mind-vault/pull/110) (Phase 3 — django).
Three-phase debloat across `wrap/SKILL.md` (-43%, -236L), `django-frontend/SKILL.md` (-33%, -307L), and `django/SKILL.md` (-26%, -205L). **748L total saved across 2,268L of original SKILL.md bodies (-33%)**. Twelve new `references/*.md` files emitted, each loading on demand only when the consuming agent's task touches the relevant pattern. Token cost reclaimed per skill activation roughly proportional to body savings — meaningful at sprint-auto-scale invocation rates. Pattern matches PR #106's rules-reorg precedent (always-on vs load-on-demand) extended from `rules/` to `skills/<owner>/SKILL.md`.

### IDEA-001: Playwright Direction-1 plumbing — assets, gate, preflight ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-001-playwright-plumbing/IDEA-001-playwright-plumbing.md), [PR #106](https://github.com/infohata/mind-vault/pull/106).
Direction-1 (in-stack browser automation) plumbing landed — `setup_playwright.sh.template` bootstrap script, three new `skills/django-frontend/references/` files (`HTMX_ALPINE_WAITS.md`, `MULTI_TENANT_PLAYWRIGHT.md`, `VISUAL_BASELINE_BUMPS.md`), three-branch IDEA-level `requires_playwright` gate, `/wrap` Step 7 Playwright-coverage pre-fill algorithm, `AGENT_architect` /plan-time project probes, and a rules-reorg moving 6 domain-specific RULE files into `skills/<owner>/references/` (saving ~14K tokens off unconditional load). Ships the precedent that IDEA-002 Phase 1 extends.
