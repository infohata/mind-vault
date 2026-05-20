---
id: 004
name: IDEA-004-onboarding-dev-env-walkthrough
description: Extend docs/guides/ONBOARDING.md from a "30-minute mind-vault tour" into a full clone-and-go dev-environment walkthrough — IDE install, Claude Code CLI + VSCode plugin, mind-vault setup script, recommended Claude Code settings + plugin set, per-stack add-ons, and dev-env hygiene best practices (.env isolation, .gitignore baseline, secret discipline, docker-compose conventions, branch hygiene, hook/permission setup). Target: green-field engineer productive in under 90 min.
status: idea
priority: medium
created: 2026-05-19
related:
  - 2026-05-idea-003-version-tag-automation  # ONBOARDING was just touched at v4.0.3
# Sprint-auto eligibility gates
auto_safe: false
auto_safe_reason: "Content-heavy walkthrough authoring — judgement calls on which plugins to recommend, what default settings to surface, how much per-stack depth to include, and screenshot/example inclusion. Sprint-auto's mechanical-verification harness can't gauge authorial quality."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Docs-only — touches docs/guides/ONBOARDING.md exclusively (plus maybe inline updates to README.md cross-refs). No infra / auth / schema / secrets surface."
---

# IDEA-004 — ONBOARDING.md: full dev-environment walkthrough

## Problem

`docs/guides/ONBOARDING.md` today is a 30-minute mind-vault-internals tour aimed at someone who already has VSCode / Cursor + Claude Code + a working shell environment. New adopters landing on a blank machine (or a fresh OS install) hit a much wider gap: where do I install the IDE? Where does Claude Code come from? How do I wire the VSCode plugin? Which plugins should I enable in Claude Code? What auto-mode settings does the user actually run with? After the v4.0.2 Windows-host bootstrap (PR #120) plus v4.0.3's `make release` helper (PR #124), the gap between "fresh OS" and "running a real sprint" is wider than ONBOARDING acknowledges.

## Proposal

Extend `docs/guides/ONBOARDING.md` into a green-field walkthrough that takes someone from blank-machine to "completed first sprint" in under 90 minutes. Sections to add ahead of (or restructured around) the current `§ 1 What mind-vault is`:

1. **§ Pre-flight — IDE setup.** VSCode vs Cursor decision tree (which to pick when), install links per OS, recommended workspace baseline (settings.json snippet, suggested core extensions: GitLens, Docker, Python, EditorConfig, etc.). For Windows: pointer to v4.0.2's `scripts/install-wsl.ps1` (already there but currently surfaced later).
2. **§ Install Claude Code.** CLI install (one-liner per OS), VSCode plugin install + auth flow, first-run verification. Distinguish "Claude Code CLI" vs "VSCode plugin" vs "claude.ai/code" so the reader knows what they're installing and why.
3. **§ Set up mind-vault.** Existing `## 3 Bring up mind-vault` content, possibly trimmed. Cover symlink script, host-picker, sanity check (`ls ~/.claude/skills`).
4. **§ Claude Code settings — the productive defaults.** What Kestas actually runs with: auto-mode-on (`claude --auto`?), permission-mode defaults, allowed-bash patterns, model selection (Opus 4.7 1M context for sprint work). Where these live (`~/.claude/settings.json`) and the canonical snippet.
5. **§ Recommended plugin set.** Walk through the productive plugin loadout: `superpowers` (foundational), `feature-dev` (architecture + review-loop), `skill-creator` (when authoring skills), and any others. For each: what it adds, when to invoke, what it pairs with.
6. **§ Per-stack add-ons.** Reference from the user's global `~/.claude/CLAUDE.md` conventions: Docker / docker compose, pyenv (no global pip), Make-target preference. Brief justification per item.
7. **§ Dev-environment hygiene + best practices.** The conventions every mind-vault-consuming project should adopt, ahead of touching code:
   - **`.env` isolation** — never commit `.env` (Kestas's global rule: agents must NEVER touch `.env`). Pattern: `.env.template` is committed (sentinel values), `.env` is local-only. Inside *git worktrees* there's a narrow exception per the global `CLAUDE.md` — sentinel-populated `.env` from template is allowed for disposable docker-volume bootstrap; never copy from the primary checkout's real `.env`.
   - **`.gitignore` baseline** — what every mind-vault-aware project should ignore: `.env`, `*.pyc`, `__pycache__/`, `.venv/`, `node_modules/`, IDE detritus (`.vscode/settings.json` if per-user, `.idea/`), docker volume mount-points (`pgdata/`, `redis-data/`), and any worktree-specific overrides (`docker-compose.override.yml` when sprint-auto auto-generates it).
   - **Secret-handling discipline** — credentials live in `.env` (gitignored); the test sentinel `test-not-a-real-key` is the canonical replacement when bootstrapping disposable environments; rotation discipline (regenerate when sharing screens / pushing screenshots / publishing logs). Agents must never grep / cat `.env`.
   - **Docker-compose conventions** — production parity in local dev (Daphne-only stack mirroring prod, nginx with `proxy_pass`, real Postgres + Redis containers, not SQLite). Where overrides live (root `docker-compose.override.yml` is user-local; sprint-auto's per-worktree override sits in the worktree). Bare `docker` commands forbidden — always `docker compose`.
   - **Branch hygiene** — never commit on `main` (per `RULE_git-safety`); how to recover from accidental main commits (`git stash` + create feature branch + `git stash pop`); the `--force-with-lease` rule (never plain `--force`); `--no-verify` is forbidden unless the user explicitly authorises.
   - **Hook + permission setup** — the productive `~/.claude/settings.json` patterns: pre-approved bash patterns (`docker compose *`, `make *`, etc.), denied destructive patterns (`rm -rf *`, `git reset --hard *` without prompt), audit-hook installation. Cross-link `/update-config` skill.
8. **§ First sprint walkthrough.** The existing 30-minute tour, now reframed as "your first sprint" — `/ideate` (optional) → `/idea` → `/plan` → `/work` → review-loop → `/wrap` → `/compound`. Concrete worked example pointer (could reference IDEA-003's archive dir as the dogfood case study).

The deliverable is a doc that a stranger could clone-and-go from — not just a mind-vault summary.

## Why now

- v4 is the open-source release candidate. The README's `v4` headline talks about "you can adopt this" but ONBOARDING currently assumes the adopter is already set up to adopt. The gap matters for actual adoption.
- v4.0.2 (Windows bootstrap) + v4.0.3 (`make release`) just landed back-to-back; both touched ONBOARDING in small ways. Now's the moment to do the bigger rewrite while the file is fresh in mind.
- Kestas runs a very specific productive Claude Code config (auto-mode, plugin set, settings choices) that adopters cannot reverse-engineer from the repo. Capturing the convention is itself a compound learning.

## Non-goals

- NOT a full Claude Code reference manual — point at official Anthropic docs for the deep CLI surface.
- NOT a stack tutorial — `pyenv` / `docker compose` deep-dives belong in their upstream docs, just mention what mind-vault assumes.
- NOT a beginner programming guide — readers are assumed to be experienced engineers new to *this stack / agent setup*, not new to programming.
- NOT screencasts / videos — markdown-only, copy-pasteable commands.

## Acceptance criteria

- [ ] `docs/guides/ONBOARDING.md` has the eight sections above (or a justified subset / reorganisation).
- [ ] The dev-env hygiene section codifies the conventions a new project should adopt before its first commit (`.env.template` shape, `.gitignore` baseline, sentinel-replacement pattern for disposable bootstraps, `docker compose`-not-`docker` discipline, the branch-hygiene recovery recipes).
- [ ] A new reader on a blank machine could go from "git clone" to "first `/wrap` finished" in ≤ 90 minutes following the doc.
- [ ] Each section has a verifiable success-check (e.g. "`claude --version` returns 4.x", "`ls ~/.claude/skills` shows symlinks", "`make help` lists targets").
- [ ] Plugin recommendations are versioned (so we can update when the plugin set evolves).
- [ ] Settings snippet for `~/.claude/settings.json` is included and tested.
- [ ] Cross-reference from `README.md`'s v4 headline updated to mention the walkthrough (replacing today's "30-minute tour" framing).

## Related

- [IDEA-003 — version-tag automation](./IDEA-003-version-tag-automation.md): just touched ONBOARDING at v4.0.3; this IDEA does the larger restructure on top.
- [PR #120 — WSL2 installer](https://github.com/infohata/mind-vault/pull/120): the Windows-host primer that started the "adopter onboarding" thread.
- [PR #118 — v4 multi-engine review](https://github.com/infohata/mind-vault/pull/118): the v4 OSS-release candidate that motivates the bigger walkthrough.
- The user's global `~/.claude/CLAUDE.md` — source-of-truth for the "productive defaults" the new ONBOARDING should surface.

## Open questions for `/plan`

- Should the walkthrough split into per-OS branches (Linux / macOS / Windows-via-WSL) or stay OS-agnostic with per-OS callouts? The latter is shorter but harder for a Windows-only adopter to read straight-through.
- Settings snippet: how much of Kestas's personal `~/.claude/settings.json` should be canonical vs labelled "user preference"? Risk of over-prescribing.
- Plugin recommendations have version drift — should we lock the recommended set to "v4.0.x" with an update cadence, or describe the *principles* (foundational vs sprint-orchestration vs author-tools) and leave specific names current?
