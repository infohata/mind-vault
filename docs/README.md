# mind-vault Documentation

This directory contains analysis, specifications, and guides for the mind-vault project.

---

## Skill Specifications

### [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md)
**Comprehensive guide** for creating OpenCode-compatible skills

- File structure and discovery requirements
- Naming rules and validation
- Frontmatter specifications
- On-demand loading patterns
- Cross-platform compatibility (OpenCode + Claude Code)
- Creation workflow and best practices
- Integration patterns and troubleshooting

**Use for**: Creating skills, validation reference, migration guide

---

### [CURSOR_SETUP.md](CURSOR_SETUP.md)
**Cursor 2.4+ integration** with mind-vault at user level

- Cursor loads skills from `~/.claude/skills/` (Claude compatibility)—one symlink serves Claude Code and Cursor
- Subagents: `~/.cursor/agents` → mind-vault
- Known symlink caveat and per-skill workaround

**Use for**: Setting up Cursor to use mind-vault skills and subagents

---

## Archived Research

Research documents have been consolidated and archived for reference:

- **OpenCode Analysis**: `docs/archive/opencode-research/` (4 consolidated into SKILL_SPECIFICATION.md)
- **Session Notes**: `docs/archive/session-notes/` (historical development records)

---

## Tools

### Skill Validation Script

**Location**: `tools/validate-skills.sh`

**Usage**:
```bash
# Validate single skill
./tools/validate-skills.sh django-multi-tenant

# Validate all skills
./tools/validate-skills.sh --all
```

**Checks**:
- Name format (regex validation)
- Directory structure
- Frontmatter completeness
- Description length
- Common issues (TODO, FIXME)
- Recommended sections

---

## Key Specifications

### Name Format
```regex
^[a-z0-9]+(-[a-z0-9]+)*$
```

**Requirements**:
- Lowercase letters only (a-z)
- Numbers allowed (0-9)
- Single hyphens as separators
- Cannot start or end with hyphen
- No consecutive hyphens
- 1-64 characters

**Examples**:
```
✅ django-multi-tenant
✅ error-handling-async
✅ git-workflow

❌ Django-MultiTenant (uppercase)
❌ error_handling_async (underscore)
❌ git--workflow (double hyphen)
```

### Directory Structure
```
skills/
└── skill-name/          # Must match frontmatter 'name'
    └── SKILL.md         # Exact case required
```

### Minimal Frontmatter
```yaml
---
name: skill-name
description: Brief, specific description (1-1024 chars)
---
```

### Recommended Frontmatter
```yaml
---
name: skill-name
description: Brief, specific description
license: MIT
compatibility: opencode, claude
metadata:
  category: domain
  complexity: intermediate
  version: "1.0"
---
```

---

## Quick Start: Creating a Skill

### 5-Step Process

1. **Create directory**:
   ```bash
   mkdir -p skills/your-skill-name
   ```

2. **Create SKILL.md**:
   ```bash
   touch skills/your-skill-name/SKILL.md
   ```

3. **Add frontmatter**:
   ```yaml
   ---
   name: your-skill-name
   description: Brief, specific description
   ---
   ```

4. **Write content**:
   ```markdown
   ## Overview
   [Your skill content]
   
   ## When to Use
   [Applicability criteria]
   
   ## Core Patterns
   [Patterns with examples]
   ```

5. **Validate**:
   ```bash
   ./tools/validate-skills.sh your-skill-name
   ```

---

## Content Template

```markdown
---
name: skill-name
description: Brief, specific description
license: MIT
compatibility: opencode, claude
metadata:
  category: domain
  complexity: intermediate
---

## Overview
Brief introduction (2-3 sentences)

## When to Use
- Specific scenario 1
- Specific scenario 2

Do NOT use for:
- Scenario where not applicable

## Prerequisites
- Related skills to load
- Knowledge requirements

## Core Patterns

### Pattern 1: Name
Explanation and code example

### Pattern 2: Name
Explanation and code example

## Examples

### Example 1: Scenario
Complete, tested code example

## Common Pitfalls

### Pitfall 1: Description
Problem and solution

## Important Considerations
- Performance notes
- Security considerations
- Scalability implications

## Related Skills
- `related-skill`: Relationship description
```

---

## Validation Checklist

Before committing a skill:

- [ ] Name follows regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Name is 1-64 characters
- [ ] Directory: `skills/<name>/SKILL.md`
- [ ] File named `SKILL.md` (exact case)
- [ ] Directory name matches frontmatter `name`
- [ ] Frontmatter includes `name` and `description`
- [ ] Description is 1-1024 characters (aim for 100-200)
- [ ] Description is specific and actionable
- [ ] Content follows template structure
- [ ] Code examples are complete and tested
- [ ] Tool references are generic (not platform-specific)
- [ ] Related skills referenced appropriately
- [ ] Validation script passes: `./tools/validate-skills.sh <name>`
- [ ] Tested in OpenCode (if available)
- [ ] Permissions configured (if needed)

---

## Common Commands

```bash
# Create new skill
mkdir -p skills/skill-name
touch skills/skill-name/SKILL.md

# Validate single skill
./tools/validate-skills.sh skill-name

# Validate all skills
./tools/validate-skills.sh --all

# Test in OpenCode
opencode
# Then: skill({ name: "skill-name" })

# Check permissions (if opencode.json exists)
cat opencode.json | jq '.permission.skill'
```

---

## Resources

### External Documentation
- [OpenCode Skills](https://opencode.ai/docs/skills/)
- [OpenCode Agents](https://opencode.ai/docs/agents/)
- [OpenCode Permissions](https://opencode.ai/docs/permissions/)
- [OpenCode Tools](https://opencode.ai/docs/tools/)
- [OpenCode Commands](https://opencode.ai/docs/commands/)

### Internal Documentation
- [AGENTS.md](../AGENTS.md): Project-level rules and conventions
- [skills/](../skills/): Skill directory
- [agents/](../agents/): Custom agent definitions
- [rules/](../rules/): Behavioral rules

### Tools
- [Regex Tester](https://regex101.com/): Test skill name format
- Validation script: `tools/validate-skills.sh`

---

## Contributing

When adding new documentation:

1. **Follow naming convention**: `TOPIC_DESCRIPTION.md` or `TOPIC_DATE.md`
2. **Include metadata**: Purpose, date, status, applies to
3. **Update this README**: Add entry in appropriate section
4. **Cross-reference**: Link to related documents
5. **Keep focused**: One topic per document

---

**Last Updated**: 2026-01-28  
**Maintained By**: mind-vault project
