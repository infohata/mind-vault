# AGENTS.md - Coding Guidelines for mind-vault

This guide is for agentic coding assistants (Claude Code, OpenCode) working in this repository.

## Project Overview

**mind-vault** is a centralized configuration, skills, and rules repository for AI agents. It contains:
- **skills/** - Reusable agent skills (SKILL.md files)
- **agents/** - Custom agent definitions (AGENT.md files)
- **rules/** - Shared behavioral rules (RULE.md files)
- **docs/** - Analysis and pattern documentation

This is **not** a typical application - there are no tests, build steps, or runtime execution. Focus is on **clarity, completeness, and reusability**.

## Commands & Workflow

### Git Workflow
```bash
# Check status before any changes
git status

# View recent commits to understand patterns
git log --oneline -10

# Commit changes (follow existing message style)
git add <files>
git commit -m "Describe what was added/changed and why"

# DO NOT push to main - user handles that
```

### No Build/Test/Lint Steps
- This project has no Makefile, pytest, linting, or build pipeline
- There are no tests to run (it's a configuration repository)
- No installation dependencies or virtual environments needed
- Validation happens through code review and documentation clarity

## Code Style & Conventions

### File Organization

**Markdown Files (.md)**
- Use for skill definitions, rules, and pattern documentation
- Maximum ~500 lines per file (split if longer)
- Clear section headings with proper hierarchy (#, ##, ###)
- Include working examples where applicable

**Directory Structure**
```
skills/                          # Reusable agent skills
  ├── django-architecture/       # Core Django patterns
  │   └── SKILL.md
  ├── django-celery/             # Background tasks (single-tenant)
  │   └── SKILL.md
  ├── django-async-websocket/    # WebSocket patterns (single-tenant)
  │   └── SKILL.md
  ├── django-multi-tenant/       # Multi-tenant architecture
  │   └── SKILL.md
  ├── django-celery-multitenant/ # Background tasks (multi-tenant)
  │   └── SKILL.md
  └── django-async-websocket-multitenant/ # WebSocket (multi-tenant)
      └── SKILL.md
agents/          # AGENT.md files - agent specializations
rules/           # RULE.md files - behavioral guidelines
docs/            # Documentation, analysis, patterns
```

### Naming Conventions

**Skills** (in `skills/`)
- Format: `skills/{skill-name}/SKILL.md`
- Example: `skills/django-architecture/SKILL.md`
- Names: kebab-case, descriptive (what problem does it solve?)

**Rules** (in `rules/`)
- Format: `RULE_{NAME}.md`
- Example: `RULE_tool-dependency-guardrails.md`
- Names: kebab-case, action-oriented (what behavior is required?)

**Agents** (in `agents/`)
- Format: `AGENT_{NAME}.md`
- Example: `AGENT_django-specialist.md`
- Names: kebab-case, role-based

**Documentation** (in `docs/`)
- Format: `{PURPOSE}_{DATE_OR_VERSION}.md`
- Example: `TEISUTIS_SCAN.md`, `SESSION_STATE_2026_01_26.md`
- Keep dates in YYYY_MM_DD format

### Markdown Formatting

**Headers & Structure**
```markdown
# Main Title (one per file)
## Major Sections
### Subsections
#### Details (if needed)
```

**Code Examples**
- Use triple backticks with language specification
- Include syntax highlighting: ```python, ```bash, ```markdown
- Show realistic, complete examples
- Comment non-obvious logic

**Lists**
- Use dashes (-) for unordered lists
- Use numbered (1, 2, 3) for sequences
- Use checkboxes (- [ ], - [x]) for status tracking

**Links & References**
- Internal: Use relative paths `[link text](../skills/django-architecture/SKILL.md)`
- External: Full URLs only
- Reference line numbers when helpful: `file.py:45`

### Content Style

**Tone**
- Technical and direct (no fluff)
- Practical - focus on how to use the pattern
- Explain the "why" for non-obvious decisions
- Avoid marketing language

**Structure for Skills/Rules**
1. **What it is** - Clear one-liner definition
2. **When to use it** - Context and applicable scenarios
3. **How it works** - Technical explanation with examples
4. **Why it matters** - Problem it solves, impact
5. **Examples** - Concrete, copy-paste ready code

**Generic Patterns**
- Focus on patterns applicable across projects, not project-specific
- Document why something is generic (applies beyond one use case)
- Note which projects/contexts use this pattern successfully

### Imports & Dependencies

**No Python/JavaScript imports needed** - this is a configuration repository

**Documentation imports** (as references):
- Assume Django knowledge (user background: Django since 2013)
- Reference standard libraries: Django ORM, DRF, Channels
- Link to official docs when helpful

### Error Handling Philosophy

Not applicable to this repository (no code execution). However, when documenting patterns:
- Document common failure modes
- Show defensive programming practices
- Include timeout/fallback handling in examples
- Categorize errors (programming errors vs. runtime errors)

### Comments in Documentation

Use structured comments in code examples:
```python
# Important context - explains the why
data = expensive_operation()

# Warning: Specific danger to avoid
# Never do this in async context without @database_sync_to_async
db_call()

# Fallback behavior - what happens if primary fails
try:
    result = search()
except TimeoutError:
    result = fallback_search()
```

## Documentation Standards

### SKILL.md Template
```markdown
# SKILL_{Name}

## Overview
One-paragraph summary.

## When to Use
Specific scenarios where this applies.

## Pattern
Explanation of how to implement, with code examples.

## Why It's Generic
Why this applies across projects (not project-specific).

## Example Use Cases
List of projects/contexts using this pattern.

## References
Links to related documentation.
```

### RULE.md Template
```markdown
# RULE_{Name}

## Principle
Core behavioral principle in one sentence.

## Details
Multi-paragraph explanation of what this rule covers.

## Examples
✅ DO - correct implementation
❌ DON'T - incorrect implementation

## Why This Matters
Context and impact of following this rule.
```

### Documentation Files (docs/)
Include metadata at top:
```markdown
# {Title}

**Purpose**: One-line description  
**Date**: YYYY-MM-DD  
**Status**: Ready/In Progress/Archive  
**Applies To**: mind-vault / specific projects
```

## Guardrails & Critical Rules

### Git Safety
- ✅ DO: Make focused commits with clear messages
- ❌ DON'T: Commit credentials, API keys, or .env files
- ❌ DON'T: Force push to main
- ❌ DON'T: Rewrite history on shared branches

### Content Safety
- ✅ DO: Focus on reusable, generic patterns
- ❌ DON'T: Include project-specific code (unless as case study)
- ❌ DON'T: Reference private/confidential information
- ❌ DON'T: Document patterns not yet validated in production

### Documentation Quality
- ✅ DO: Include working examples
- ✅ DO: Explain the "why" not just the "how"
- ✅ DO: Keep files focused (split if >500 lines)
- ❌ DON'T: Leave TODO comments in final files
- ❌ DON'T: Include incomplete patterns

## File Operations

**Creating Files**
1. Use full paths: `/home/kestas/projects/mind-vault/...`
2. Place in appropriate directory (skills/, agents/, rules/, docs/)
3. Follow naming conventions above
4. Include proper header with metadata

**Editing Files**
1. Read file first to understand context
2. Make focused edits (don't rewrite entire sections)
3. Preserve formatting and structure
4. Keep files aligned with template style

**Deleting Files**
- Rare - prefer archiving old docs with note at top
- Update references when removing files

## User Context & Preferences

**User Background**
- Python/Django expertise since 2013
- Previously C/C++, now interested in C++/Rust with AI help
- Values pragmatism over perfection
- Loves Django ORM and DRF

**Operational Preferences**
- Direct communication, no marketing fluff
- Technical depth welcome
- Docker Compose for everything (no bare docker)
- Makefile enthusiast (but this project doesn't need one)
- Values production parity in local development

## Quality Checklist

Before finishing work on skills/rules/documentation:

- [ ] File follows naming convention (subdirs with SKILL.md, RULE_, AGENT_, or proper doc format)
- [ ] Content is placed in correct directory
- [ ] Metadata/header is present (for docs)
- [ ] Content is generic and reusable (not project-specific)
- [ ] All code examples are complete and tested-in-thought
- [ ] Links are relative paths or full URLs
- [ ] No credentials, API keys, or secrets included
- [ ] Clear explanation of why this pattern matters
- [ ] **Rule Enforcement**: Run `/load-rules` command at session start and after compaction to enforce active rules

## Agent Roles

Agent roles define specialization and focus areas when working in mind-vault. See individual role files in `agents/` directory:

- [`researcher.md`](agents/researcher.md) - Pattern extraction and analysis
- [`architect.md`](agents/architect.md) - Backend/technical design and validation
- [`frontend.md`](agents/frontend.md) - Frontend/UX patterns and components
- [`documentation.md`](agents/documentation.md) - Documentation quality (shared responsibility)
- [`test-engineer.md`](agents/test-engineer.md) - Edge case and completeness validation
- [`curator.md`](agents/curator.md) - Quality gates and consistency
- [`devops.md`](agents/devops.md) - Deployment and operations patterns

## Next Steps

For agents extending this repository:
1. Check existing files for related patterns (avoid duplication)
2. Follow naming and format conventions strictly
3. Focus on reusability and clarity
4. Document patterns already validated in production
5. Get user confirmation before committing changes

---

**Last Updated**: 2026-01-26  
**Repository**: https://github.com/infohata/mind-vault  
**Symlinks**: `~/.claude/skills`, `~/.config/opencode/skills`, `~/.config/opencode/commands`
