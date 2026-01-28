# OpenCode Agent Skills - Detailed Specifications

**Purpose**: Comprehensive analysis of OpenCode skill format and integration patterns  
**Date**: 2026-01-28  
**Status**: Ready  
**Applies To**: mind-vault skill development and validation  
**Source**: https://opencode.ai/docs/skills/

---

## Executive Summary

OpenCode uses a **directory-based skill system** where each skill is a folder containing a `SKILL.md` file with YAML frontmatter. Skills are **loaded on-demand** via a native `skill` tool, allowing agents to discover available skills and load full content only when needed. This differs from Claude Code's approach where skills may be loaded upfront.

**Key Differentiators**:
- **On-demand loading**: Skills appear in tool descriptions, agents load them explicitly
- **Strict naming validation**: Lowercase alphanumeric with single hyphens only
- **Permission-based access control**: Pattern-based allow/deny/ask system
- **Directory structure required**: Each skill must be in its own folder
- **Frontmatter validation**: Only specific fields recognized, others ignored

---

## 1. File Structure & Discovery

### 1.1 Directory Structure

**Required structure**:
```
skills/
├── skill-name/
│   └── SKILL.md          # Required, exact case
├── another-skill/
│   └── SKILL.md
└── third-skill/
    └── SKILL.md
```

**Key requirements**:
- Each skill must be in its own directory
- Directory name must match the `name` field in frontmatter
- File must be named `SKILL.md` (all caps)
- One `SKILL.md` per directory

### 1.2 Discovery Locations

OpenCode searches these locations in order:

**Project-local paths** (walks up from current directory to git worktree):
1. `.opencode/skills/<name>/SKILL.md`
2. `.claude/skills/<name>/SKILL.md` (Claude Code compatibility)

**Global paths**:
3. `~/.config/opencode/skills/<name>/SKILL.md`
4. `~/.claude/skills/<name>/SKILL.md` (Claude Code compatibility)

**Discovery behavior**:
- Walks up directory tree from current working directory
- Stops at git worktree boundary
- Loads all matching `skills/*/SKILL.md` along the way
- Global definitions loaded from home directory

**Disable Claude Code compatibility**:
```bash
export OPENCODE_DISABLE_CLAUDE_CODE=1        # Disable all .claude support
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 # Disable only .claude/skills
```

### 1.3 Precedence Rules

- **Unique names required**: Skill names must be unique across all locations
- **First match wins**: If duplicate names exist, first discovered skill is used
- **Project overrides global**: Project-local skills take precedence over global

---

## 2. Frontmatter Specification

### 2.1 Required Fields

```yaml
---
name: skill-name
description: Brief description of what this skill does
---
```

**Field requirements**:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `name` | ✅ Yes | string | 1-64 chars, lowercase alphanumeric with single hyphens |
| `description` | ✅ Yes | string | 1-1024 chars, specific enough for agent selection |

### 2.2 Optional Fields

```yaml
---
name: skill-name
description: Brief description
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: github
  version: "1.0"
---
```

**Optional field details**:

| Field | Type | Purpose | Example |
|-------|------|---------|---------|
| `license` | string | License identifier | `MIT`, `Apache-2.0`, `proprietary` |
| `compatibility` | string | Platform compatibility | `opencode`, `claude`, `both` |
| `metadata` | object | String-to-string key-value pairs | Custom categorization |

**Important**: Unknown frontmatter fields are **silently ignored** (no errors).

### 2.3 Name Validation Rules

**Regex pattern**:
```regex
^[a-z0-9]+(-[a-z0-9]+)*$
```

**Rules**:
- ✅ Must be 1-64 characters
- ✅ Lowercase alphanumeric only (`a-z`, `0-9`)
- ✅ Single hyphen separators allowed
- ❌ Cannot start with hyphen
- ❌ Cannot end with hyphen
- ❌ Cannot contain consecutive hyphens (`--`)
- ❌ No underscores, spaces, or special characters
- ✅ Must match directory name exactly

**Valid examples**:
```
git-release
django-patterns
error-handling
multi-tenant-async
```

**Invalid examples**:
```
Git-Release          # Uppercase
git_release          # Underscore
-git-release         # Starts with hyphen
git-release-         # Ends with hyphen
git--release         # Consecutive hyphens
git release          # Space
git.release          # Period
```

### 2.4 Description Guidelines

**Length**: 1-1024 characters (strictly enforced)

**Best practices**:
- Be specific enough for agent to choose correctly
- Focus on **when to use** the skill
- Avoid generic descriptions like "Helpful utilities"
- Include context about problem domain

**Good examples**:
```yaml
description: Create consistent releases and changelogs from merged PRs
description: Multi-tenant Django patterns with schema-per-tenant isolation
description: Async error categorization for WebSocket consumers
```

**Poor examples**:
```yaml
description: Useful patterns                    # Too vague
description: Django stuff                       # Not specific
description: Everything you need for releases   # Overpromises
```

---

## 3. Skill Content Structure

### 3.1 Recommended Sections

While OpenCode doesn't enforce content structure, effective skills typically include:

```markdown
---
name: example-skill
description: Brief one-liner
---

## What I do
- Clear bullet points of capabilities
- Specific actions this skill enables
- Concrete outcomes

## When to use me
Describe scenarios where this skill applies.
Include decision criteria for when NOT to use this skill.

## How to use me
Step-by-step guidance or patterns.
Include code examples where applicable.

## Important considerations
- Edge cases to watch for
- Common pitfalls
- Prerequisites or dependencies
```

### 3.2 Content Best Practices

**Be directive**:
- Use "I" voice ("What I do", "When to use me")
- Provide clear instructions, not just information
- Include actionable steps

**Provide context**:
- Explain the "why" behind patterns
- Note when to ask clarifying questions
- Reference related skills or tools

**Include examples**:
- Show concrete code snippets
- Demonstrate typical usage patterns
- Illustrate edge cases

**Keep it focused**:
- One skill = one coherent capability
- Split large skills into multiple focused skills
- Use references for related content

---

## 4. On-Demand Loading Mechanism

### 4.1 Tool Description Format

OpenCode lists available skills in the `skill` tool description:

```xml
<available_skills>
  <skill>
    <name>git-release</name>
    <description>Create consistent releases and changelogs</description>
  </skill>
  <skill>
    <name>django-patterns</name>
    <description>Multi-tenant Django architecture patterns</description>
  </skill>
</available_skills>
```

**Agent sees**:
- Skill name
- Skill description
- Nothing else until loaded

### 4.2 Loading Process

**Agent invocation**:
```javascript
skill({ name: "git-release" })
```

**What happens**:
1. OpenCode validates skill name exists
2. Checks permissions (allow/deny/ask)
3. Reads full `SKILL.md` content
4. Returns content to agent context
5. Agent uses instructions from skill

**Performance implications**:
- Skills not loaded until explicitly requested
- Reduces initial context size
- Allows large skill libraries without overhead
- Agent must know when to load skills

### 4.3 Lazy Loading Pattern

**Recommended approach** (from OpenCode docs):
```markdown
## External File Loading

CRITICAL: When you encounter a skill reference, use the skill tool 
to load it on a need-to-know basis when relevant to the SPECIFIC 
task at hand.

Instructions:
- Do NOT preemptively load all skills
- Load based on actual need for current task
- Treat loaded content as mandatory instructions
- Follow skill references recursively when needed
```

---

## 5. Permission System

### 5.1 Permission Levels

Three permission levels control skill access:

| Permission | Behavior | Use Case |
|------------|----------|----------|
| `allow` | Skill loads immediately without prompt | Trusted, frequently used skills |
| `deny` | Skill hidden from agent, access rejected | Experimental or restricted skills |
| `ask` | User prompted for approval before loading | Skills requiring review |

### 5.2 Global Configuration

**In `opencode.json`**:
```json
{
  "permission": {
    "skill": {
      "*": "allow",                    // Default: allow all
      "pr-review": "allow",            // Specific skill
      "internal-*": "deny",            // Pattern: deny internal-*
      "experimental-*": "ask"          // Pattern: prompt for experimental-*
    }
  }
}
```

**Pattern matching**:
- `*` matches zero or more characters
- `?` matches exactly one character
- Last matching rule wins

**Evaluation order**:
```json
{
  "permission": {
    "skill": {
      "*": "deny",                     // 1. Deny all by default
      "django-*": "allow",             // 2. Allow django-* skills
      "django-experimental": "ask"     // 3. But ask for this specific one
    }
  }
}
```

Result: `django-experimental` requires approval (last match wins).

### 5.3 Per-Agent Overrides

**For custom agents** (in agent frontmatter):
```yaml
---
name: document-writer
description: Documentation specialist
permission:
  skill:
    "documents-*": "allow"
    "code-*": "deny"
---
```

**For built-in agents** (in `opencode.json`):
```json
{
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "internal-*": "allow",       // Plan agent can use internal skills
          "*": "ask"                   // But asks for others
        }
      }
    }
  }
}
```

**Precedence**:
1. Agent-specific permissions (highest priority)
2. Global skill permissions
3. Default behavior (allow)

### 5.4 Disabling Skill Tool

**Completely disable skills for an agent**:

**Custom agent**:
```yaml
---
name: simple-agent
description: No skills needed
tools:
  skill: false
---
```

**Built-in agent**:
```json
{
  "agent": {
    "plan": {
      "tools": {
        "skill": false
      }
    }
  }
}
```

**Effect**: `<available_skills>` section omitted entirely from tool description.

---

## 6. Integration with OpenCode Ecosystem

### 6.1 Relationship to Rules (AGENTS.md)

**Rules vs Skills**:

| Aspect | Rules (AGENTS.md) | Skills (SKILL.md) |
|--------|-------------------|-------------------|
| **Scope** | Always loaded, global context | Loaded on-demand, task-specific |
| **Purpose** | Project conventions, coding standards | Reusable patterns, specialized knowledge |
| **Location** | Project root or `~/.config/opencode/` | `skills/` subdirectory |
| **Loading** | Automatic at session start | Explicit via `skill` tool |
| **Size** | Should be concise | Can be comprehensive |

**Complementary usage**:
```markdown
# AGENTS.md
## Django Project Rules

For multi-tenant patterns, load the skill:
- Use `skill({ name: "django-multi-tenant" })` when working with tenant isolation

## Code Standards
- Always use type hints
- Follow PEP 8
```

### 6.2 Relationship to Agents

**Agent types**:
- **Primary agents**: Main assistants (Build, Plan) - user switches between them
- **Subagents**: Specialized assistants (General, Explore) - invoked for specific tasks

**Skills work with all agent types**:
- Primary agents can load skills for their main work
- Subagents can load skills for specialized tasks
- Permissions control which agents access which skills

**Example workflow**:
1. User asks Build agent to implement multi-tenant feature
2. Build agent sees `django-multi-tenant` skill in available list
3. Build agent loads skill: `skill({ name: "django-multi-tenant" })`
4. Build agent follows patterns from skill content
5. Build agent may invoke subagent with skill context

### 6.3 Relationship to Commands

**Commands** (custom slash commands) can reference skills:

```markdown
# .opencode/commands/review-tenant.md
---
description: Review multi-tenant code
agent: plan
---

Load the django-multi-tenant skill and review the code in 
@src/tenants/ for proper tenant isolation patterns.
```

**Workflow**:
1. User runs `/review-tenant`
2. Command prompt sent to Plan agent
3. Plan agent loads `django-multi-tenant` skill
4. Plan agent reviews code against skill patterns

### 6.4 Relationship to Tools

**Skills are loaded via the `skill` tool**:
- Built-in tool, always available (unless disabled)
- Subject to permission system like other tools
- Returns skill content as text

**Skills can reference other tools**:
```markdown
## How to use me

1. Use the `grep` tool to find all TenantModel subclasses:
   grep({ pattern: "class.*TenantModel", include: "*.py" })

2. Use the `read` tool to examine each model:
   read({ filePath: "path/to/model.py" })

3. Verify tenant context usage patterns
```

---

## 7. Troubleshooting & Validation

### 7.1 Common Issues

**Skill not showing up**:

| Check | Solution |
|-------|----------|
| File name | Must be `SKILL.md` (all caps) |
| Frontmatter | Must include `name` and `description` |
| Name uniqueness | Skill names must be unique across all locations |
| Permissions | Check if skill has `deny` permission |
| Directory structure | Skill must be in `skills/<name>/SKILL.md` |

**Skill loads but content ignored**:
- Verify frontmatter YAML is valid
- Check for parsing errors in content
- Ensure description is specific enough for agent to select

**Permission issues**:
- Check global `permission.skill` settings
- Check agent-specific permission overrides
- Verify pattern matching rules (last match wins)

### 7.2 Validation Checklist

**Before committing a skill**:

- [ ] Directory name matches `name` field in frontmatter
- [ ] Name follows regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Name is 1-64 characters
- [ ] Description is 1-1024 characters
- [ ] Description is specific and actionable
- [ ] File named `SKILL.md` (exact case)
- [ ] Frontmatter includes required fields (`name`, `description`)
- [ ] Content provides clear, directive instructions
- [ ] Examples included where applicable
- [ ] No duplicate skill names in repository
- [ ] Permissions configured appropriately

### 7.3 Testing Skills

**Manual testing**:
1. Start OpenCode in project directory
2. Check skill appears in autocomplete
3. Load skill: `skill({ name: "your-skill" })`
4. Verify content loads correctly
5. Test agent follows skill instructions

**Permission testing**:
1. Set permission to `ask`
2. Attempt to load skill
3. Verify prompt appears
4. Test `allow`, `deny`, and `once` options

---

## 8. Comparison: OpenCode vs Claude Code

### 8.1 Key Differences

| Aspect | OpenCode | Claude Code |
|--------|----------|-------------|
| **Loading** | On-demand via `skill` tool | Loaded at session start (varies) |
| **Discovery** | Tool description lists available skills | Skills in context from start |
| **Structure** | Directory per skill required | Single file or directory |
| **Naming** | Strict validation (lowercase, hyphens) | More flexible |
| **Permissions** | Granular allow/deny/ask per skill | Less granular control |
| **Frontmatter** | Only specific fields recognized | More flexible |
| **Compatibility** | Reads `.claude/skills/` as fallback | Native format |

### 8.2 Migration Considerations

**From Claude Code to OpenCode**:

1. **Directory structure**: Ensure each skill is in its own folder
2. **Naming**: Validate all skill names against OpenCode regex
3. **Frontmatter**: Verify required fields present
4. **Loading**: Update documentation to reflect on-demand loading
5. **Permissions**: Configure skill permissions in `opencode.json`

**Maintaining compatibility**:
- Place skills in `.claude/skills/` for both platforms
- Use OpenCode-compliant naming (works in both)
- Keep frontmatter minimal (required fields only)
- Test in both environments

---

## 9. Best Practices for mind-vault

### 9.1 Skill Organization

**Recommended structure**:
```
skills/
├── django/
│   └── SKILL.md                    # Core Django patterns
├── django-multi-tenant/
│   └── SKILL.md                    # Multi-tenant specialization
├── django-async-websocket/
│   └── SKILL.md                    # Async WebSocket patterns
├── error-handling-async/
│   └── SKILL.md                    # Async error patterns
└── git-workflow/
    └── SKILL.md                    # Git conventions
```

**Naming strategy**:
- Use domain prefixes: `django-*`, `git-*`, `docker-*`
- Keep names descriptive but concise
- Use hyphens for multi-word names
- Avoid abbreviations unless widely known

### 9.2 Content Guidelines

**For mind-vault skills**:

1. **Start with clear scope**:
   ```markdown
   ## What I do
   - Provide multi-tenant Django patterns using django-tenants
   - Focus on schema-per-tenant isolation
   - Cover tenant context propagation
   ```

2. **Define applicability**:
   ```markdown
   ## When to use me
   Use this skill when:
   - Implementing multi-tenant SaaS applications
   - Using django-tenants package
   - Need schema-per-tenant isolation (not row-level)
   
   Do NOT use this skill for:
   - Row-level multi-tenancy (use django-multi-tenant-row instead)
   - Single-tenant applications
   ```

3. **Provide actionable patterns**:
   ```markdown
   ## Patterns
   
   ### Tenant Context in Views
   ```python
   from django_tenants.utils import tenant_context
   
   def get_tenant_data(tenant_id):
       tenant = get_tenant_by_id(tenant_id)
       with tenant_context(tenant):
           return Article.objects.all()
   ```
   ```

4. **Reference related skills**:
   ```markdown
   ## Related Skills
   - `django-async-websocket`: For WebSocket tenant context
   - `django-celery-multitenant`: For background task tenant context
   ```

### 9.3 Permission Strategy

**For mind-vault**:

```json
{
  "permission": {
    "skill": {
      "*": "allow",                      // Allow all by default
      "experimental-*": "ask",           // Prompt for experimental
      "deprecated-*": "deny"             // Hide deprecated
    }
  }
}
```

**Agent-specific**:
```json
{
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "*": "allow"                   // Plan can use all skills
        }
      }
    },
    "build": {
      "permission": {
        "skill": {
          "*": "allow",
          "experimental-*": "ask"        // Build asks for experimental
        }
      }
    }
  }
}
```

### 9.4 Maintenance Workflow

**Adding new skills**:
1. Create directory: `skills/new-skill/`
2. Create `SKILL.md` with required frontmatter
3. Validate name against regex
4. Write clear, directive content
5. Test loading in OpenCode
6. Configure permissions if needed
7. Document in repository README

**Updating existing skills**:
1. Load skill in OpenCode to verify current state
2. Make content changes (frontmatter changes require care)
3. Test loading after changes
4. Update version in metadata if using versioning
5. Document changes in commit message

**Deprecating skills**:
1. Add `deprecated-` prefix to directory name
2. Update frontmatter description to note deprecation
3. Add deprecation notice at top of content
4. Set permission to `deny` or `ask`
5. Keep for reference, remove after transition period

---

## 10. Advanced Patterns

### 10.1 Skill Composition

**Referencing other skills**:
```markdown
## Prerequisites

Before using this skill, load these foundational skills:
- `django-architecture`: Core Django patterns
- `error-handling-async`: Async error patterns

Load them with:
skill({ name: "django-architecture" })
skill({ name: "error-handling-async" })
```

### 10.2 Conditional Loading

**In skill content**:
```markdown
## Conditional Patterns

If working with WebSockets:
- Load `django-async-websocket` skill
- Apply tenant context in consumers

If working with background tasks:
- Load `django-celery-multitenant` skill
- Pass tenant_id to all tasks
```

### 10.3 Skill Metadata Usage

**Categorization**:
```yaml
---
name: django-multi-tenant
description: Multi-tenant Django patterns
metadata:
  category: django
  subcategory: multi-tenant
  complexity: advanced
  dependencies: django-tenants
  version: "2.0"
---
```

**Querying** (in AGENTS.md or commands):
```markdown
When selecting Django skills, prefer:
- Skills with `category: django`
- Skills matching current complexity level
- Skills with compatible versions
```

### 10.4 Skill Templates

**Create skill template**:
```markdown
# skills/_template/SKILL.md
---
name: template-skill
description: Template for creating new skills
---

## What I do
- [Describe capabilities]
- [List specific actions]
- [Note concrete outcomes]

## When to use me
[Describe scenarios and decision criteria]

## How to use me
[Step-by-step guidance]

## Important considerations
- [Edge cases]
- [Common pitfalls]
- [Prerequisites]

## Examples
[Code snippets and usage patterns]

## Related Skills
- [Related skill names]
```

---

## 11. OpenCode-Specific Features

### 11.1 Skill Tool Behavior

**Tool description format**:
- Skills listed in XML format
- Only name and description exposed
- Full content loaded on demand
- Tool respects permission system

**Agent decision-making**:
- Agent sees all allowed skills in tool description
- Agent decides when to load based on task
- Agent can load multiple skills in sequence
- Agent can reference loaded skills later in conversation

### 11.2 Integration with Other Tools

**Skills can guide tool usage**:
```markdown
## Implementation Steps

1. **Find relevant files**:
   Use `glob` tool: glob({ pattern: "**/*tenant*.py" })

2. **Search for patterns**:
   Use `grep` tool: grep({ pattern: "TenantModel", include: "*.py" })

3. **Read and analyze**:
   Use `read` tool on each file

4. **Make changes**:
   Use `edit` tool with exact string replacement
```

### 11.3 Skill + Command Synergy

**Command that loads skill**:
```markdown
# .opencode/commands/tenant-check.md
---
description: Check tenant isolation patterns
agent: plan
---

Load the django-multi-tenant skill and analyze all models in 
@src/tenants/ for proper tenant isolation.

Verify:
- All tenant models inherit from TenantModel
- No tenant_id foreign keys used
- All queries use tenant_context
```

---

## 12. Validation & Quality Assurance

### 12.1 Automated Validation Script

**Suggested validation script** (for mind-vault):
```bash
#!/bin/bash
# validate-skills.sh

for skill_dir in skills/*/; do
  skill_name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"
  
  # Check file exists
  if [ ! -f "$skill_file" ]; then
    echo "❌ Missing SKILL.md in $skill_name"
    continue
  fi
  
  # Check name format
  if ! echo "$skill_name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "❌ Invalid name format: $skill_name"
  fi
  
  # Check frontmatter
  if ! grep -q "^name: $skill_name$" "$skill_file"; then
    echo "❌ Name mismatch in $skill_name"
  fi
  
  if ! grep -q "^description: " "$skill_file"; then
    echo "❌ Missing description in $skill_name"
  fi
  
  echo "✅ $skill_name validated"
done
```

### 12.2 Quality Checklist

**Content quality**:
- [ ] Clear, directive language ("do this", not "you could")
- [ ] Concrete examples with code snippets
- [ ] Explains "why" not just "what"
- [ ] Includes edge cases and pitfalls
- [ ] References related skills appropriately
- [ ] No outdated or deprecated patterns

**Technical quality**:
- [ ] Code examples are syntactically correct
- [ ] Patterns tested in production
- [ ] Compatible with specified versions
- [ ] No security vulnerabilities in examples
- [ ] Performance considerations noted

**Documentation quality**:
- [ ] Proper markdown formatting
- [ ] Code blocks have language tags
- [ ] Links are valid (internal and external)
- [ ] Consistent terminology
- [ ] No typos or grammatical errors

---

## 13. Future Considerations

### 13.1 Potential Enhancements

**Skill versioning**:
- Use metadata for version tracking
- Support loading specific versions
- Deprecation and migration paths

**Skill dependencies**:
- Declare required skills in frontmatter
- Auto-load dependencies
- Validate dependency chains

**Skill testing**:
- Test fixtures for skill validation
- Automated testing of skill patterns
- Integration tests with OpenCode

### 13.2 Monitoring & Analytics

**Track skill usage**:
- Which skills are loaded most frequently
- Which skills are never loaded (candidates for removal)
- Which skills are denied by permissions
- Agent success rate after loading skills

**Improve based on data**:
- Refine descriptions for better discoverability
- Split or merge skills based on usage patterns
- Update content based on agent feedback
- Optimize permissions based on usage

---

## 14. Summary & Quick Reference

### 14.1 Essential Requirements

**File structure**:
```
skills/<skill-name>/SKILL.md
```

**Minimal frontmatter**:
```yaml
---
name: skill-name
description: What this skill does (1-1024 chars)
---
```

**Name validation**:
```regex
^[a-z0-9]+(-[a-z0-9]+)*$
```

**Loading**:
```javascript
skill({ name: "skill-name" })
```

### 14.2 Common Patterns

**Allow all skills**:
```json
{
  "permission": {
    "skill": {
      "*": "allow"
    }
  }
}
```

**Deny experimental skills**:
```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "experimental-*": "deny"
    }
  }
}
```

**Ask for specific skill**:
```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "dangerous-skill": "ask"
    }
  }
}
```

### 14.3 Troubleshooting Quick Guide

| Problem | Solution |
|---------|----------|
| Skill not listed | Check file name is `SKILL.md` (caps) |
| Skill listed but won't load | Check permissions |
| Name validation error | Use lowercase, hyphens only |
| Content not applied | Check description specificity |
| Duplicate skill error | Ensure unique names across all locations |

---

## 15. References

**OpenCode Documentation**:
- Skills: https://opencode.ai/docs/skills/
- Rules: https://opencode.ai/docs/rules/
- Agents: https://opencode.ai/docs/agents/
- Commands: https://opencode.ai/docs/commands/
- Tools: https://opencode.ai/docs/tools/
- Permissions: https://opencode.ai/docs/permissions/

**Related mind-vault Files**:
- `AGENTS.md`: Project-level rules and conventions
- `skills/`: Skill directory
- `agents/`: Custom agent definitions
- `rules/`: Behavioral rules

**Validation Tools**:
- Name regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- Description length: 1-1024 characters
- File name: `SKILL.md` (exact case)

---

**Last Updated**: 2026-01-28  
**Document Version**: 1.0  
**Maintained By**: mind-vault project
