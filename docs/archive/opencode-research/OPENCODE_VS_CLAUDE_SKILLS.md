# OpenCode vs Claude Code: Skills Comparison

**Purpose**: Detailed comparison of skill systems for cross-platform compatibility  
**Date**: 2026-01-28  
**Status**: Ready  
**Applies To**: mind-vault cross-platform skill development

---

## Executive Summary

OpenCode and Claude Code both support skill-based agent customization, but with significant implementation differences. **OpenCode uses on-demand loading with strict validation**, while **Claude Code loads skills at session start with more flexible formatting**. This document provides a comprehensive comparison to guide cross-platform skill development.

**Key Recommendation**: Design skills for OpenCode's stricter requirements, which will ensure compatibility with both platforms.

---

## 1. Core Architecture Differences

### 1.1 Loading Strategy

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Loading time** | On-demand via `skill` tool | Session start (varies by implementation) |
| **Context impact** | Minimal until loaded | All skills in initial context |
| **Discovery** | Listed in tool description | Available from start |
| **Performance** | Scales with skill library size | May impact startup time |
| **Agent awareness** | Must explicitly load | Skills available immediately |

**OpenCode approach**:
```javascript
// Agent sees available skills
<available_skills>
  <skill>
    <name>django-patterns</name>
    <description>Multi-tenant Django patterns</description>
  </skill>
</available_skills>

// Agent loads when needed
skill({ name: "django-patterns" })
```

**Claude Code approach**:
```markdown
Skills loaded at session start:
- django-patterns: Multi-tenant Django patterns
- error-handling: Async error categorization
- git-workflow: Git conventions

[Full content available immediately]
```

**Implications**:
- OpenCode: Better for large skill libraries (100+ skills)
- Claude Code: Better for small, frequently-used skill sets
- OpenCode: Agent must know when to load skills
- Claude Code: Agent has all skills available but may be overwhelmed

### 1.2 File Structure

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Directory structure** | Required: `skills/<name>/SKILL.md` | Flexible: `skills/<name>.md` or `skills/<name>/SKILL.md` |
| **File naming** | Strict: `SKILL.md` (all caps) | Flexible: `SKILL.md`, `skill.md`, or custom |
| **Nesting** | Single level: `skills/<name>/` | Supports nested directories |
| **Multiple files** | One `SKILL.md` per directory | Can reference multiple files |

**OpenCode structure** (required):
```
skills/
├── django-patterns/
│   └── SKILL.md              # Must be exactly this
├── error-handling/
│   └── SKILL.md
└── git-workflow/
    └── SKILL.md
```

**Claude Code structure** (flexible):
```
skills/
├── django-patterns.md        # Single file works
├── error-handling/
│   ├── SKILL.md              # Or directory with SKILL.md
│   └── examples.md           # Can include supporting files
└── git/
    ├── workflow.md           # Nested structure supported
    └── release.md
```

**Compatibility strategy**: Use OpenCode structure (works in both).

### 1.3 Discovery Locations

**OpenCode search paths**:
1. `.opencode/skills/<name>/SKILL.md` (project, OpenCode-specific)
2. `.claude/skills/<name>/SKILL.md` (project, Claude Code compat)
3. `~/.config/opencode/skills/<name>/SKILL.md` (global, OpenCode)
4. `~/.claude/skills/<name>/SKILL.md` (global, Claude Code compat)

**Claude Code search paths**:
1. `.claude/skills/` (project)
2. `~/.claude/skills/` (global)
3. `~/.config/Claude/skills/` (alternative global)

**Shared locations**:
- `.claude/skills/` (both platforms)
- `~/.claude/skills/` (both platforms)

**Best practice**: Place skills in `.claude/skills/` for maximum compatibility.

---

## 2. Naming & Validation

### 2.1 Name Format

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Regex** | `^[a-z0-9]+(-[a-z0-9]+)*$` | More flexible (varies) |
| **Case** | Lowercase only | Mixed case allowed |
| **Separators** | Single hyphens only | Hyphens, underscores, spaces (varies) |
| **Length** | 1-64 characters | Less strict |
| **Validation** | Strict enforcement | Lenient |

**OpenCode valid names**:
```
django-patterns          ✅
error-handling-async     ✅
multi-tenant-2024        ✅
git-workflow             ✅
```

**OpenCode invalid names**:
```
Django-Patterns          ❌ (uppercase)
error_handling           ❌ (underscore)
error--handling          ❌ (double hyphen)
-error-handling          ❌ (leading hyphen)
error-handling-          ❌ (trailing hyphen)
error handling           ❌ (space)
```

**Claude Code typically accepts**:
```
Django-Patterns          ✅ (often works)
error_handling           ✅ (often works)
error handling           ⚠️ (may work, not recommended)
```

**Recommendation**: Use OpenCode naming (lowercase, single hyphens) for compatibility.

### 2.2 Directory Name Matching

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Match required** | Yes, directory must match `name` field | Less strict |
| **Validation** | Enforced at load time | May not validate |
| **Error handling** | Skill fails to load | May load with warning |

**OpenCode requirement**:
```
skills/
└── django-patterns/          # Directory name
    └── SKILL.md
        ---
        name: django-patterns  # Must match exactly
        ---
```

**Mismatch behavior**:
- OpenCode: Skill fails to load, error logged
- Claude Code: May load successfully, uses frontmatter name

**Best practice**: Always match directory name to frontmatter `name` field.

---

## 3. Frontmatter Specification

### 3.1 Required Fields

| Field | OpenCode | Claude Code |
|-------|----------|-------------|
| `name` | ✅ Required | ⚠️ Often optional (uses filename) |
| `description` | ✅ Required (1-1024 chars) | ⚠️ Often optional |

**OpenCode minimal frontmatter**:
```yaml
---
name: skill-name
description: Brief description of what this skill does
---
```

**Claude Code minimal frontmatter**:
```yaml
---
# Often works with no frontmatter at all
# Or minimal frontmatter
---
```

**Recommendation**: Always include `name` and `description` for compatibility.

### 3.2 Optional Fields

| Field | OpenCode | Claude Code |
|-------|----------|-------------|
| `license` | ✅ Recognized | ⚠️ May be ignored |
| `compatibility` | ✅ Recognized | ⚠️ May be ignored |
| `metadata` | ✅ String-to-string map | ⚠️ May support more types |
| Custom fields | ❌ Silently ignored | ✅ Often preserved |

**OpenCode optional fields**:
```yaml
---
name: skill-name
description: Brief description
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: github
---
```

**Claude Code may support**:
```yaml
---
name: skill-name
description: Brief description
author: John Doe
version: 1.0
tags: [django, multi-tenant]
custom_field: custom_value
---
```

**Compatibility strategy**:
- Use OpenCode-recognized fields for core metadata
- Add custom fields for Claude Code-specific features
- Document which fields are platform-specific

### 3.3 Description Guidelines

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Length** | 1-1024 characters (enforced) | Less strict |
| **Purpose** | Agent selection in tool description | Context and discovery |
| **Specificity** | Must be specific for correct selection | Can be more general |

**OpenCode description best practices**:
```yaml
# ✅ Good: Specific, actionable
description: Multi-tenant Django patterns with schema-per-tenant isolation using django-tenants

# ❌ Bad: Too vague for agent selection
description: Django patterns

# ❌ Bad: Too long (over 1024 chars)
description: This skill provides comprehensive multi-tenant Django patterns...
[500 more words]
```

**Recommendation**: Write specific, concise descriptions (under 200 chars) that work well in both platforms.

---

## 4. Permission Systems

### 4.1 OpenCode Permissions

**Granular control**:
```json
{
  "permission": {
    "skill": {
      "*": "allow",                    // Default
      "experimental-*": "ask",         // Pattern matching
      "internal-*": "deny",            // Hide from agent
      "django-patterns": "allow"       // Specific skill
    }
  }
}
```

**Three levels**:
- `allow`: Load immediately
- `ask`: Prompt user for approval
- `deny`: Hide from agent, reject access

**Pattern matching**:
- `*` matches zero or more characters
- `?` matches exactly one character
- Last matching rule wins

**Per-agent overrides**:
```json
{
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "internal-*": "allow"        // Plan can use internal skills
        }
      }
    }
  }
}
```

### 4.2 Claude Code Permissions

**Less granular** (varies by implementation):
- May not have skill-specific permissions
- Often all-or-nothing (skills enabled or disabled)
- May rely on file system permissions

**Typical approach**:
- Skills in `.claude/skills/` are loaded
- Remove skill file to disable
- No pattern-based filtering

### 4.3 Cross-Platform Permission Strategy

**For maximum compatibility**:

1. **Use OpenCode permissions for fine-grained control**
2. **Organize skills by trust level**:
   ```
   skills/
   ├── core-*/              # Always safe
   ├── experimental-*/      # Require approval
   └── internal-*/          # Restricted
   ```
3. **Document permission requirements** in skill content
4. **Test in both platforms** to verify behavior

---

## 5. Content Structure & Formatting

### 5.1 Markdown Support

| Feature | OpenCode | Claude Code |
|---------|----------|-------------|
| **Basic markdown** | ✅ Full support | ✅ Full support |
| **Code blocks** | ✅ With syntax highlighting | ✅ With syntax highlighting |
| **Tables** | ✅ Supported | ✅ Supported |
| **Links** | ✅ Relative and absolute | ✅ Relative and absolute |
| **Images** | ⚠️ Limited | ⚠️ Limited |
| **Custom HTML** | ⚠️ May be stripped | ⚠️ May be stripped |

**Both platforms support standard markdown**:
```markdown
## Section Header

### Subsection

**Bold text** and *italic text*

- Bullet lists
- Work well

1. Numbered lists
2. Also supported

```python
# Code blocks with syntax highlighting
def example():
    return "works in both"
```

| Tables | Work |
|--------|------|
| In     | Both |
```

**Recommendation**: Stick to standard markdown for compatibility.

### 5.2 Content Organization

**OpenCode recommendations**:
```markdown
## What I do
- Clear capabilities
- Specific actions

## When to use me
Scenarios and decision criteria

## How to use me
Step-by-step guidance

## Important considerations
Edge cases and pitfalls
```

**Claude Code flexibility**:
```markdown
# Any structure works
Can use any heading structure
No enforced sections
```

**Best practice**: Use clear, consistent structure that works in both:
```markdown
## Overview
Brief introduction

## When to Use
Applicability criteria

## Patterns
Core patterns with examples

## Examples
Concrete code examples

## Related
Links to related skills
```

### 5.3 Code Examples

**Both platforms support**:
- Syntax-highlighted code blocks
- Inline code
- Multi-language examples

**Best practices for both**:
```markdown
### Example: Tenant Context

```python
from django_tenants.utils import tenant_context

def get_tenant_data(tenant_id):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        return Article.objects.all()
```

**Key points**:
- Always use `tenant_context()` for database queries
- Pass `tenant_id` explicitly, never assume context
- Verify tenant membership before operations
```

---

## 6. Loading & Invocation

### 6.1 OpenCode Loading

**Explicit loading via tool**:
```javascript
// Agent invokes skill tool
skill({ name: "django-patterns" })

// Returns full skill content to context
// Agent then follows skill instructions
```

**Characteristics**:
- Agent must know when to load
- Skill content added to context on-demand
- Can load multiple skills in sequence
- Can reference loaded skills later

**Agent decision process**:
1. See task requiring Django multi-tenant work
2. Check available skills in tool description
3. Load `django-patterns` skill
4. Follow patterns from skill content
5. May load additional skills as needed

### 6.2 Claude Code Loading

**Automatic loading at session start**:
```markdown
[Session starts]
[All skills loaded into context]
[Agent has immediate access]
```

**Characteristics**:
- No explicit loading needed
- All skills available from start
- Agent doesn't need to know about loading
- May impact context size

**Agent usage**:
1. Task requires Django multi-tenant work
2. Agent already has skill content
3. Applies patterns directly
4. No loading step needed

### 6.3 Implications for Skill Design

**For OpenCode** (on-demand loading):
- Write clear descriptions for agent selection
- Make skills self-contained
- Include decision criteria ("when to use me")
- Reference related skills explicitly

**For Claude Code** (preloaded):
- Focus on clear, scannable content
- Use distinctive headings
- Avoid redundancy between skills
- Keep skills focused and concise

**Cross-platform strategy**:
- Write for OpenCode (stricter requirements)
- Ensure skills work standalone
- Include clear descriptions and decision criteria
- Test in both environments

---

## 7. Skill Composition & References

### 7.1 OpenCode Skill References

**Explicit loading of related skills**:
```markdown
## Prerequisites

Load these skills first:
- `django-architecture`: Core Django patterns
- `error-handling-async`: Async error patterns

Load them with:
skill({ name: "django-architecture" })
skill({ name: "error-handling-async" })
```

**Conditional loading**:
```markdown
## Conditional Patterns

If working with WebSockets:
- Load `django-async-websocket` skill
- Apply tenant context in consumers

If working with background tasks:
- Load `django-celery-multitenant` skill
- Pass tenant_id to all tasks
```

### 7.2 Claude Code Skill References

**Implicit references** (all loaded):
```markdown
## Related Skills

See also:
- Django Architecture patterns
- Async Error Handling patterns

These skills are already loaded and available.
```

**Cross-references**:
```markdown
## Multi-Tenant Patterns

For WebSocket patterns, refer to the "Django Async WebSocket" skill.
For background tasks, refer to the "Django Celery Multi-Tenant" skill.
```

### 7.3 Cross-Platform Reference Strategy

**Use explicit loading syntax** (works in both):
```markdown
## Prerequisites

**For OpenCode users**: Load these skills:
skill({ name: "django-architecture" })
skill({ name: "error-handling-async" })

**For Claude Code users**: These skills are already loaded.

## Related Patterns

See these related skills for additional context:
- `django-architecture`: Core Django patterns
- `error-handling-async`: Async error categorization
```

---

## 8. Tool Integration

### 8.1 OpenCode Tool References

**Skills can guide tool usage**:
```markdown
## Implementation Steps

1. **Find tenant models**:
   Use `glob` tool: glob({ pattern: "**/*tenant*.py" })

2. **Search for patterns**:
   Use `grep` tool: grep({ pattern: "TenantModel", include: "*.py" })

3. **Read files**:
   Use `read` tool on each file

4. **Make changes**:
   Use `edit` tool with exact string replacement
```

**Tool names**:
- `bash`, `edit`, `write`, `read`, `grep`, `glob`, `list`
- `skill`, `todowrite`, `todoread`, `webfetch`, `question`
- MCP tools: `mcp_<server>_<tool>`

### 8.2 Claude Code Tool References

**Similar tool references**:
```markdown
## Implementation Steps

1. **Find tenant models**:
   Use the Glob tool to search: **/*tenant*.py

2. **Search for patterns**:
   Use the Grep tool: TenantModel in *.py files

3. **Read files**:
   Use the Read tool on each file

4. **Make changes**:
   Use the Edit tool with exact string replacement
```

**Tool names** (may vary):
- Similar core tools (bash, edit, write, read, grep, glob)
- MCP tools available
- Platform-specific tools

### 8.3 Cross-Platform Tool References

**Generic approach** (works in both):
```markdown
## Implementation Steps

1. **Find tenant models**:
   Search for files matching pattern: **/*tenant*.py

2. **Search for patterns**:
   Search file contents for: TenantModel

3. **Read files**:
   Read each matching file

4. **Make changes**:
   Edit files using exact string replacement
```

**Recommendation**: Describe actions generically, let agent choose appropriate tool.

---

## 9. Testing & Validation

### 9.1 OpenCode Validation

**Automated checks**:
- Name format validation (regex)
- Frontmatter required fields
- Description length (1-1024 chars)
- Directory name matching
- File name case (`SKILL.md`)

**Testing approach**:
```bash
# Start OpenCode
opencode

# Check skill appears
# (should see in autocomplete)

# Load skill
skill({ name: "your-skill" })

# Verify content loads
# Test agent follows instructions
```

**Validation script**:
```bash
#!/bin/bash
for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"
  
  # Validate name format
  if ! echo "$skill_name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "❌ Invalid name: $skill_name"
  fi
  
  # Check file exists
  if [ ! -f "$skill_file" ]; then
    echo "❌ Missing SKILL.md in $skill_name"
  fi
  
  # Check frontmatter
  if ! grep -q "^name: $skill_name$" "$skill_file"; then
    echo "❌ Name mismatch in $skill_name"
  fi
  
  echo "✅ $skill_name validated"
done
```

### 9.2 Claude Code Validation

**Less strict validation**:
- May load skills with warnings
- More forgiving of format issues
- Relies on content quality

**Testing approach**:
```bash
# Start Claude Code session
# Skills should load automatically

# Verify skill content available
# Test agent can use skill patterns
```

### 9.3 Cross-Platform Testing

**Test in both environments**:
1. Validate against OpenCode requirements (stricter)
2. Test loading in OpenCode
3. Test loading in Claude Code
4. Verify agent behavior in both
5. Check permission handling in both

**Compatibility checklist**:
- [ ] Name follows OpenCode regex
- [ ] Directory structure matches OpenCode requirements
- [ ] Frontmatter includes required fields
- [ ] Description is specific and concise
- [ ] Content uses standard markdown
- [ ] Code examples are syntactically correct
- [ ] Tool references are generic
- [ ] Skill loads successfully in OpenCode
- [ ] Skill loads successfully in Claude Code
- [ ] Agent follows patterns correctly in both

---

## 10. Migration Strategies

### 10.1 Claude Code to OpenCode

**Steps**:
1. **Validate names**: Check all skill names against OpenCode regex
2. **Restructure directories**: Ensure each skill in own folder
3. **Add frontmatter**: Ensure `name` and `description` present
4. **Update file names**: Rename to `SKILL.md` (caps)
5. **Configure permissions**: Set up permission rules in `opencode.json`
6. **Test loading**: Verify skills load on-demand
7. **Update documentation**: Note on-demand loading behavior

**Example migration**:
```bash
# Before (Claude Code)
skills/
├── django-patterns.md
├── error-handling.md
└── git-workflow.md

# After (OpenCode compatible)
skills/
├── django-patterns/
│   └── SKILL.md
├── error-handling/
│   └── SKILL.md
└── git-workflow/
    └── SKILL.md
```

**Frontmatter updates**:
```yaml
# Before (Claude Code)
---
# Minimal or no frontmatter
---

# After (OpenCode compatible)
---
name: django-patterns
description: Multi-tenant Django patterns with schema-per-tenant isolation
---
```

### 10.2 OpenCode to Claude Code

**Steps**:
1. **Verify structure**: OpenCode structure works in Claude Code
2. **Test loading**: Ensure skills load at session start
3. **Optimize content**: May want to consolidate skills (all loaded)
4. **Remove OpenCode-specific references**: Tool loading syntax, etc.
5. **Test agent behavior**: Verify patterns work without explicit loading

**Considerations**:
- OpenCode skills work in Claude Code (stricter → lenient)
- May want to optimize for preloading (all in context)
- Can keep OpenCode structure for compatibility

### 10.3 Maintaining Dual Compatibility

**Best practices**:
1. **Use OpenCode structure**: Works in both platforms
2. **Follow OpenCode naming**: Ensures compatibility
3. **Include required frontmatter**: Both platforms benefit
4. **Write generic tool references**: Avoid platform-specific syntax
5. **Test in both environments**: Catch platform-specific issues
6. **Document platform differences**: Note in skill content if needed

**Dual-compatible skill template**:
```markdown
---
name: skill-name
description: Brief, specific description (under 200 chars)
license: MIT
compatibility: opencode, claude
---

## Overview
Brief introduction to skill purpose

## When to Use
Clear applicability criteria

## Patterns
Core patterns with examples

**For OpenCode users**: Load related skills as needed
**For Claude Code users**: Related skills already loaded

## Examples
Concrete, tested code examples

## Related Skills
- `related-skill-1`: Description
- `related-skill-2`: Description
```

---

## 11. Recommendations for mind-vault

### 11.1 Structure Strategy

**Use OpenCode-compatible structure**:
```
skills/
├── django/
│   └── SKILL.md                    # Core patterns
├── django-multi-tenant/
│   └── SKILL.md                    # Multi-tenant specialization
├── django-async-websocket/
│   └── SKILL.md                    # Async WebSocket patterns
├── django-celery/
│   └── SKILL.md                    # Background tasks
├── django-celery-multitenant/
│   └── SKILL.md                    # Multi-tenant background tasks
└── django-async-websocket-multitenant/
    └── SKILL.md                    # Multi-tenant WebSocket patterns
```

**Benefits**:
- Works in both OpenCode and Claude Code
- Clear, organized structure
- Easy to maintain and validate
- Supports on-demand loading (OpenCode)
- Works with preloading (Claude Code)

### 11.2 Naming Strategy

**Use OpenCode-compliant names**:
- Lowercase only
- Single hyphens for separators
- Descriptive but concise
- Domain prefixes (e.g., `django-*`, `git-*`)

**Examples**:
```
✅ django-multi-tenant
✅ error-handling-async
✅ git-workflow
✅ docker-compose-patterns

❌ Django-MultiTenant
❌ error_handling_async
❌ git workflow
❌ docker.compose.patterns
```

### 11.3 Content Strategy

**Write for OpenCode, works in Claude Code**:
1. **Clear descriptions** (under 200 chars)
2. **Self-contained skills** (work standalone)
3. **Explicit prerequisites** (list related skills)
4. **Generic tool references** (describe actions, not tools)
5. **Standard markdown** (avoid platform-specific features)

**Template for mind-vault skills**:
```markdown
---
name: skill-name
description: Specific, actionable description
license: MIT
compatibility: opencode, claude
metadata:
  category: django
  complexity: intermediate
---

## Overview
Brief introduction (2-3 sentences)

## When to Use
- Specific scenario 1
- Specific scenario 2
- Decision criteria

**Do NOT use for**:
- Scenario where not applicable

## Prerequisites

**Related skills** (load as needed):
- `prerequisite-skill-1`: Why needed
- `prerequisite-skill-2`: Why needed

## Patterns

### Pattern 1: Name
Description and code example

### Pattern 2: Name
Description and code example

## Examples

### Example 1: Scenario
Complete, tested code example

### Example 2: Scenario
Complete, tested code example

## Important Considerations
- Edge case 1
- Common pitfall 1
- Performance note 1

## Related Skills
- `related-skill-1`: When to use instead
- `related-skill-2`: Complementary patterns
```

### 11.4 Permission Strategy

**Configure for OpenCode** (Claude Code less granular):
```json
{
  "permission": {
    "skill": {
      "*": "allow",                      // Allow all by default
      "experimental-*": "ask",           // Prompt for experimental
      "deprecated-*": "deny",            // Hide deprecated
      "internal-*": "ask"                // Prompt for internal
    }
  },
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "*": "allow"                   // Plan can use all
        }
      }
    }
  }
}
```

### 11.5 Testing Strategy

**Test in both platforms**:
1. **OpenCode validation**:
   - Run validation script
   - Test on-demand loading
   - Verify permissions work
   - Check agent selection

2. **Claude Code validation**:
   - Test session start loading
   - Verify content accessibility
   - Check agent usage patterns

3. **Cross-platform validation**:
   - Compare agent behavior
   - Verify pattern effectiveness
   - Check for platform-specific issues

---

## 12. Quick Reference

### 12.1 Compatibility Matrix

| Feature | OpenCode | Claude Code | Compatible Approach |
|---------|----------|-------------|---------------------|
| **File structure** | `skills/<name>/SKILL.md` | Flexible | Use OpenCode structure |
| **File naming** | `SKILL.md` (caps) | Flexible | Use `SKILL.md` |
| **Skill naming** | Lowercase, hyphens | Flexible | Use OpenCode format |
| **Frontmatter** | Required: name, description | Optional | Include both fields |
| **Loading** | On-demand | Session start | Design for on-demand |
| **Permissions** | Granular | Limited | Configure for OpenCode |
| **Tool references** | Specific syntax | Flexible | Use generic descriptions |

### 12.2 Decision Tree

**Choosing platform-specific features**:
```
Need skill for both platforms?
├─ Yes → Use OpenCode-compatible format
│         ├─ Lowercase, hyphenated names
│         ├─ Directory structure
│         ├─ Required frontmatter
│         └─ Generic tool references
│
└─ No → Platform-specific optimization
          ├─ OpenCode only → Use permissions, on-demand loading
          └─ Claude Code only → Optimize for preloading
```

### 12.3 Validation Checklist

**Cross-platform skill checklist**:
- [ ] Name matches regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Directory structure: `skills/<name>/SKILL.md`
- [ ] File named `SKILL.md` (exact case)
- [ ] Frontmatter includes `name` and `description`
- [ ] Description is 1-1024 characters
- [ ] Directory name matches frontmatter `name`
- [ ] Content uses standard markdown
- [ ] Code examples are syntactically correct
- [ ] Tool references are generic
- [ ] Tested in OpenCode
- [ ] Tested in Claude Code
- [ ] Agent behavior verified in both

---

## 13. Summary

**Key Takeaways**:

1. **Design for OpenCode**: Stricter requirements ensure compatibility with both platforms
2. **Use directory structure**: `skills/<name>/SKILL.md` works everywhere
3. **Follow naming rules**: Lowercase, single hyphens only
4. **Include frontmatter**: Always provide `name` and `description`
5. **Write generic content**: Avoid platform-specific syntax
6. **Test both platforms**: Verify behavior in OpenCode and Claude Code

**For mind-vault**:
- Use OpenCode-compatible structure throughout
- Configure OpenCode permissions for fine-grained control
- Write skills that work standalone (on-demand loading)
- Test in both environments before committing
- Document platform-specific considerations when needed

**Migration path**:
- Existing Claude Code skills → Add OpenCode validation
- New skills → Design for OpenCode from start
- Maintain compatibility → Test in both platforms

---

## 14. References

**OpenCode Documentation**:
- Skills: https://opencode.ai/docs/skills/
- Agents: https://opencode.ai/docs/agents/
- Permissions: https://opencode.ai/docs/permissions/

**Claude Code Documentation**:
- Skills: (varies by implementation)
- Configuration: `~/.claude/` directory

**mind-vault Files**:
- `OPENCODE_SKILL_SPECIFICATIONS.md`: Detailed OpenCode specs
- `AGENTS.md`: Project-level rules
- `skills/`: Skill directory

---

**Last Updated**: 2026-01-28  
**Document Version**: 1.0  
**Maintained By**: mind-vault project
