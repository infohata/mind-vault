# mind-vault Documentation

This directory contains analysis, specifications, and guides for the mind-vault project.

---

## OpenCode Skills Analysis (2026-01-28)

Comprehensive analysis of OpenCode's skill system for cross-platform compatibility.

### Documents

#### 1. [OPENCODE_ANALYSIS_SUMMARY.md](OPENCODE_ANALYSIS_SUMMARY.md)
**Executive summary** - Start here for overview

- Key findings and recommendations
- Implementation roadmap
- Quick reference guide
- Validation checklist

**Use for**: Strategic planning, quick reference, communicating findings

---

#### 2. [OPENCODE_SKILL_SPECIFICATIONS.md](OPENCODE_SKILL_SPECIFICATIONS.md)
**Technical specifications** - Comprehensive reference

- File structure and discovery
- Frontmatter specification (required/optional fields)
- Name validation rules (regex, constraints)
- On-demand loading mechanism
- Permission system (allow/deny/ask)
- Integration with OpenCode ecosystem
- Troubleshooting guide
- Comparison with Claude Code

**Use for**: Understanding OpenCode skill system in depth, validating skills against specifications

---

#### 3. [OPENCODE_VS_CLAUDE_SKILLS.md](OPENCODE_VS_CLAUDE_SKILLS.md)
**Cross-platform comparison** - Compatibility guide

- Core architecture differences (on-demand vs preloading)
- Naming and validation comparison
- Frontmatter differences
- Permission systems
- Content structure
- Loading and invocation
- Migration strategies (Claude Code ↔ OpenCode)
- Dual compatibility best practices

**Use for**: Maintaining compatibility with both platforms, migration planning

---

#### 4. [OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md](OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md)
**Practical guide** - Day-to-day reference

- Quick start (5 steps to create a skill)
- Naming guidelines and examples
- Directory structure requirements
- Frontmatter templates
- Content structure templates
- Code example standards
- Validation and testing procedures
- Common patterns (Django, async, testing)
- Troubleshooting

**Use for**: Creating new skills, reference during development, onboarding contributors

---

### Quick Navigation

**I want to...**

- **Understand OpenCode skills** → Start with [OPENCODE_ANALYSIS_SUMMARY.md](OPENCODE_ANALYSIS_SUMMARY.md)
- **Create a new skill** → Use [OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md](OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md)
- **Validate a skill** → Check [OPENCODE_SKILL_SPECIFICATIONS.md](OPENCODE_SKILL_SPECIFICATIONS.md)
- **Ensure compatibility** → Read [OPENCODE_VS_CLAUDE_SKILLS.md](OPENCODE_VS_CLAUDE_SKILLS.md)
- **Migrate from Claude Code** → See migration section in [OPENCODE_VS_CLAUDE_SKILLS.md](OPENCODE_VS_CLAUDE_SKILLS.md)

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

## Document Status

| Document | Status | Last Updated |
|----------|--------|--------------|
| OPENCODE_ANALYSIS_SUMMARY.md | ✅ Ready | 2026-01-28 |
| OPENCODE_SKILL_SPECIFICATIONS.md | ✅ Ready | 2026-01-28 |
| OPENCODE_VS_CLAUDE_SKILLS.md | ✅ Ready | 2026-01-28 |
| OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md | ✅ Ready | 2026-01-28 |

---

**Last Updated**: 2026-01-28  
**Maintained By**: mind-vault project
