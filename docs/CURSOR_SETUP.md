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

## Quick setup (subagents only)

If skills are already set up via `~/.claude/skills` → mind-vault, you only need to symlink agents for Cursor subagents:

```bash
MV=~/projects/mind-vault

# Subagents: Cursor discovers from ~/.cursor/agents/
ln -sf "$MV/agents" ~/.cursor/agents
```

If you prefer Cursor’s own path for skills as well (or don’t use Claude Code), you can also add:

```bash
ln -sf "$MV/skills" ~/.cursor/skills
```

Restart Cursor (or reload window) so it rescans. Skills appear under **Cursor Settings → Rules** in the “Agent Decides” section; subagents are available to Agent when delegating.

## Paths Cursor uses

| Content   | Project-level         | User-level            | Notes |
|----------|------------------------|------------------------|--------|
| Skills   | `.cursor/skills/` or `.claude/skills/` | `~/.claude/skills/` or `~/.cursor/skills/` | Skills: same symlink as Claude Code is enough at user level. |
| Subagents| `.cursor/agents/`     | `~/.cursor/agents/`   | **Project**: mind-vault has `.cursor/agents` → `agents/` so opening the repo discovers subagents. **User**: symlink `~/.cursor/agents` → mind-vault for other projects. |

**Why subagents didn’t show from project:** Cursor discovers subagents from **project** `.cursor/agents/` first. mind-vault now includes `.cursor/agents` (symlink to `agents/`), so when you open mind-vault, Cursor finds architect, backend, curator, etc. User-level `~/.cursor/agents` is for when you’re in a different project and still want mind-vault subagents.

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
2. **Subagents**: In Agent chat, when the agent delegates, custom subagents should be available. In mind-vault they come from project `.cursor/agents/` (symlink to `agents/`); in other projects they come from user `~/.cursor/agents` if symlinked.  
3. **Single source**: Edit a skill or agent in `~/projects/mind-vault`; after Cursor rescans, the change is reflected without copying.

## References

- [Cursor: Agent Skills](https://cursor.com/docs/context/skills)  
- [Cursor: Subagents](https://cursor.com/docs/context/subagents)  
- [Symlinks bug (skills)](https://forum.cursor.com/t/cursor-doesnt-follow-symlinks-to-discover-skills/149693)  
- [mind-vault README](../README.md) – overall symlink layout for Claude / OpenCode / Cursor
