# mind-vault

AI agent configuration, skills, and rules for Claude Code, OpenCode, and Cursor.

## Structure

- **`skills/`** - Reusable agent skills (SKILL.md files)
  - Discoverable by OpenCode, Claude Code, and Cursor (2.4+)
  - Loaded on-demand, zero context overhead
  - Project-specific and global patterns

- **`agents/`** - Custom agent definitions (subagents)
  - Agent configuration and specialization
  - Used by OpenCode and Cursor (2.4+)

- **`rules/`** - Shared behavioral rules
  - Coding conventions
  - Architecture patterns
  - Best practices

## Symlinks (single source of truth)

User-level symlinks keep one copy in mind-vault; all tools point to it.

**Skills (shared by Claude Code and Cursor):**  
Cursor 2.4+ loads user-level skills from both `~/.cursor/skills/` and `~/.claude/skills/` (Claude compatibility). A single symlink to `~/.claude/skills` therefore serves **both** Claude Code and Cursor—no need for `~/.cursor/skills` unless you want Cursor’s path explicit.

```bash
# Skills: Claude Code and Cursor both read ~/.claude/skills
ln -s ~/projects/mind-vault/skills ~/.claude/skills
ln -s ~/projects/mind-vault/skills ~/.config/opencode/skills

# OpenCode-specific
ln -s ~/projects/mind-vault/agents ~/.config/opencode/agents
ln -s ~/projects/mind-vault/commands ~/.config/opencode/commands
ln -s ~/projects/mind-vault/rules ~/.config/opencode/rules
```

**Cursor (2.4+)** – full setup (skills, commands, agents, rules):
```bash
./scripts/setup-cursor-symlinks.sh
```

Or manually: `~/.cursor/agents`, `~/.cursor/commands`, `~/.cursor/skills/*`, `~/.cursor/rules` → mind-vault. See [Cursor setup](docs/CURSOR_SETUP.md).

## OpenCode Configuration

Add to `~/.config/opencode/opencode.jsonc`:
```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["rules/RULE_*.md"],
  "mcp": {
    "browsermcp": {
      "type": "local", 
      "command": ["${HOME}/.local/bin/browsermcp-start"],
      "enabled": true
    }
  }
}
```

This enables:
- **Automatic rule loading** on session start
- **Agent specialization** via symlinked agents
- **Custom commands** like `/load-rules` for rule recovery
- **MCP server integration** for browser automation

## Usage

In OpenCode, Claude Code, or Cursor, reference skills by name:
- Ask: "Load the django skill" or "Load the django-frontend skill"
- Or use `/skill-name` in Cursor Agent chat
- OpenCode and Cursor will apply skills when relevant

Skills available include:
- **django** - Core Django patterns (ORM, views, forms, multi-tenancy)
- **django-frontend** - HTMX + Alpine.js + Bulma frontend architecture
- **deployment** - Docker Compose deployment with monitoring and Django extensions
- **django-celery** - Background task patterns with Celery
- **django-async-websocket** - Real-time WebSocket communication
- And more in the `skills/` directory

## For Developers

Creating new skills? See the comprehensive guide:
- **[Skill Development Guide](docs/SKILL_SPECIFICATION.md)** - OpenCode skill specifications, validation, and best practices

## Version Control

Commit all non-sensitive configuration to git.

⚠️ **Never commit**: API keys, credentials, passwords, tokens
✅ **Do commit**: Skills, agent rules, coding conventions, patterns
