# OpenCode Skills Analysis - Summary

**Purpose**: Executive summary of OpenCode skill system analysis  
**Date**: 2026-01-28  
**Status**: Ready  
**Applies To**: mind-vault skill development strategy

---

## Overview

This document summarizes the comprehensive analysis of OpenCode's skill system, conducted to inform mind-vault's skill development strategy and ensure cross-platform compatibility with Claude Code.

---

## Key Findings

### 1. Core Architecture Differences

**OpenCode uses on-demand loading**:
- Skills listed in tool description (name + description only)
- Agent explicitly loads skills when needed: `skill({ name: "skill-name" })`
- Reduces initial context size
- Scales well with large skill libraries (100+ skills)

**Claude Code uses session-start loading**:
- All skills loaded into context at session start
- Agent has immediate access to all skills
- Better for small, frequently-used skill sets
- May impact context size with many skills

**Implication**: Design skills for OpenCode's stricter requirements to ensure compatibility with both platforms.

### 2. Strict Validation Requirements

**OpenCode enforces**:
- Name format: `^[a-z0-9]+(-[a-z0-9]+)*$` (lowercase, single hyphens only)
- Directory structure: `skills/<name>/SKILL.md` (exact case)
- Frontmatter: Required `name` and `description` fields
- Description length: 1-1024 characters (strictly enforced)
- Directory name must match frontmatter `name` field

**Claude Code is more flexible**:
- Accepts various naming formats
- Supports single files or directories
- Frontmatter often optional
- Less strict validation

**Implication**: Use OpenCode naming and structure for maximum compatibility.

### 3. Permission System

**OpenCode provides granular control**:
- Three levels: `allow`, `ask`, `deny`
- Pattern-based matching with wildcards
- Per-agent permission overrides
- Skills with `deny` hidden from agent entirely

**Claude Code has limited permissions**:
- Often all-or-nothing (skills enabled or disabled)
- May rely on file system permissions
- Less granular control

**Implication**: Configure OpenCode permissions for fine-grained control; organize skills by trust level for Claude Code.

---

## Recommendations for mind-vault

### 1. File Structure

**Use OpenCode-compatible structure**:
```
skills/
├── django/
│   └── SKILL.md
├── django-multi-tenant/
│   └── SKILL.md
├── django-async-websocket/
│   └── SKILL.md
└── error-handling-async/
    └── SKILL.md
```

**Place in `.claude/skills/`** for maximum compatibility with both platforms.

### 2. Naming Strategy

**Follow OpenCode naming rules**:
- Lowercase only
- Single hyphens as separators
- Domain prefixes: `django-*`, `git-*`, `error-handling-*`
- Descriptive but concise (1-64 chars)

**Examples**:
```
✅ django-multi-tenant
✅ error-handling-async
✅ git-workflow

❌ Django-MultiTenant
❌ error_handling_async
❌ git workflow
```

### 3. Frontmatter Template

**Always include**:
```yaml
---
name: skill-name
description: Specific, actionable description (100-200 chars)
license: MIT
compatibility: opencode, claude
metadata:
  category: domain
  complexity: intermediate
  version: "1.0"
---
```

### 4. Content Structure

**Use consistent template**:
```markdown
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
[Explanation and code]

### Pattern 2: Name
[Explanation and code]

## Examples
### Example 1: Scenario
[Complete, tested code]

## Common Pitfalls
### Pitfall 1: Description
[Problem and solution]

## Important Considerations
- Performance notes
- Security considerations
- Scalability implications

## Related Skills
- `related-skill`: Relationship description
```

### 5. Validation Workflow

**Before committing**:
1. Run validation script: `./tools/validate-skills.sh skill-name`
2. Test loading in OpenCode: `skill({ name: "skill-name" })`
3. Verify agent follows patterns correctly
4. Test in Claude Code (if available)
5. Check permissions work as expected

### 6. Permission Configuration

**In `opencode.json`**:
```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "experimental-*": "ask",
      "deprecated-*": "deny"
    }
  }
}
```

---

## Documentation Deliverables

### 1. OPENCODE_SKILL_SPECIFICATIONS.md
**Comprehensive technical specifications**:
- File structure and discovery
- Frontmatter specification
- Name validation rules
- On-demand loading mechanism
- Permission system
- Integration with OpenCode ecosystem
- Troubleshooting guide
- Comparison with Claude Code

**Use for**: Understanding OpenCode skill system in depth, validating skills against specifications.

### 2. OPENCODE_VS_CLAUDE_SKILLS.md
**Cross-platform compatibility analysis**:
- Core architecture differences
- Naming and validation comparison
- Frontmatter differences
- Permission systems
- Content structure
- Loading and invocation
- Migration strategies
- Dual compatibility best practices

**Use for**: Maintaining compatibility with both OpenCode and Claude Code, migration planning.

### 3. OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md
**Practical implementation guide**:
- Quick start (5 steps)
- Naming guidelines
- Directory structure
- Frontmatter templates
- Content structure templates
- Code example standards
- Validation and testing
- Common patterns
- Troubleshooting

**Use for**: Day-to-day skill creation, reference during development, onboarding new contributors.

### 4. OPENCODE_ANALYSIS_SUMMARY.md (this document)
**Executive summary**:
- Key findings
- Recommendations
- Documentation overview
- Next steps

**Use for**: Quick reference, strategic planning, communicating findings.

---

## Implementation Roadmap

### Phase 1: Validation (Immediate)
- [ ] Create validation script: `tools/validate-skills.sh`
- [ ] Validate existing skills against OpenCode requirements
- [ ] Fix any naming or structure issues
- [ ] Test loading in OpenCode (if available)

### Phase 2: Standardization (Short-term)
- [ ] Update all skills to use consistent frontmatter
- [ ] Ensure all skills follow content template
- [ ] Add metadata for categorization
- [ ] Update code examples to be complete and tested

### Phase 3: Enhancement (Medium-term)
- [ ] Configure OpenCode permissions in `opencode.json`
- [ ] Create skill templates for common patterns
- [ ] Document skill composition patterns
- [ ] Add testing strategies for skills

### Phase 4: Optimization (Long-term)
- [ ] Analyze skill usage patterns (if metrics available)
- [ ] Consolidate or split skills based on usage
- [ ] Create advanced skill composition patterns
- [ ] Develop automated testing for skills

---

## Validation Script

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
NC='\033[0m'

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

# Validate single skill
./tools/validate-skills.sh django-multi-tenant

# Validate all skills
for skill in skills/*/; do
  skill_name=$(basename "$skill")
  ./tools/validate-skills.sh "$skill_name"
done
```

---

## Quick Reference

### Skill Creation Checklist
- [ ] Name follows regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- [ ] Directory: `skills/<name>/SKILL.md`
- [ ] Frontmatter includes `name` and `description`
- [ ] Description is specific (100-200 chars)
- [ ] Content follows template structure
- [ ] Code examples are complete and tested
- [ ] Validation script passes
- [ ] Tested in OpenCode (if available)

### Common Commands
```bash
# Create skill
mkdir -p skills/skill-name
touch skills/skill-name/SKILL.md

# Validate
./tools/validate-skills.sh skill-name

# Test in OpenCode
opencode
# Then: skill({ name: "skill-name" })
```

### Name Validation Regex
```regex
^[a-z0-9]+(-[a-z0-9]+)*$
```

---

## Next Steps

### Immediate Actions
1. **Create validation script**: Implement `tools/validate-skills.sh`
2. **Validate existing skills**: Run validation on all current skills
3. **Fix issues**: Update any skills that don't meet OpenCode requirements
4. **Document process**: Update AGENTS.md with skill creation workflow

### Short-term Actions
1. **Standardize frontmatter**: Ensure all skills use consistent metadata
2. **Update content**: Apply template structure to all skills
3. **Test loading**: Verify skills load correctly in OpenCode (if available)
4. **Configure permissions**: Set up `opencode.json` with skill permissions

### Long-term Actions
1. **Monitor usage**: Track which skills are used most frequently
2. **Optimize library**: Consolidate or split skills based on usage patterns
3. **Enhance documentation**: Add more examples and use cases
4. **Automate testing**: Create automated tests for skill validation

---

## Key Takeaways

1. **OpenCode is stricter than Claude Code**: Design for OpenCode requirements to ensure compatibility with both platforms.

2. **On-demand loading changes skill design**: Write specific descriptions and self-contained skills that work standalone.

3. **Validation is critical**: Use validation script before committing to catch issues early.

4. **Structure matters**: Directory structure and file naming are strictly enforced in OpenCode.

5. **Permissions provide control**: Use OpenCode's granular permissions for fine-grained access control.

6. **Cross-platform compatibility is achievable**: Following OpenCode requirements ensures skills work in both platforms.

---

## Resources

**Documentation**:
- `docs/OPENCODE_SKILL_SPECIFICATIONS.md`: Technical specifications
- `docs/OPENCODE_VS_CLAUDE_SKILLS.md`: Cross-platform comparison
- `docs/OPENCODE_SKILL_IMPLEMENTATION_GUIDE.md`: Practical guide
- `docs/OPENCODE_ANALYSIS_SUMMARY.md`: This document

**External References**:
- OpenCode Skills: https://opencode.ai/docs/skills/
- OpenCode Agents: https://opencode.ai/docs/agents/
- OpenCode Permissions: https://opencode.ai/docs/permissions/

**Tools**:
- `tools/validate-skills.sh`: Skill validation script
- Name regex tester: https://regex101.com/

---

## Conclusion

The OpenCode skill system provides a robust, scalable approach to agent customization with strict validation and on-demand loading. By following OpenCode's requirements, mind-vault can maintain a high-quality skill library that works seamlessly across both OpenCode and Claude Code platforms.

The key to success is:
1. **Strict adherence to naming and structure requirements**
2. **Comprehensive validation before committing**
3. **Clear, specific descriptions for agent selection**
4. **Self-contained, well-documented skills**
5. **Regular testing in both platforms**

With these practices in place, mind-vault can build a robust, maintainable skill library that serves as a valuable resource for AI-assisted development across multiple platforms.

---

**Last Updated**: 2026-01-28  
**Analysis Conducted By**: Researcher Agent  
**Document Version**: 1.0  
**Status**: Complete
