# Changelog

All notable changes to mind-vault — skills, rules, agents, commands, tools.

Mind-vault is a rolling config library, not a versioned package. Entries are grouped by month, reverse-chronological within each month, and each bullet references the PR whose merge introduced the change. Older than the first entry: the `git log` is authoritative.

Category keys follow [Keep a Changelog](https://keepachangelog.com/): **Added**, **Changed**, **Fixed**, **Removed**, **Deprecated**, **Security**.

## Unreleased

PRs open and not yet merged to main.

(none)

## 2026-04

- **Added** `tools/install-mosh-tmux.sh` — resilient-SSH installer for spotty links. Installs mosh + tmux on Debian/Ubuntu, writes a marker-bounded `~/.tmux.conf` with truecolor + scrollback + mouse defaults, adds an SSH-only auto-attach snippet to `~/.bashrc`, opens UDP 60000:61000 in UFW when active. `--check` / `--no-ufw` / `--no-autoattach` / `--no-tmux-config` / `--session-name` / `--target-user` flags. (2026-04-22, [#59](https://github.com/infohata/mind-vault/pull/59))
- **Added** `skills/deployment/references/SHELL_INSTALLERS.md` — canonical authoring + review reference for `tools/install-*.sh` scripts. 15 patterns distilled from bugbot review cycles across PRs #55 (install-gcloud-cli), #58 (wrap SKILL chown fallback), #59 (install-mosh-tmux): the `set -eo pipefail` family (pipeline-in-assignment silent abort, `head -N` SIGPIPE race), `chown 'user:'` vs `'user:user'`, marker-block regex-metacharacter hazards + unclosed-sed-range EOF truncation, `case` vs `grep -E` for security-sensitive validation (newline bypass), opt-out flag cross-cutting sweep, substring-match traps, HEREDOC quoting discipline, target-user resolution, idempotency-respects-flags, post-install session-restart requirement. Each pattern has bad/good examples + provenance. (2026-04-22, [#59](https://github.com/infohata/mind-vault/pull/59))
- **Changed** `agents/AGENT_bugbot.md` §9 — slimmed from inline pattern list to a quick-index pointing at `SHELL_INSTALLERS.md` for details. Reduces duplication between drill-side and author-side references; single source of truth going forward. (2026-04-22, [#59](https://github.com/infohata/mind-vault/pull/59))
- **Changed** `tools/README.md` "Adding New Tools" — slimmed to a 6-item contributor muscle-memory list + pointer to `SHELL_INSTALLERS.md`. Replaced inline template with an annotated skeleton. (2026-04-22, [#59](https://github.com/infohata/mind-vault/pull/59))
- **Added** `skills/deployment/references/CONTAINER_DNS_NSS.md` + `commands/bugbot-loop.md` dual-signal enumeration + `skills/wrap/SKILL.md` per-file teardown evaluation — compound PR from teisutis sprint-auto dogfood learnings. DNS-NSS reference captures the hostname=domain/`getaddrinfo`-loopback trap; bugbot-loop Phase 1 now mandates `/reviews` + `/comments` dual-signal output with staleness rule for persistent inline comments; wrap step 5 adds a 4-class per-file evaluation for worktree teardown refusals (forgotten commit / missing gitignore / stale ephemera / container-as-root permission residue). (2026-04-21, [#58](https://github.com/infohata/mind-vault/pull/58))
- **Fixed** `tools/sprint-auto-bootstrap.sh` IPAM override — reset pinned subnet + per-service `ipv4_address` entries when the parent compose file pins them, avoiding worktree-vs-primary subnet collisions. (2026-04-21, [#57](https://github.com/infohata/mind-vault/pull/57))
- **Fixed** `tools/sprint-auto-bootstrap.sh` sed delimiter collision in SALT|HMAC sentinel generation — sed address pattern used a delimiter that could collide with sentinel content; switched to a safer delimiter. (2026-04-21, [#56](https://github.com/infohata/mind-vault/pull/56))
- **Added** `tools/install-gcloud-cli.sh` — apt-based Google Cloud CLI installer for Debian/Ubuntu. System-wide install via Google's official apt repo with dearmored keyring (no deprecated `apt-key`). `--check` / `--with-components` flags. (2026-04-21, [#55](https://github.com/infohata/mind-vault/pull/55))
- **Fixed** `skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper` template — aborted silently when executed outside a git repo; now errors early with a clear message. (2026-04-21, [#54](https://github.com/infohata/mind-vault/pull/54))
- **Added** `tools/install-oh-my-posh.sh` — user-scope prompt theme installer (no sudo). Curated 10-theme interactive menu, marker-bounded `~/.bashrc` / `~/.zshrc` / pwsh wiring, `--theme NAME` for non-interactive CI. (2026-04-21, [#53](https://github.com/infohata/mind-vault/pull/53))
- **Removed** 8 skill-duplicate command wrappers — consolidated after skill discovery shipped; thin wrapper commands that only forwarded to already-discoverable skills were redundant. (2026-04-21, [#51](https://github.com/infohata/mind-vault/pull/51))
- **Changed** CHANGELOG promotion — PR #49 entries moved from `## Unreleased` into the `## 2026-04` dated section, demonstrating the self-mode `/wrap` flow. (2026-04-21, [#50](https://github.com/infohata/mind-vault/pull/50))
- **Added** `/wrap` skill — post-merge documentation + cleanup sweep. Flips IDEA frontmatter to `complete`, re-sorts the ideas index, appends a devlog entry, tears down worktree stacks, scans project docs for stale references. Sits between `/work`'s merge and `/compound`'s learning-routing. Self-mode on mind-vault (this repo) skips IDEA steps, runs docs-scan against this CHANGELOG + READMEs. (2026-04-20, [#49](https://github.com/infohata/mind-vault/pull/49))
- **Added** `AGENT_bugbot` pass + `skills/django/references/TESTING.md` — three compound learnings from teisutis PR #330. (2026-04-20, [#49](https://github.com/infohata/mind-vault/pull/49))
- **Changed** `/bugbot-loop` retry cadence: exponential 180 → 600 → 1200s replaced with **linear 270s** — each wake stays inside the 300s prompt-cache TTL; the only backstop is `max_idle_polls = 20`. (2026-04-20, [#49](https://github.com/infohata/mind-vault/pull/49))

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

`/wrap` run on mind-vault itself (self-mode) maintains this file end-to-end — Step 4 of the skill both adds new entries for the just-merged PR and promotes any existing `## Unreleased` bullets into the current `## YYYY-MM` section, so `Unreleased` is empty (or lists truly open-and-unmerged PRs) after every wrap. No human promotion step required.

For out-of-band manual entries (doc updates landed without a wrap run): prepend under **Unreleased** before merge. The next wrap run will promote them automatically.

Git log remains the source of truth; this file is the curated, human-readable summary.
