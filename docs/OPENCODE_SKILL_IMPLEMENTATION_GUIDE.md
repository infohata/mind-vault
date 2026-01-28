# OpenCode Skill Implementation Guide

**Purpose**: Practical guide for creating OpenCode-compatible skills in mind-vault  
**Date**: 2026-01-28  
**Status**: Ready  
**Applies To**: mind-vault skill development workflow

---

## Quick Start

### Creating a New Skill (5 Steps)

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
   description: Brief, specific description of what this skill does
   ---
   ```

4. **Write content**:
   ```markdown
   ## Overview
   [Your skill content]
   ```

5. **Validate**:
   ```bash
   ./tools/validate-skills.sh your-skill-name
   ```

---

## 1. Naming Your Skill

### 1.1 Name Format Rules

**Regex**: `^[a-z0-9]+(-[a-z0-9]+)*$`

**Requirements**:
- ✅ Lowercase letters only (`a-z`)
- ✅ Numbers allowed (`0-9`)
- ✅ Single hyphens as separators
- ❌ No uppercase
- ❌ No underscores
- ❌ No spaces
- ❌ No consecutive hyphens
- ❌ Cannot start or end with hyphen
- ✅ 1-64 characters

### 1.2 Naming Patterns

**Use domain prefixes**:
```
django-*              # Django-related skills
git-*                 # Git workflow skills
docker-*              # Docker/containerization
error-handling-*      # Error handling patterns
testing-*             # Testing strategies
```

**Examples**:
```
✅ django-multi-tenant
✅ django-async-websocket
✅ error-handling-async
✅ git-workflow
✅ docker-compose-dev
✅ testing-integration

❌ Django-MultiTenant      # Uppercase
❌ django_multi_tenant     # Underscore
❌ django--multi-tenant    # Double hyphen
❌ -django-multi-tenant    # Leading hyphen
❌ django-multi-tenant-    # Trailing hyphen
```

### 1.3 Name Selection Strategy

**Good names are**:
- **Descriptive**: Clearly indicate purpose
- **Specific**: Not too generic
- **Concise**: Short but meaningful
- **Consistent**: Follow existing patterns

**Examples**:

| ❌ Too Generic | ✅ Specific | ✅ Better |
|---------------|------------|----------|
| `patterns` | `django-patterns` | `django-multi-tenant` |
| `async` | `async-patterns` | `error-handling-async` |
| `database` | `database-patterns` | `django-orm-optimization` |
| `testing` | `testing-patterns` | `testing-integration-django` |

---

## 2. Directory Structure

### 2.1 Required Structure

```
skills/
└── your-skill-name/          # Directory name must match frontmatter 'name'
    └── SKILL.md              # Exact case required
```

**Critical requirements**:
- Directory name must match `name` field in frontmatter exactly
- File must be named `SKILL.md` (all caps)
- One skill per directory
- No nested skill directories

### 2.2 Optional Supporting Files

```
skills/
└── your-skill-name/
    ├── SKILL.md              # Required
    ├── examples/             # Optional: code examples
    │   ├── example1.py
    │   └── example2.py
    ├── templates/            # Optional: code templates
    │   └── template.py
    └── README.md             # Optional: additional documentation
```

**Note**: Only `SKILL.md` is loaded by OpenCode. Other files are for reference.

### 2.3 Location Options

**Project-local** (recommended for project-specific skills):
```
.claude/skills/your-skill-name/SKILL.md
```

**Global** (for reusable skills across projects):
```
~/.claude/skills/your-skill-name/SKILL.md
```

**OpenCode-specific** (if not using Claude Code):
```
.opencode/skills/your-skill-name/SKILL.md
~/.config/opencode/skills/your-skill-name/SKILL.md
```

**For mind-vault**: Use `.claude/skills/` for maximum compatibility.

---

## 3. Frontmatter Specification

### 3.1 Minimal Required Frontmatter

```yaml
---
name: your-skill-name
description: Brief description of what this skill does (1-1024 chars)
---
```

**Field requirements**:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `name` | ✅ Yes | string | Must match directory name, follow regex |
| `description` | ✅ Yes | string | 1-1024 characters, specific and actionable |

### 3.2 Recommended Optional Fields

```yaml
---
name: your-skill-name
description: Brief description
license: MIT
compatibility: opencode, claude
metadata:
  category: django
  subcategory: multi-tenant
  complexity: intermediate
  version: "1.0"
  author: mind-vault
---
```

**Optional fields**:

| Field | Type | Purpose | Example |
|-------|------|---------|---------|
| `license` | string | License identifier | `MIT`, `Apache-2.0` |
| `compatibility` | string | Platform compatibility | `opencode`, `claude`, `both` |
| `metadata` | object | Custom key-value pairs | See below |

### 3.3 Metadata Conventions

**Recommended metadata fields**:

```yaml
metadata:
  category: django              # Primary domain
  subcategory: multi-tenant     # Specific area
  complexity: intermediate      # beginner, intermediate, advanced
  version: "1.0"                # Skill version
  author: mind-vault            # Author/maintainer
  tags: multi-tenant,django     # Comma-separated tags
  updated: "2026-01-28"         # Last update date
```

**Use metadata for**:
- Categorization and discovery
- Version tracking
- Complexity indication
- Maintenance tracking

### 3.4 Description Best Practices

**Length**: 1-1024 characters (aim for 100-200)

**Good descriptions**:
```yaml
# ✅ Specific and actionable
description: Multi-tenant Django patterns with schema-per-tenant isolation using django-tenants

# ✅ Clear use case
description: Async error categorization for WebSocket consumers with graceful degradation

# ✅ Technology-specific
description: Git workflow conventions for feature branches, commits, and pull requests
```

**Poor descriptions**:
```yaml
# ❌ Too vague
description: Django patterns

# ❌ Too generic
description: Useful utilities for development

# ❌ Too long (over 200 chars)
description: This comprehensive skill provides detailed patterns for implementing multi-tenant architecture in Django applications using the django-tenants package with schema-per-tenant isolation including tenant context management, middleware configuration, model design, and integration with async operations and background tasks
```

**Formula for good descriptions**:
```
[Technology] [specific pattern/feature] [key benefit/approach]

Examples:
- Django multi-tenant patterns with schema-per-tenant isolation
- Async error handling with graceful degradation strategies
- Git workflow for feature branches and atomic commits
```

---

## 4. Content Structure

### 4.1 Recommended Template

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
Brief introduction (2-3 sentences) explaining what this skill covers and why it matters.

## When to Use
Clear criteria for when this skill applies:
- Specific scenario 1
- Specific scenario 2
- Technology/framework requirement

**Do NOT use for**:
- Scenario where not applicable
- Alternative approach scenario

## Prerequisites

**Knowledge prerequisites**:
- Required background knowledge
- Assumed familiarity with technologies

**Related skills** (load as needed):
- `prerequisite-skill`: Why needed
- `complementary-skill`: How it relates

## Core Patterns

### Pattern 1: Descriptive Name
Brief explanation of the pattern.

**When to use**: Specific use case

**Implementation**:
```python
# Complete, working code example
def example_pattern():
    """Docstring explaining the pattern."""
    return implementation
```

**Key points**:
- Important consideration 1
- Important consideration 2

### Pattern 2: Descriptive Name
[Same structure as Pattern 1]

## Examples

### Example 1: Real-World Scenario
Description of the scenario.

```python
# Complete, tested code example
# Include imports and context
from django.db import models

class Example(models.Model):
    field = models.CharField(max_length=100)
    
    def method(self):
        """Implementation."""
        pass
```

**Explanation**:
- What this example demonstrates
- Why this approach is used
- Edge cases handled

### Example 2: Another Scenario
[Same structure as Example 1]

## Common Pitfalls

### Pitfall 1: Description
**Problem**: What goes wrong

**Solution**: How to avoid it

**Example**:
```python
# ❌ Wrong approach
wrong_code()

# ✅ Correct approach
correct_code()
```

### Pitfall 2: Description
[Same structure as Pitfall 1]

## Important Considerations

### Performance
- Performance consideration 1
- Performance consideration 2

### Security
- Security consideration 1
- Security consideration 2

### Scalability
- Scalability consideration 1
- Scalability consideration 2

## Testing

### Testing Strategy
How to test implementations using this skill.

```python
# Example test
def test_pattern():
    """Test the pattern implementation."""
    assert expected_behavior()
```

## Related Skills

- `related-skill-1`: When to use instead of this skill
- `related-skill-2`: Complementary patterns to combine
- `related-skill-3`: Advanced patterns building on this

## References

- [Official Documentation](https://example.com/docs)
- [Related Article](https://example.com/article)
- Internal: `docs/RELATED_DOC.md`
```

### 4.2 Section Guidelines

**Overview** (required):
- 2-3 sentences
- Explain what and why
- Set expectations

**When to Use** (required):
- Clear applicability criteria
- Include negative cases (when NOT to use)
- Help agent make correct selection

**Prerequisites** (recommended):
- Knowledge requirements
- Related skills to load
- Technology dependencies

**Core Patterns** (required):
- 2-5 main patterns
- Each with explanation and code
- Include "when to use" for each

**Examples** (required):
- 2-3 complete examples
- Real-world scenarios
- Tested, working code

**Common Pitfalls** (recommended):
- 2-3 common mistakes
- Show wrong vs. right approach
- Explain why it matters

**Important Considerations** (recommended):
- Performance implications
- Security concerns
- Scalability notes

**Testing** (optional):
- How to test implementations
- Example tests
- Testing strategies

**Related Skills** (recommended):
- Links to related skills
- Explain relationships
- Guide to skill composition

**References** (optional):
- External documentation
- Related articles
- Internal documentation

### 4.3 Writing Style

**Voice**:
- Use "I" voice in section headers ("When to use me")
- Use directive language ("Do this", not "You could do this")
- Be specific and actionable

**Tone**:
- Professional but approachable
- Technical but clear
- Confident but not dogmatic

**Structure**:
- Short paragraphs (2-4 sentences)
- Bullet points for lists
- Code examples for concrete patterns
- Tables for comparisons

**Examples**:

✅ **Good**:
```markdown
## When to Use Me

Use this skill when:
- Implementing multi-tenant SaaS with Django
- Using django-tenants package for schema isolation
- Need to maintain strict tenant data separation

Do NOT use for:
- Single-tenant applications
- Row-level multi-tenancy (use django-multi-tenant-row instead)
```

❌ **Poor**:
```markdown
## When to Use

This skill might be useful if you're working on something with multiple tenants. 
It could help with Django projects. You might want to consider using it for 
various scenarios where tenant isolation is important.
```

---

## 5. Code Examples

### 5.1 Code Block Standards

**Always specify language**:
```markdown
```python
# Python code
```

```bash
# Shell commands
```

```yaml
# YAML configuration
```

```json
// JSON configuration
```
```

**Include context**:
```python
# ✅ Good: Complete, runnable example
from django_tenants.utils import tenant_context
from myapp.models import Article

def get_tenant_articles(tenant_id):
    """Retrieve articles for a specific tenant."""
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        return Article.objects.all()

# ❌ Poor: Incomplete, missing imports
def get_articles(tenant_id):
    with tenant_context(tenant):
        return Article.objects.all()
```

### 5.2 Example Structure

**Complete examples**:
```python
# Imports
from django.db import models
from django_tenants.models import TenantModel

# Context
class Article(TenantModel):
    """Article model with tenant isolation."""
    
    # Fields
    title = models.CharField(max_length=200)
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    
    # Methods
    def __str__(self):
        return self.title
    
    # Meta
    class Meta:
        ordering = ['-created_at']
```

**Annotated examples**:
```python
# Step 1: Import required modules
from django_tenants.utils import tenant_context

# Step 2: Get tenant instance
tenant = get_tenant_by_id(tenant_id)

# Step 3: Establish tenant context
with tenant_context(tenant):
    # Step 4: Query within tenant schema
    articles = Article.objects.all()
    
    # Step 5: Process results
    for article in articles:
        process_article(article)
```

### 5.3 Comparison Examples

**Show wrong vs. right**:
```python
# ❌ Wrong: No tenant context
def get_articles():
    return Article.objects.all()  # Could access wrong schema

# ✅ Correct: Explicit tenant context
def get_articles(tenant_id):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        return Article.objects.all()  # Guaranteed correct schema
```

### 5.4 Multi-Language Examples

**When showing multiple languages**:
```markdown
### Example: Configuration

**Python**:
```python
TENANT_MODEL = "tenants.Tenant"
TENANT_DOMAIN_MODEL = "tenants.Domain"
```

**YAML** (for environment):
```yaml
environment:
  TENANT_MODEL: "tenants.Tenant"
  TENANT_DOMAIN_MODEL: "tenants.Domain"
```

**Shell** (for testing):
```bash
export TENANT_MODEL="tenants.Tenant"
export TENANT_DOMAIN_MODEL="tenants.Domain"
```
```

---

## 6. Skill References

### 6.1 Referencing Related Skills

**Explicit loading syntax** (OpenCode):
```markdown
## Prerequisites

Load these skills before proceeding:

```javascript
skill({ name: "django-architecture" })
skill({ name: "error-handling-async" })
```

These provide foundational patterns used in this skill.
```

**Generic reference** (works in both):
```markdown
## Related Skills

This skill builds on patterns from:
- `django-architecture`: Core Django patterns
- `error-handling-async`: Async error categorization

**For OpenCode**: Load these skills using the skill tool
**For Claude Code**: These skills are already loaded
```

### 6.2 Conditional References

```markdown
## Conditional Patterns

### If Working with WebSockets
Load the `django-async-websocket` skill for:
- Async consumer patterns
- WebSocket error handling
- Real-time data streaming

### If Working with Background Tasks
Load the `django-celery` skill for:
- Task definition patterns
- Error handling and retries
- Task scheduling
```

### 6.3 Skill Composition

```markdown
## Skill Composition

This skill combines patterns from:

1. **Foundation**: `django-architecture`
   - BaseModel patterns
   - DRF conventions
   - ASGI setup

2. **Specialization**: `django-multi-tenant`
   - Tenant context management
   - Schema isolation
   - Tenant resolution

3. **Integration**: `django-async-websocket`
   - Async consumer patterns
   - Tenant context in WebSockets
   - Real-time updates

Load skills in this order for best results.
```

---

## 7. Tool Integration

### 7.1 Generic Tool References

**Describe actions, not tools**:
```markdown
## Implementation Steps

1. **Find tenant models**:
   Search for files matching pattern: `**/*tenant*.py`
   
2. **Search for patterns**:
   Search file contents for: `TenantModel`
   
3. **Read and analyze**:
   Read each matching file to verify patterns
   
4. **Make changes**:
   Edit files using exact string replacement
```

### 7.2 OpenCode-Specific Tool References

**When targeting OpenCode specifically**:
```markdown
## Implementation Steps (OpenCode)

1. **Find tenant models**:
   ```javascript
   glob({ pattern: "**/*tenant*.py" })
   ```

2. **Search for patterns**:
   ```javascript
   grep({ pattern: "TenantModel", include: "*.py" })
   ```

3. **Read files**:
   ```javascript
   read({ filePath: "path/to/file.py" })
   ```

4. **Make changes**:
   ```javascript
   edit({ 
     filePath: "path/to/file.py",
     oldString: "old code",
     newString: "new code"
   })
   ```
```

### 7.3 Tool Guidance

**Guide tool usage without specifying tools**:
```markdown
## Verification Steps

1. **Locate all models**:
   Find all Python files in the models directory
   
2. **Check inheritance**:
   Search for classes inheriting from TenantModel
   
3. **Verify context usage**:
   Search for `tenant_context` usage in views
   
4. **Validate queries**:
   Ensure all queries are within tenant context
```

---

## 8. Validation & Testing

### 8.1 Pre-Commit Validation

**Checklist**:
- [ ] Name matches regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Directory name matches frontmatter `name`
- [ ] File named `SKILL.md` (exact case)
- [ ] Frontmatter includes `name` and `description`
- [ ] Description is 1-1024 characters
- [ ] All code examples are syntactically correct
- [ ] All internal references are valid
- [ ] No typos or grammatical errors

### 8.2 Validation Script

**Create `tools/validate-skills.sh`**:
```bash
#!/bin/bash
# Validate OpenCode skill format

SKILL_NAME="$1"
SKILL_DIR="skills/$SKILL_NAME"
SKILL_FILE="$SKILL_DIR/SKILL.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Validating skill: $SKILL_NAME"
echo "================================"

# Check directory exists
if [ ! -d "$SKILL_DIR" ]; then
  echo -e "${RED}❌ Directory not found: $SKILL_DIR${NC}"
  exit 1
fi

# Check SKILL.md exists
if [ ! -f "$SKILL_FILE" ]; then
  echo -e "${RED}❌ SKILL.md not found in $SKILL_DIR${NC}"
  exit 1
fi

# Validate name format
if ! echo "$SKILL_NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo -e "${RED}❌ Invalid name format: $SKILL_NAME${NC}"
  echo "   Must match: ^[a-z0-9]+(-[a-z0-9]+)*$"
  exit 1
fi

# Check name length
NAME_LENGTH=${#SKILL_NAME}
if [ $NAME_LENGTH -lt 1 ] || [ $NAME_LENGTH -gt 64 ]; then
  echo -e "${RED}❌ Name length must be 1-64 characters (got $NAME_LENGTH)${NC}"
  exit 1
fi

# Check frontmatter name matches
if ! grep -q "^name: $SKILL_NAME$" "$SKILL_FILE"; then
  echo -e "${RED}❌ Frontmatter 'name' doesn't match directory name${NC}"
  exit 1
fi

# Check description exists
if ! grep -q "^description: " "$SKILL_FILE"; then
  echo -e "${RED}❌ Missing 'description' in frontmatter${NC}"
  exit 1
fi

# Check description length
DESCRIPTION=$(grep "^description: " "$SKILL_FILE" | sed 's/^description: //')
DESC_LENGTH=${#DESCRIPTION}
if [ $DESC_LENGTH -lt 1 ] || [ $DESC_LENGTH -gt 1024 ]; then
  echo -e "${YELLOW}⚠️  Description length should be 1-1024 characters (got $DESC_LENGTH)${NC}"
fi

# Check for common issues
if grep -q "TODO" "$SKILL_FILE"; then
  echo -e "${YELLOW}⚠️  Found TODO comments${NC}"
fi

if grep -q "FIXME" "$SKILL_FILE"; then
  echo -e "${YELLOW}⚠️  Found FIXME comments${NC}"
fi

echo -e "${GREEN}✅ Skill validation passed: $SKILL_NAME${NC}"
exit 0
```

**Usage**:
```bash
chmod +x tools/validate-skills.sh
./tools/validate-skills.sh django-multi-tenant
```

### 8.3 Testing in OpenCode

**Manual testing**:
```bash
# 1. Start OpenCode in project directory
cd /path/to/project
opencode

# 2. Check skill appears in autocomplete
# Type: skill({ name: "
# Should see your skill in list

# 3. Load skill
skill({ name: "your-skill-name" })

# 4. Verify content loads
# Should see full skill content

# 5. Test agent follows patterns
# Give agent a task that should use the skill
# Verify agent applies patterns correctly
```

### 8.4 Testing Permissions

**Test permission levels**:
```bash
# 1. Set permission to "ask" in opencode.json
{
  "permission": {
    "skill": {
      "your-skill-name": "ask"
    }
  }
}

# 2. Attempt to load skill
skill({ name: "your-skill-name" })

# 3. Verify prompt appears
# Should see approval prompt

# 4. Test "allow", "deny", and "once" options
# Verify each behaves correctly
```

---

## 9. Common Patterns

### 9.1 Django Skill Pattern

```markdown
---
name: django-pattern-name
description: Django [specific feature] with [key approach]
metadata:
  category: django
  complexity: intermediate
---

## Overview
Django pattern for [specific use case].

## When to Use
- Django [version] or later
- Using [specific package/feature]
- Need [specific capability]

## Prerequisites
- `django-architecture`: Core Django patterns

## Core Patterns

### Pattern 1: Model Design
```python
from django.db import models

class Example(models.Model):
    # Implementation
    pass
```

### Pattern 2: View Implementation
```python
from rest_framework import viewsets

class ExampleViewSet(viewsets.ModelViewSet):
    # Implementation
    pass
```

## Examples
[Complete Django examples]

## Common Pitfalls
[Django-specific pitfalls]

## Testing
```python
from django.test import TestCase

class ExampleTestCase(TestCase):
    # Test implementation
    pass
```
```

### 9.2 Async Pattern

```markdown
---
name: async-pattern-name
description: Async [specific feature] with [key approach]
metadata:
  category: async
  complexity: advanced
---

## Overview
Async pattern for [specific use case].

## When to Use
- Async/await code
- [Specific async framework]
- Need [specific async capability]

## Core Patterns

### Pattern 1: Async Function
```python
async def example_async():
    # Implementation
    pass
```

### Pattern 2: Error Handling
```python
async def example_with_error_handling():
    try:
        # Implementation
    except Exception as exc:
        # Error handling
        pass
```

## Important Considerations

### Event Loop Safety
- Never block the event loop
- Use async-friendly operations
- Wrap sync operations properly

### Concurrency
- Handle concurrent access
- Use proper locking
- Manage shared state
```

### 9.3 Testing Pattern

```markdown
---
name: testing-pattern-name
description: Testing [specific feature] with [key approach]
metadata:
  category: testing
  complexity: intermediate
---

## Overview
Testing pattern for [specific use case].

## When to Use
- Testing [specific type of code]
- Using [testing framework]
- Need [specific testing capability]

## Core Patterns

### Pattern 1: Unit Test
```python
import pytest

def test_example():
    # Test implementation
    assert expected_behavior()
```

### Pattern 2: Integration Test
```python
@pytest.mark.integration
def test_integration():
    # Integration test
    pass
```

## Testing Strategies
- Unit testing approach
- Integration testing approach
- End-to-end testing approach

## Common Testing Pitfalls
- Pitfall 1
- Pitfall 2
```

---

## 10. Maintenance

### 10.1 Updating Skills

**Process**:
1. Load current skill in OpenCode
2. Identify changes needed
3. Update content (preserve frontmatter)
4. Validate changes
5. Test loading
6. Update version in metadata
7. Document changes in commit

**Version tracking**:
```yaml
metadata:
  version: "1.1"
  updated: "2026-01-28"
  changelog: "Added async patterns, updated examples"
```

### 10.2 Deprecating Skills

**Process**:
1. Add deprecation notice at top
2. Update description to note deprecation
3. Add `deprecated-` prefix to directory name
4. Set permission to `deny` or `ask`
5. Keep for reference period
6. Remove after transition

**Deprecation notice**:
```markdown
---
name: deprecated-old-skill
description: [DEPRECATED] Use new-skill instead
---

## ⚠️ DEPRECATION NOTICE

This skill is deprecated as of 2026-01-28.

**Use instead**: `new-skill`

**Reason**: [Explanation of why deprecated]

**Migration guide**: [How to migrate to new skill]

---

[Original content preserved for reference]
```

### 10.3 Archiving Skills

**Archive structure**:
```
skills/
├── _archived/
│   └── old-skill-name/
│       ├── SKILL.md
│       └── ARCHIVED.md
```

**ARCHIVED.md**:
```markdown
# Archived Skill: old-skill-name

**Archived**: 2026-01-28  
**Reason**: Replaced by new-skill  
**Replacement**: `new-skill`

## Migration Notes
[How to migrate from this skill to replacement]

## Historical Context
[Why this skill existed, what it solved]
```

---

## 11. Troubleshooting

### 11.1 Skill Not Appearing

**Check**:
1. File named `SKILL.md` (exact case)
2. Directory name matches frontmatter `name`
3. Frontmatter includes `name` and `description`
4. Name follows regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
5. Skill not hidden by permissions

**Debug**:
```bash
# Check file exists
ls -la skills/your-skill-name/SKILL.md

# Check frontmatter
head -n 10 skills/your-skill-name/SKILL.md

# Validate name
echo "your-skill-name" | grep -E '^[a-z0-9]+(-[a-z0-9]+)*$'
```

### 11.2 Skill Loads But Content Ignored

**Check**:
1. Description is specific enough
2. Content is clear and directive
3. Code examples are correct
4. No parsing errors in YAML

**Debug**:
```bash
# Check YAML frontmatter
python3 -c "
import yaml
with open('skills/your-skill-name/SKILL.md') as f:
    content = f.read()
    frontmatter = content.split('---')[1]
    print(yaml.safe_load(frontmatter))
"
```

### 11.3 Permission Issues

**Check**:
1. Global permission settings
2. Agent-specific permission overrides
3. Pattern matching rules

**Debug**:
```bash
# Check opencode.json permissions
cat opencode.json | jq '.permission.skill'

# Check agent permissions
cat opencode.json | jq '.agent.build.permission.skill'
```

---

## 12. Quick Reference

### 12.1 Skill Creation Checklist

- [ ] Name follows regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Name is 1-64 characters
- [ ] Directory created: `skills/<name>/`
- [ ] File created: `skills/<name>/SKILL.md`
- [ ] Directory name matches frontmatter `name`
- [ ] Frontmatter includes `name` and `description`
- [ ] Description is 1-1024 characters
- [ ] Description is specific and actionable
- [ ] Content follows recommended structure
- [ ] Code examples are complete and tested
- [ ] Tool references are generic
- [ ] Related skills referenced appropriately
- [ ] Validation script passes
- [ ] Tested in OpenCode
- [ ] Permissions configured (if needed)

### 12.2 Common Commands

```bash
# Create skill directory
mkdir -p skills/skill-name

# Create SKILL.md
touch skills/skill-name/SKILL.md

# Validate skill
./tools/validate-skills.sh skill-name

# Test in OpenCode
opencode
# Then: skill({ name: "skill-name" })

# Check permissions
cat opencode.json | jq '.permission.skill'
```

### 12.3 Validation Regex

```regex
^[a-z0-9]+(-[a-z0-9]+)*$
```

**Test online**: https://regex101.com/

---

## 13. Examples

### 13.1 Complete Minimal Skill

**File**: `skills/example-minimal/SKILL.md`

```markdown
---
name: example-minimal
description: Minimal example skill demonstrating required structure
---

## Overview
This is a minimal skill showing the required structure.

## When to Use
Use this as a template for creating new skills.

## Core Patterns

### Pattern 1: Basic Structure
Every skill needs:
- Clear frontmatter with name and description
- Overview section
- When to Use section
- At least one pattern or example

## Examples

### Example 1: Hello World
```python
def hello_world():
    """Minimal example function."""
    return "Hello, World!"
```

## Related Skills
- `skill-template`: Full template with all sections
```

### 13.2 Complete Full Skill

**File**: `skills/example-full/SKILL.md`

```markdown
---
name: example-full
description: Complete example skill with all recommended sections
license: MIT
compatibility: opencode, claude
metadata:
  category: example
  complexity: intermediate
  version: "1.0"
  author: mind-vault
---

## Overview
This is a complete skill demonstrating all recommended sections and best practices.

## When to Use
Use this skill when:
- Creating production-ready skills
- Need comprehensive documentation
- Want to follow all best practices

Do NOT use for:
- Quick prototypes (use minimal template)
- Internal-only skills (use simplified structure)

## Prerequisites

**Knowledge prerequisites**:
- Basic understanding of skill structure
- Familiarity with OpenCode

**Related skills**:
- `example-minimal`: Basic structure
- `skill-template`: Template reference

## Core Patterns

### Pattern 1: Complete Structure
A complete skill includes:
- Comprehensive frontmatter
- All recommended sections
- Multiple examples
- Testing guidance

**Implementation**:
```markdown
---
name: skill-name
description: Description
license: MIT
metadata:
  category: domain
---

[Content sections]
```

**Key points**:
- Use all optional frontmatter fields
- Include metadata for categorization
- Follow consistent structure

### Pattern 2: Code Examples
Every pattern should include:
- Complete, runnable code
- Explanatory comments
- Context and imports

**Implementation**:
```python
# Imports
from typing import List

# Function with full context
def example_function(items: List[str]) -> str:
    """
    Example function with type hints and docstring.
    
    Args:
        items: List of items to process
        
    Returns:
        Processed result
    """
    return ", ".join(items)
```

**Key points**:
- Include type hints
- Add docstrings
- Show complete context

## Examples

### Example 1: Minimal Skill
Creating a minimal skill:

```markdown
---
name: my-skill
description: Brief description
---

## Overview
[Content]

## When to Use
[Criteria]

## Core Patterns
[Patterns]
```

**Explanation**:
- Minimal required frontmatter
- Essential sections only
- Quick to create and maintain

### Example 2: Full Skill
Creating a comprehensive skill:

```markdown
---
name: my-skill
description: Brief description
license: MIT
metadata:
  category: domain
  complexity: intermediate
---

[All sections]
```

**Explanation**:
- Complete frontmatter
- All recommended sections
- Production-ready documentation

## Common Pitfalls

### Pitfall 1: Incomplete Frontmatter
**Problem**: Missing required fields causes loading failures

**Solution**: Always include `name` and `description`

**Example**:
```yaml
# ❌ Wrong: Missing description
---
name: my-skill
---

# ✅ Correct: Both required fields
---
name: my-skill
description: Brief description
---
```

### Pitfall 2: Vague Descriptions
**Problem**: Agent can't select skill correctly

**Solution**: Be specific about what skill does

**Example**:
```yaml
# ❌ Wrong: Too vague
description: Useful patterns

# ✅ Correct: Specific
description: Django multi-tenant patterns with schema-per-tenant isolation
```

## Important Considerations

### Performance
- Keep skills focused (faster loading)
- Avoid redundant content
- Use references for related content

### Maintainability
- Version skills in metadata
- Document changes
- Keep examples up-to-date

### Discoverability
- Use clear, descriptive names
- Write specific descriptions
- Categorize with metadata

## Testing

### Testing Strategy
Test skills by:
1. Validating format with script
2. Loading in OpenCode
3. Verifying agent usage
4. Checking examples work

### Example Test
```bash
# Validate format
./tools/validate-skills.sh example-full

# Test loading
opencode
# Then: skill({ name: "example-full" })

# Verify content
# Check that full content loads correctly
```

## Related Skills

- `example-minimal`: Minimal skill structure
- `skill-template`: Template for new skills
- `django-patterns`: Example domain-specific skill

## References

- [OpenCode Skills Documentation](https://opencode.ai/docs/skills/)
- Internal: `docs/OPENCODE_SKILL_SPECIFICATIONS.md`
- Internal: `docs/OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md`
```

---

## 14. Summary

**Key Takeaways**:

1. **Follow naming rules**: Lowercase, hyphens only, 1-64 chars
2. **Use directory structure**: `skills/<name>/SKILL.md`
3. **Include required frontmatter**: `name` and `description`
4. **Write specific descriptions**: Help agent select correctly
5. **Provide complete examples**: Tested, working code
6. **Validate before committing**: Use validation script
7. **Test in OpenCode**: Verify loading and usage

**Quick Start**:
```bash
# 1. Create skill
mkdir -p skills/my-skill
touch skills/my-skill/SKILL.md

# 2. Add frontmatter and content
# (Use template above)

# 3. Validate
./tools/validate-skills.sh my-skill

# 4. Test
opencode
# Then: skill({ name: "my-skill" })
```

---

**Last Updated**: 2026-01-28  
**Document Version**: 1.0  
**Maintained By**: mind-vault project
