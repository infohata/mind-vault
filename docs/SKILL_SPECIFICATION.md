# OpenCode Skill Specifications

**Purpose**: Comprehensive guide for creating OpenCode-compatible skills
**Date**: 2026-01-28
**Status**: Ready
**Applies To**: mind-vault skill development and validation
**Source**: https://opencode.ai/docs/skills/

---

## Executive Summary

OpenCode uses a **directory-based skill system** with **on-demand loading** and **strict validation**. Skills are stored as `skills/<name>/SKILL.md` files with YAML frontmatter. Agents discover available skills via the `skill` tool and load them explicitly when needed.

**Key Requirements for mind-vault**:
- **Strict naming**: `^[a-z0-9]+(-[a-z0-9]+)*$` (lowercase, single hyphens)
- **Directory structure**: `skills/<name>/SKILL.md` (required)
- **Frontmatter**: `name` and `description` fields mandatory
- **On-demand loading**: Skills appear in tool descriptions, loaded via `skill({ name: "..." })`

---

## 1. File Structure & Discovery

### Directory Structure (Required)
```
skills/
├── skill-name/
│   └── SKILL.md          # Required, exact case
├── another-skill/
│   └── SKILL.md
└── third-skill/
    └── SKILL.md
```

**Requirements**:
- Each skill in its own directory
- Directory name must match frontmatter `name`
- File named `SKILL.md` (all caps)
- One `SKILL.md` per directory

### Discovery Locations
OpenCode searches these locations in order:
1. **Project-local**: `.opencode/skills/<name>/SKILL.md` (walks up from current directory)
2. **User-global**: `~/.opencode/skills/<name>/SKILL.md`
3. **System-global**: `/usr/local/share/opencode/skills/<name>/SKILL.md`

### Frontmatter Format
```yaml
---
name: skill-name
description: Brief description (1-1024 characters)
---
```

**Validation Rules**:
- `name`: Required, matches directory name, format: `^[a-z0-9]+(-[a-z0-9]+)*$`
- `description`: Required, 1-1024 characters, no newlines
- Other fields: Ignored (OpenCode only recognizes `name` and `description`)

---

## 2. Skill Loading & Usage

### On-Demand Loading
Skills appear in the `skill` tool description:
```javascript
<available_skills>
  <skill>
    <name>django</name>
    <description>Django patterns for web development</description>
  </skill>
</available_skills>
```

Agents load skills explicitly:
```javascript
skill({ name: "django" })
```

### Cross-Platform Compatibility
| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| Loading | On-demand via `skill` tool | Session start |
| Naming | Strict: lowercase + hyphens only | Flexible |
| Structure | Directory required | File or directory |
| Frontmatter | Required fields only | Often optional |
| Validation | Strict enforcement | More lenient |

**Recommendation**: Use OpenCode requirements for maximum compatibility.

---

## 3. Creating Skills

### Quick Start (5 Steps)

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

4. **Write content** with standard sections:
   ```markdown
   ## Overview
   What this skill does and when to use it.

   ## Examples
   Code examples and patterns.

   ## References
   Related documentation.
   ```

5. **Validate**:
   ```bash
   ./tools/validate-skills.sh your-skill-name
   ```

### Naming Rules

**Format**: `^[a-z0-9]+(-[a-z0-9]+)*$`
- Lowercase letters and numbers only
- Single hyphens as separators
- Cannot start/end with hyphen
- No consecutive hyphens

**Examples**:
- ✅ `django-architecture`
- ✅ `error-handling`
- ❌ `Django-Architecture` (uppercase)
- ❌ `error__handling` (double underscore)

### Description Best Practices

- **Length**: 20-200 characters (recommended)
- **Content**: Action-oriented, specific
- **Format**: Complete sentence preferred

**Examples**:
- ✅ "Django patterns for building scalable web applications with multi-tenant support"
- ❌ "Django stuff"

---

## 4. Validation & Testing

### Automated Validation
Use the provided validation script:
```bash
# Validate single skill
./tools/validate-skills.sh skill-name

# Validate all skills
./tools/validate-skills.sh --all
```

**Checks performed**:
- Directory structure
- File naming (`SKILL.md`)
- Frontmatter presence and format
- Name format validation
- Description length and content
- Recommended sections

### Common Issues & Fixes

| Issue | Symptom | Fix |
|-------|---------|-----|
| Name mismatch | "Frontmatter 'name' doesn't match directory name" | Update frontmatter or rename directory |
| Invalid format | "Invalid name format" | Use lowercase + single hyphens only |
| Missing frontmatter | "Missing YAML frontmatter" | Add `---` markers and required fields |
| Empty description | "Description is empty" | Add meaningful description |

---

## 5. Integration Patterns

### Skill Content Organization

**Standard sections** (recommended):
```markdown
## Overview
What the skill does and when to use it.

## When to Use
Specific scenarios and use cases.

## Pattern
Technical implementation details.

## Examples
Code samples and real-world usage.

## Why It's Generic
Why this applies beyond one project.

## References
Links to related documentation.
```

### Cross-Skill References

Link between related skills:
```markdown
## Related Skills
- [django-multi-tenant](../django-multi-tenant/SKILL.md) - Multi-tenant architecture
- [django-async-websocket](../django-async-websocket/SKILL.md) - Real-time features
```

### Version Control

- Store skills in version control
- Use semantic commit messages
- Tag releases for stability
- Document breaking changes

---

## 6. Advanced Features

### Permission-Based Access

OpenCode supports pattern-based permissions:
- `allow`: Always allow access
- `deny`: Never allow access
- `ask`: Prompt user for confirmation

### Skill Dependencies

Skills can reference each other:
- Use relative links: `../other-skill/SKILL.md`
- Document prerequisites
- Suggest related skills

### Performance Considerations

- Keep skill files focused (< 500 lines)
- Use clear section headers
- Include working code examples
- Link to external resources when appropriate

---

## 7. Migration from Claude Code

### Key Changes Required

1. **Directory structure**: Convert single files to directories
2. **Naming**: Ensure lowercase + hyphens only
3. **Frontmatter**: Add required fields, remove unsupported ones
4. **Loading**: Update documentation to mention on-demand loading

### Compatibility Testing

Test skills on both platforms:
- OpenCode: Use `skill` tool to load
- Claude Code: Verify session loading
- Cross-platform: Ensure no platform-specific content

---

## Summary

OpenCode skills require **strict formatting** but provide **excellent scalability**. Design for OpenCode's requirements to ensure compatibility with both platforms. Use the validation tools and follow the implementation guide for reliable skill development.

**Essential checklist**:
- [ ] Directory: `skills/<name>/SKILL.md`
- [ ] Name format: lowercase + single hyphens
- [ ] Frontmatter: `name` and `description` fields
- [ ] Validation: passes `./tools/validate-skills.sh`
- [ ] Content: clear, actionable, generic patterns</content>
<parameter name="filePath">docs/SKILL_SPECIFICATION.md