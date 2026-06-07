# Mind-Vault Scripts — host config-wiring

One concern: **wire mind-vault into each agent host.** These scripts create the
per-host symlinks that make mind-vault's `skills/`, `commands/`, `agents/`, and
`rules/` discoverable by Claude Code, Cursor, OpenCode, VS Code Copilot, and
Antigravity — without copying anything, so a single edit in mind-vault propagates
to every host.

This dir does **not** provision machines (that's [`../install/`](../install/README.md))
and does **not** hold scripts that skills invoke at runtime (that's
[`../tools/`](../tools/README.md)).

## Available wiring scripts

| Script | Wires into |
| --- | --- |
| `setup-claude-code-symlinks.sh` | `~/.claude/` (skills, commands, agents, rules, docs/rules, statusline) |
| `setup-cursor-symlinks.sh` | Cursor's host config dir |
| `setup-opencode-symlinks.sh` | OpenCode's host config dir |
| `setup-vscode-copilot-symlinks.sh` | VS Code Copilot's host config dir |
| `setup-antigravity-symlinks.sh` | Antigravity's host config dir |
| `_symlink-lib.sh` | shared helper sourced by every `setup-*` script (not run directly) |

**Usage** (run once per host; safe to re-run, all links are idempotent):

```bash
# From repo root — wire Claude Code
./scripts/setup-claude-code-symlinks.sh

# Override the mind-vault location if it isn't at ~/projects/mind-vault
MIND_VAULT=/opt/mind-vault ./scripts/setup-cursor-symlinks.sh
```

## `_symlink-lib.sh` — the shared helper

Every `setup-*-symlinks.sh` sources `_symlink-lib.sh`, which exports the host-agnostic
primitives (`mv_resolve_root`, `mv_link_skills_per_dir`, `mv_link_tree`,
`mv_link_files_renamed`). Edit linking behaviour once, here — not in five copies.

**Why per-skill symlinks, not a single parent-dir symlink**: `mv_link_skills_per_dir`
links each skill directory **individually** (`~/.claude/skills/<skill> -> mind-vault/skills/<skill>`)
rather than `~/.claude/skills -> mind-vault/skills`. A parent-dir symlink broke
host discovery — some hosts failed to enumerate the individual skill dirs through
the parent link. Linking each skill directly is the safe form across Claude Code,
Cursor, and OpenCode. Don't "simplify" it back to one symlink.

## Why this dir is still named `scripts/` (IDEA-017 deferral)

After IDEA-016's re-partition, `scripts/` holds **only** config-wiring — so the
generic name is, for now, a deliberate misnomer pending a plugin decision.

A research spike for [IDEA-017](../docs/ideas/IDEA-017-mind-vault-as-claude-code-plugin.md)
(mind-vault as a Claude Code plugin) confirmed the rename must wait: **the CC plugin
format only PARTIALLY dissolves `setup-claude-code-symlinks.sh`.** The plugin
absorbs the `skills/` / `commands/` / `agents/` thirds, but `rules/`, `docs/rules/`,
and the statusline + `settings.json` wiring have **no plugin home** — so a residual
Claude Code symlink script survives regardless. Renaming `scripts/` → `link/` (and
`setup-*-symlinks.sh` → `link-*.sh`) now would just be churn IDEA-017 might redo.

The rename is therefore **deferred to IDEA-017**. Until that decision lands, the dir
keeps the name `scripts/` and the files keep the `setup-*-symlinks.sh` naming.

---

**Scripts Directory**: `mind-vault/scripts/`
