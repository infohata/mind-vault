# mind-vault Ideas Index

_Two locations per [`RULE_ideas-location-status`](../../skills/idea/references/IDEAS_LOCATION_STATUS.md): `docs/ideas/` = backlog;
`docs/archive/YYYY-MM-idea-NNN-<slug>/` = everything that's left backlog,
differentiated by frontmatter `status:`._

## 🚧 In Progress

- [IDEA-002](../archive/2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md) ⏳ — Skill debloat — extract over-budget SKILL.md bodies into references/ (Phase 1 shipped via PR #107; Phases 2 + 3 queued)

## 💡 High Priority (backlog)

_(none)_

## 💡 Medium Priority (backlog)

_(none)_

## 💡 Low Priority (backlog)

_(none)_

## 🗃 Superseded / Rejected (archive)

_(none)_

## ✅ References — Implemented

### IDEA-001: Playwright Direction-1 plumbing — assets, gate, preflight ✅ COMPLETE

**Status**: ✅ **COMPLETE** · **Completed**: 2026-05-09 · **See**: [Archive](../archive/2026-05-idea-001-playwright-plumbing/IDEA-001-playwright-plumbing.md), [PR #106](https://github.com/infohata/mind-vault/pull/106).
Direction-1 (in-stack browser automation) plumbing landed — `setup_playwright.sh.template` bootstrap script, three new `skills/django-frontend/references/` files (`HTMX_ALPINE_WAITS.md`, `MULTI_TENANT_PLAYWRIGHT.md`, `VISUAL_BASELINE_BUMPS.md`), three-branch IDEA-level `requires_playwright` gate, `/wrap` Step 7 Playwright-coverage pre-fill algorithm, `AGENT_architect` /plan-time project probes, and a rules-reorg moving 6 domain-specific RULE files into `skills/<owner>/references/` (saving ~14K tokens off unconditional load). Ships the precedent that IDEA-002 Phase 1 extends.
