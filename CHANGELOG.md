# Changelog

All notable changes to mind-vault — skills, rules, agents, commands, tools.

Mind-vault is a rolling config library, not a versioned package. Entries are grouped by month, reverse-chronological within each month, and each bullet references the PR whose merge introduced the change. Older than the first entry: the `git log` is authoritative.

Category keys follow [Keep a Changelog](https://keepachangelog.com/): **Added**, **Changed**, **Fixed**, **Removed**, **Deprecated**, **Security**.

## Unreleased

PRs open and not yet merged to main.

- **Added** `/wrap` skill — post-merge documentation + cleanup sweep. Flips IDEA frontmatter to `complete`, re-sorts the ideas index, appends a devlog entry, tears down worktree stacks, scans project docs for stale references. Sits between `/work`'s merge and `/compound`'s learning-routing. Self-mode on mind-vault (this repo) skips IDEA steps, runs docs-scan against this CHANGELOG + READMEs. ([#49](https://github.com/infohata/mind-vault/pull/49))
- **Added** `AGENT_bugbot` pass + `skills/django/references/TESTING.md` — three compound learnings from teisutis PR #330. ([#49](https://github.com/infohata/mind-vault/pull/49))
- **Changed** `/bugbot-loop` retry cadence: exponential 180 → 600 → 1200s replaced with **linear 270s** — each wake stays inside the 300s prompt-cache TTL; the only backstop is `max_idle_polls = 20`. ([#49](https://github.com/infohata/mind-vault/pull/49))

## 2026-04

- **Added** `/sprint-auto` skill + canonical `tools/sprint-auto-bootstrap.sh` + wrapper/hooks templates — overnight unattended orchestrator that runs a curated list of opt-in IDEAs through `/plan` → `/work` → PR creation in per-IDEA git worktrees with independent docker-compose stacks. Belt-and-suspenders opt-in (`auto_safe: true` frontmatter + explicit arg allowlist); never merges; worktrees preserved after each run. (2026-04-20, [#48](https://github.com/infohata/mind-vault/pull/48))
- **Changed** `tools/bugbot.sh` canonicalised — merged variants into a single script and added the `BUGBOT_CLEAN_SIGNAL` marker to `find_bugbot_comments.sh` so `/bugbot-loop` can fast-hand-back on clean reviews without waiting out the idle-poll bound. (2026-04-20, [#47](https://github.com/infohata/mind-vault/pull/47))
- **Added** `RULE_ideas-location-status` — IDEA files live in exactly two places: `docs/ideas/IDEA-NNN-<slug>.md` while `status: idea`, `docs/archive/YYYY-MM-idea-NNN-<slug>/` thereafter. Single `git mv` at `/plan` time; all subsequent status transitions are frontmatter-only. (2026-04-20, [#46](https://github.com/infohata/mind-vault/pull/46))
- **Changed** top-level `README.md` restructured — sprint workflow moved to the top, mermaid loop added, sections grouped by Sprint / Cross-project / Meta. (2026-04-20, [#45](https://github.com/infohata/mind-vault/pull/45))
- **Added** Sprint workflow Phase 2: `/ideate` skill (divergent-scan + adversarial filter above `/idea`) and `AGENT_curator` sprint-end promotion sweep mode (scans `docs/solutions/` for recurring patterns, proposes `/compound --promote` invocations). (2026-04-20, [#44](https://github.com/infohata/mind-vault/pull/44))
- **Added** `skills/skill-writer/` emitted-templates portability rule — when a skill pattern supports multiple source-file locations, never hardcode relative paths in emitted templates; compute them from the source's directory at emit time. (Compounded from PR #42 F1.) (2026-04-20, [#43](https://github.com/infohata/mind-vault/pull/43))
- **Added** Sprint workflow Phase 1: five-stage CE-inspired loop `/idea` → `/plan` (alias `/brainstorm`) → `/work` → `/bugbot-loop` → `/compound`, plus `/ingest-backlog` brownfield-takeover helper. `docs/SPRINT_WORKFLOW.md` becomes authoritative for the IDEA frontmatter schema. (2026-04-19, [#42](https://github.com/infohata/mind-vault/pull/42))
- **Added** `skills/django/` django-tenants parallel-test patterns — pytest-xdist + schema pooling for tenant-aware test runs. (2026-04-18, [#41](https://github.com/infohata/mind-vault/pull/41))
- **Changed** Cross-host mind-vault revamp — consolidated skills/agents/setup-scripts/docs structure that the rolling config library has run on since. (2026-04-18, [#40](https://github.com/infohata/mind-vault/pull/40))

## How this gets maintained

`/wrap` run on mind-vault itself (self-mode) appends a new entry under **Unreleased** automatically — the skill's Step 4 on self-mode targets this file instead of the per-project `docs/archive/YYYY-MM-DEVELOPMENT_LOG.md`. On merge, manually promote the **Unreleased** entry into the current `## YYYY-MM` section.

For manual entries (out-of-band doc updates, etc.): prepend under **Unreleased** before merge; promote to the dated section after.

Git log remains the source of truth; this file is the curated, human-readable summary.
