---
id: "017"
title: mind-vault as a Claude Code plugin
status: complete   # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by:
depends_on: []       # list of IDEA ids required before starting, or []
related: ["016"]             # list of IDEA ids that share context, or []
created: 2026-06-06
completed: 2026-06-08
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Large unknowns — plugin manifest shape, marketplace vs local-install, and whether the symlink-from-working-tree dev loop survives plugin packaging. These are design decisions a human must own; not an unattended-overnight task."                     # why safe, or what blocks — 1-2 sentences
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Touches the distribution/installation substrate for every host (Claude Code, Cursor, OpenCode, etc.) — a regression here makes skills/commands/agents invisible across machines. Human-verified rollout required."       # any auth/permission/schema/infra touch? — 1-2 sentences
---

# IDEA-017: mind-vault as a Claude Code plugin

**Status**: ✅ Complete (2026-06-08) — shipped in PR #190 (plan: `2026-06-07-mind-vault-cc-plugin-plan.md`)
**Priority**: Medium

**Problem** (or opportunity): mind-vault is distributed into agent hosts by a fleet of per-host symlink scripts (`scripts/setup-{claude-code,cursor,opencode,vscode-copilot,antigravity}-symlinks.sh` + `_symlink-lib.sh`). The mechanism works but carries a recurring tax:

- **Per-machine, manual.** Each host needs `setup-<host>-symlinks.sh` re-run after cloning, and again whenever a new skill/command/agent is added (the `/land` skill went dark this way — added but the symlink script wasn't re-run).
- **Per-skill symlinks** (deliberate, to dodge a host discovery bug) mean the install surface grows with every skill.
- **Five host variants** to keep in sync as each tool's config conventions drift.

Claude Code now ships a **native plugin system** — skills + commands + agents + hooks bundled under a manifest, installed via the plugin marketplace or `/plugin`. That is the *intended* distribution mechanism for exactly what mind-vault is.

**Proposal** (or idea): Make mind-vault installable as a first-class Claude Code plugin, so a single `/plugin install` (or marketplace add) replaces the manual symlink dance for the Claude Code host. `/plan` must resolve the unknowns before committing:

- **Plugin manifest shape** — what the CC plugin format requires (manifest schema, dir layout, how skills/commands/agents/hooks are declared) and how far mind-vault's current `skills/` `commands/` `agents/` `rules/` layout already matches it.
- **Dev-loop survival** — today edits in the working tree are live via symlink (single source of truth). Does plugin packaging preserve a working-tree dev loop, or does it force a build/publish step between edit and effect? If the latter, that's a real ergonomic regression to weigh.
- **Marketplace vs local-install** — private repo (mind-vault is private); is a local/path install viable without publishing to a public marketplace?
- **rules/ handling** — CC doesn't natively discover `rules/` (today surfaced via `~/.claude/CLAUDE.md` references); does the plugin format have a home for them, or do they stay out-of-band?
- **Non-CC hosts** — Cursor/OpenCode/etc. have no equivalent plugin system, so their `setup-*-symlinks.sh` stay. Plugin-compat narrows but does not eliminate the symlink fleet.

**First `/plan` step — external research (do this before scoping anything).** Dispatch `mv-researcher` (the web-enabled persona) to:

1. **Official Claude Code plugin docs** — pin the *exact* current format: manifest schema (filename, required keys), expected dir layout, and how skills / commands / agents / hooks are each declared and discovered. Don't infer the schema from memory — the format is young and moving; read the live docs.
2. **Anthropic's own plugins as worked examples** — the `superpowers` plugin is already installed locally at `~/.claude/plugins/cache/claude-plugins-official/superpowers/` (read its manifest + layout directly), and survey the public claude-plugins marketplace repo for best-practice conventions (versioning, marketplace metadata, multi-skill bundling). Extract what a mature plugin actually does, then map each finding back onto mind-vault's current `skills/`+`commands/`+`agents/`+`rules/` layout to size the gap.

The research output (manifest schema + a layout-delta table) is the input the rest of the plan's decisions depend on.

**Why now**:

- Distribution friction compounds with every skill added; the 5.x effort (IDEA-009, IDEA-014) adds more skills + reviewer personas, raising the per-host symlink tax.
- This is the **long-term supersede** for the [IDEA-016](IDEA-016-reorganize-scripts-tools-by-concern.md) config-wiring concern — if the Claude Code host moves to a plugin, the `setup-claude-code-symlinks.sh` portion of that concern dissolves. `/plan` on 016 should know 017 exists before investing in re-partitioning the symlink scripts.

**Non-goals**:

- Not removing the symlink scripts — they remain the install path for non-CC hosts and as a fallback.
- Not a rewrite of skills/commands/agents content — purely a packaging/distribution layer over the existing artifacts.
- Not publishing to a public marketplace (mind-vault is private) unless `/plan` finds a private-distribution path that needs it.

**Related**: [IDEA-016](IDEA-016-reorganize-scripts-tools-by-concern.md) (scripts/tools taxonomy — plugin-compat may dissolve its config-wiring concern). Both surfaced 2026-06-06 while auditing the install-script story behind the 5.x runway (IDEA-009 #164 / IDEA-014 #178).
