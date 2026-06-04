# Cursor Integration (mind-vault)

**Purpose**: Use mind-vault skills and subagents in Cursor at user level via symlinks (single source of truth).  
**Requires**: Cursor 2.4+ (skills and subagents support).  
**Applies to**: User-level config under `~/.cursor/`.

## Skills: Cursor uses Claude’s setup

Cursor 2.4+ loads user-level skills from **both** `~/.cursor/skills/` and `~/.claude/skills/` (Claude compatibility). So if you already have:

```bash
ln -s ~/projects/mind-vault/skills ~/.claude/skills
```

for Claude Code, **Cursor discovers the same skills from that symlink**. You do not need `~/.cursor/skills` for skills—one symlink serves both tools. Only subagents require a Cursor-specific symlink (see below).

## Quick setup (all-in-one)

Run `./scripts/setup-cursor-symlinks.sh` to create all symlinks (skills, commands, agents, rules). Or manually:

```bash
MV=~/projects/mind-vault

mkdir -p ~/.cursor/skills && for d in "$MV"/skills/*/; do ln -sf "$(cd "$d" && pwd)" ~/.cursor/skills/$(basename "$d"); done
ln -sf "$MV/commands" ~/.cursor/commands
ln -sf "$MV/agents" ~/.cursor/agents
ln -sf "$MV/rules" ~/.cursor/rules
```

Restart Cursor (Cmd+Shift+P → Developer: Reload Window) to rescan.

## Paths Cursor uses

| Content   | Project-level         | User-level            | Notes |
|----------|------------------------|------------------------|--------|
| Skills   | `.cursor/skills/` or `.claude/skills/` | `~/.cursor/skills/*` or `~/.claude/skills/` | Use per-skill symlinks in `~/.cursor/skills/` to avoid discovery bug. |
| Commands | `.cursor/commands/`    | `~/.cursor/commands/` | Slash commands (e.g. `/load-rules`, `/create-pr`). |
| Subagents| `.cursor/agents/`     | `~/.cursor/agents/`   | **Project**: mind-vault has `.cursor/agents` → `agents/`. **User**: symlink → mind-vault for other projects. |
| Rules    | `.cursor/rules/`      | Cursor Settings       | User Rules are in app; `~/.cursor/rules` is reference only. |

**Why subagents didn’t show from project:** Cursor discovers subagents from **project** `.cursor/agents/` first. mind-vault now includes `.cursor/agents` (symlink to `agents/`), so when you open mind-vault, Cursor finds `mv-architect`, `mv-backend`, `mv-curator`, etc. (each `agents/AGENT_*.md` profile carries an explicit `name: mv-<persona>` in frontmatter — Cursor reads that `name`, falling back to the filename). User-level `~/.cursor/agents` is for when you’re in a different project and still want mind-vault subagents.

Because every profile uses `model: inherit`, **the same file works unchanged in both Claude Code and Cursor** — no fork needed. OpenCode and Antigravity need a translation step; see [`AGENT_PORTABILITY.md`](AGENT_PORTABILITY.md) for the cross-harness compatibility matrix and fork recipes.

## If skills are not discovered (symlink caveat)

Cursor has a [known issue](https://forum.cursor.com/t/cursor-doesnt-follow-symlinks-to-discover-skills/149693): it may not discover skills when the **parent** directory is a symlink (e.g. `~/.cursor/skills` → mind-vault). A workaround is to use a real directory and symlink each skill:

```bash
MV=~/projects/mind-vault
mkdir -p ~/.cursor/skills
for d in "$MV"/skills/*/; do
  name=$(basename "$d")
  ln -sf "$(realpath "$d")" ~/.cursor/skills/"$name"
done
```

Then keep `~/.cursor/agents` as a single symlink to `"$MV/agents"` if you want (subagent symlink behavior may differ). Re-run the loop after adding new skills in mind-vault.

## Rules

Cursor’s **User Rules** are configured in the app (Cursor Settings → Rules), not via a directory. To reuse mind-vault rules (e.g. git-safety) in Cursor you can:

- Copy or reference their content into User Rules, or  
- In a project that uses mind-vault, use project rules (e.g. `.cursor/rules/`) or `AGENTS.md` and point to the same conventions.

## Verify

1. **Skills**: Cursor Settings → Rules → Agent Decides. You should see mind-vault skills (e.g. django, deployment).  
2. **Commands**: Type `/` in Agent chat; you should see load-rules, create-pr, commit, etc.  
3. **Subagents**: In Agent chat, when the agent delegates, custom subagents should be available. In mind-vault they come from project `.cursor/agents/`; in other projects from user `~/.cursor/agents` if symlinked.  
4. **Single source**: Edit a skill or agent in `~/projects/mind-vault`; after Cursor rescans, the change is reflected without copying.

## References

- [Cursor: Agent Skills](https://cursor.com/docs/context/skills)  
- [Cursor: Subagents](https://cursor.com/docs/context/subagents)  
- [Symlinks bug (skills)](https://forum.cursor.com/t/cursor-doesnt-follow-symlinks-to-discover-skills/149693)  
- [mind-vault README](../../README.md) – overall symlink layout for Claude / OpenCode / Cursor
