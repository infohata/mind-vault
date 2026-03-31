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

**CRITICAL**: All git operations follow `rules/RULE_git-safety.md`

Key requirements:
- Work on feature branches only (never commit to main)
- Show diff and ask approval BEFORE every commit
- Never merge (user merges on GitHub)

See [`rules/RULE_git-safety.md`](rules/RULE_git-safety.md) for full details.

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
  ├── django/                    # Modular Django skill (NEW)
  │   ├── SKILL.md               # Core architecture patterns
  │   ├── references/            # Specialized patterns (load on-demand)
  │   │   ├── MULTI_TENANT.md
  │   │   ├── ASYNC_WEBSOCKET.md
  │   │   ├── CELERY.md
  │   │   ├── MULTI_TENANT_ASYNC.md
  │   │   └── MULTI_TENANT_CELERY.md
  │   ├── scripts/               # Automation helpers
  │   └── assets/                # Templates and diagrams
  ├── _archived/                 # Archived skills (old versions)
  │   ├── django-architecture/
  │   ├── django-async-websocket/
  │   ├── django-celery/
  │   ├── django-multi-tenant/
  │   ├── django-celery-multitenant/
  │   └── django-async-websocket-multitenant/
agents/          # AGENT.md files - agent specializations
rules/           # RULE.md files - behavioral guidelines
docs/            # Documentation, analysis, patterns
```

### Naming Conventions

**Skills** (in `skills/`)
- Format: `skills/{skill-name}/SKILL.md`
- Example: `skills/django/SKILL.md`
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
- Internal: Use relative paths `[link text](../skills/django/SKILL.md)`
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

### Git Safety (RULE_git-safety.md)

**The 3 Hard Rules:**
1. ⛔ NEVER COMMIT TO MAIN - Work on feature branches only
2. ⛔ NEVER COMMIT WITHOUT APPROVAL - Show diff, ask "Should I commit?", wait for "yes" in THIS response
3. ⛔ NEVER MERGE - User merges on GitHub, agent never runs `git merge`

**Additional:**
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

### Context Compaction Handling

**When context compaction occurs:**
1. PAUSE immediately after compaction completes
2. State what you were working on before compaction
3. Confirm critical rules are still active (especially git safety)
4. Ask user if you should continue or if they want to adjust approach

**Why this matters:**
- Compaction can dilute rule awareness
- User needs opportunity to intervene before you continue
- Prevents rule violations that happen mid-task

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

## Updating skills from project work

When work in **other projects** (e.g. Teisutis) yields reusable patterns (formset abstractions, date/time handling, frontend conventions), update **generic** mind-vault skills so all projects benefit.

**When to update** (same bar as creating a skill):
- Pattern is reusable across projects; you’d reference it again; not project-specific.
- Don’t add one-off fixes or project-only conventions (those stay in the project’s AGENTS.md).

**What to update**:
- **Fits existing skill** (e.g. django, django-frontend) → Edit that skill: add a short section or bullet.
- **New cross-project technique** → Extend the relevant skill or create a new one only if it’s a new category.
- **Project-specific** → Do not add to generic skills.

**Where**: Edit in this repo (`skills/`, `rules/`). Projects symlink from here (e.g. `~/.cursor/skills/`, `~/.claude/rules/`). **Subagents in other projects must not write here** — only the main agent or user updates mind-vault.

**Format**: Follow SKILL.md template and content style; keep content generic (no project names except as examples).

**Workflow**: (1) Note patterns that were non-obvious and reusable. (2) Decide: existing skill vs new skill. (3) Edit in mind-vault; keep changes small and generic. (4) Commit so symlinked Cursor/Claude skills stay in sync.

---

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
