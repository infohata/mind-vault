# mind-vault

AI agent configuration, skills, and rules for Claude Code and OpenCode.

## Structure

- **`skills/`** - Reusable agent skills (SKILL.md files)
  - Discoverable by OpenCode and Claude Code
  - Loaded on-demand, zero context overhead
  - Project-specific and global patterns

- **`agents/`** - Custom agent definitions
  - Agent configuration and specialization
  - Project-specific agent rules

- **`rules/`** - Shared behavioral rules
  - Coding conventions
  - Architecture patterns
  - Best practices

## Symlinks

From `~/.claude/` and `~/.config/opencode/`:
```bash
# Skills (both Claude Code and OpenCode)
ln -s ~/projects/mind-vault/skills ~/.claude/skills
ln -s ~/projects/mind-vault/skills ~/.config/opencode/skills

# OpenCode-specific integration
ln -s ~/projects/mind-vault/agents ~/.config/opencode/agents
ln -s ~/projects/mind-vault/commands ~/.config/opencode/commands
ln -s ~/projects/mind-vault/rules ~/.config/opencode/rules
```

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

In OpenCode or Claude Code, reference skills by name:
- Ask: "Load the django-orm skill"
- Or implicitly: OpenCode will find relevant skills

## Version Control

Commit all non-sensitive configuration to git.

⚠️ **Never commit**: API keys, credentials, passwords, tokens
✅ **Do commit**: Skills, agent rules, coding conventions, patterns
