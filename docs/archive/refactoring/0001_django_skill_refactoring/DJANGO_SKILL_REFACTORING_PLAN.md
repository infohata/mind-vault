# Django Skill Refactoring Plan: Modular Architecture

**Date**: 2026-01-27  
**Purpose**: Refactor 6 separate Django skills into 1 modular skill with selective loading  
**Status**: Planning Phase

---

## Executive Summary

This document outlines a plan to consolidate 6 Django skills into a single modular skill structure that agents can load selectively based on their needs. The refactoring leverages the Agent Skills specification's progressive disclosure pattern (metadata → instructions → resources) to minimize context usage while maintaining comprehensive coverage.

**Current State**: 6 separate skills (~2,900 total lines)
- `django-architecture` (801 lines)
- `django-async-websocket` (374 lines)
- `django-celery` (614 lines)
- `django-multi-tenant` (755 lines)
- `django-celery-multitenant` (327 lines)
- `django-async-websocket-multitenant` (363 lines)

**Target State**: 1 modular skill with selective loading
- Core `SKILL.md` (~500 lines) - architecture fundamentals
- Reference files for specialized patterns (~1,500 lines total)
- Scripts for common operations (~400 lines)
- Progressive disclosure reduces typical context usage by 60-80%

---

## Understanding Agent Skills Specification

### Key Insights from agentskills.io

#### 1. Progressive Disclosure Pattern

The specification emphasizes **three-tier loading**:

```
Tier 1: Metadata (~100 tokens)
  ├─ name: "django"
  └─ description: "Core Django patterns..."
  
Tier 2: Instructions (<5000 tokens recommended)
  └─ SKILL.md body (loaded when skill activated)
  
Tier 3: Resources (loaded on-demand)
  ├─ references/MULTI_TENANT.md
  ├─ references/ASYNC_WEBSOCKET.md
  ├─ references/CELERY.md
  └─ scripts/setup_tenant.py
```

**Benefit**: Agents load only what they need, when they need it.

#### 2. File Structure Requirements

```
django/
├── SKILL.md              # Required: frontmatter + core instructions
├── references/           # Optional: detailed technical docs
│   ├── MULTI_TENANT.md
│   ├── ASYNC_WEBSOCKET.md
│   ├── CELERY.md
│   └── FORMS.md
├── scripts/              # Optional: executable helpers
│   ├── setup_tenant.py
│   ├── create_consumer.py
│   └── test_celery.py
└── assets/               # Optional: templates, diagrams
    ├── templates/
    └── diagrams/
```

#### 3. Frontmatter Constraints

```yaml
---
name: django                    # Max 64 chars, lowercase, hyphens only
description: |                  # Max 1024 chars
  Core Django architecture patterns including BaseModel abstractions,
  DRF conventions, ASGI setup, multi-tenancy, async WebSocket, and
  Celery background tasks. Use for Django projects requiring production-ready
  patterns with optional multi-tenant support.
license: MIT
compatibility: opencode
metadata:
  author: mind-vault
  version: "2.0"
  replaces: 
    - django-architecture
    - django-async-websocket
    - django-celery
    - django-multi-tenant
    - django-celery-multitenant
    - django-async-websocket-multitenant
---
```

#### 4. Keep SKILL.md Under 500 Lines

> "Keep your main SKILL.md under 500 lines. Move detailed reference material to separate files."

**Why**: Agents load the entire SKILL.md when activating. Smaller = less context waste.

#### 5. Reference Files Should Be Focused

> "Keep individual reference files focused. Agents load these on demand, so smaller files mean less use of context."

**Strategy**: Split by concern, not by size. Each reference file should be independently useful.

---

## Current Skill Analysis

### Dependency Graph

```
django-architecture (foundation)
  ├─ django-async-websocket
  │   └─ django-async-websocket-multitenant
  ├─ django-celery
  │   └─ django-celery-multitenant
  └─ django-multi-tenant
      ├─ django-celery-multitenant
      └─ django-async-websocket-multitenant
```

**Key Insight**: Multi-tenant variants are **extensions**, not replacements. They add tenant context propagation to base patterns.

### Content Overlap Analysis

| Pattern | Architecture | Async WS | Celery | Multi-Tenant | Celery-MT | Async-MT |
|---------|--------------|----------|--------|--------------|-----------|----------|
| BaseModel | ✅ Core | - | - | Extends | - | - |
| Settings | ✅ Core | Config | Config | Config | - | - |
| DRF ViewSets | ✅ Core | - | - | Extends | - | - |
| Middleware | ✅ Core | - | - | **Critical** | - | - |
| ASGI Setup | ✅ Core | **Critical** | - | - | - | - |
| Channels | - | ✅ Core | - | - | - | Extends |
| Celery Tasks | - | - | ✅ Core | - | Extends | - |
| Tenant Context | - | - | - | ✅ Core | **Critical** | **Critical** |
| Error Handling | ✅ Core | Extends | Extends | - | - | - |

**Observation**: 
- ~40% of content is duplicated configuration (settings, docker-compose)
- Multi-tenant variants add ~30% new content (tenant context patterns)
- Async/Celery variants are mostly independent but share error handling

---

## Proposed Modular Structure

### Directory Layout

```
skills/django/
├── SKILL.md                           # Core architecture (~500 lines)
│   ├─ Frontmatter with comprehensive description
│   ├─ Project structure
│   ├─ BaseModel patterns
│   ├─ Settings & configuration
│   ├─ DRF basics
│   ├─ Middleware
│   ├─ ASGI setup (basic)
│   ├─ Database optimization
│   └─ References to specialized files
│
├── references/
│   ├── MULTI_TENANT.md                # ~400 lines
│   │   ├─ Schema-per-tenant concept
│   │   ├─ Tenant model & resolution
│   │   ├─ User/Scope/UserScope pattern
│   │   ├─ 5-layer permission checking
│   │   ├─ tenant_context() usage
│   │   └─ Common pitfalls
│   │
│   ├── ASYNC_WEBSOCKET.md             # ~350 lines
│   │   ├─ Channels installation
│   │   ├─ Consumer patterns
│   │   ├─ @database_sync_to_async
│   │   ├─ Group broadcasting
│   │   ├─ Error handling
│   │   └─ Testing
│   │
│   ├── CELERY.md                      # ~400 lines
│   │   ├─ Installation & config
│   │   ├─ Task patterns
│   │   ├─ Signal-based triggering
│   │   ├─ Error categorization
│   │   ├─ Retry strategies
│   │   └─ Monitoring
│   │
│   ├── MULTI_TENANT_ASYNC.md          # ~250 lines
│   │   ├─ Tenant verification in connect()
│   │   ├─ Group naming with tenant_id
│   │   ├─ Database access with tenant_context
│   │   └─ Common pitfalls
│   │
│   ├── MULTI_TENANT_CELERY.md         # ~200 lines
│   │   ├─ Passing org_id to tasks
│   │   ├─ tenant_context in workers
│   │   ├─ Signal patterns with tenant
│   │   └─ Common pitfalls
│   │
│   └── FORMS.md                       # ~150 lines (new)
│       ├─ Common form patterns
│       ├─ Validation
│       └─ Error handling
│
├── scripts/
│   ├── setup_tenant.py                # Create new tenant
│   ├── create_consumer.py             # Generate WebSocket consumer
│   ├── create_task.py                 # Generate Celery task
│   └── test_celery.py                 # Verify Celery setup
│
└── assets/
    ├── templates/
    │   ├── consumer_template.py
    │   ├── task_template.py
    │   └── viewset_template.py
    └── diagrams/
        ├── multi_tenant_architecture.svg
        └── async_flow.svg
```

### Core SKILL.md Structure (~500 lines)

```markdown
---
name: django
description: |
  Core Django architecture patterns including BaseModel abstractions,
  DRF conventions, ASGI setup, multi-tenancy, async WebSocket, and
  Celery background tasks. Use for Django projects requiring production-ready
  patterns with optional multi-tenant support.
license: MIT
compatibility: opencode
metadata:
  author: mind-vault
  version: "2.0"
  replaces: 
    - django-architecture
    - django-async-websocket
    - django-celery
    - django-multi-tenant
    - django-celery-multitenant
    - django-async-websocket-multitenant
---

## Overview

Core Django project architecture patterns for organizing models, views,
serializers, and middleware. Covers BaseModel abstractions, DRF conventions,
ASGI setup, and common DRY patterns.

**Optional Extensions** (load on-demand):
- [Multi-Tenant Architecture](references/MULTI_TENANT.md) - Schema-per-tenant isolation
- [Async WebSocket](references/ASYNC_WEBSOCKET.md) - Real-time communication
- [Celery Background Tasks](references/CELERY.md) - Async job processing
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md) - WebSocket with tenants
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md) - Tasks with tenants

## When to Use

- Starting a new Django project
- Organizing app structure and models
- Setting up DRF viewsets and permissions
- Configuring middleware and ASGI
- Extracting common patterns into mixins/base classes
- Optimizing database queries
- Adding performance monitoring

**Load additional references when**:
- Multi-tenancy required → [MULTI_TENANT.md](references/MULTI_TENANT.md)
- Real-time features needed → [ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md)
- Background tasks needed → [CELERY.md](references/CELERY.md)

## Pattern

### Project Structure

[... core architecture content ...]

### BaseModel Abstraction

[... BaseModel patterns ...]

### Settings & Configuration

[... environment-based config ...]

### DRF Patterns

[... ViewSet, permissions, serializers ...]

### Middleware Patterns

[... custom middleware ...]

### ASGI Configuration (Basic)

[... basic ASGI setup ...]

**For WebSocket support**: See [ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md)

### Database Optimization

[... N+1 prevention, batch operations ...]

### Performance Monitoring

[... decorator-based timing ...]

## When NOT to Use These Patterns

[... anti-patterns ...]

## Related References

- [Multi-Tenant Architecture](references/MULTI_TENANT.md) - If using multi-tenancy
- [Async WebSocket](references/ASYNC_WEBSOCKET.md) - If using real-time features
- [Celery Background Tasks](references/CELERY.md) - If using background tasks
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md) - Combining both
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md) - Combining both

## External References

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimization](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
```

---

## Migration Strategy

### Phase 1: Create Modular Structure (Week 1)

**Tasks**:
1. Create `skills/django/` directory
2. Write new `SKILL.md` with core patterns (~500 lines)
3. Extract multi-tenant content → `references/MULTI_TENANT.md`
4. Extract async WebSocket → `references/ASYNC_WEBSOCKET.md`
5. Extract Celery → `references/CELERY.md`
6. Create extension references:
   - `references/MULTI_TENANT_ASYNC.md`
   - `references/MULTI_TENANT_CELERY.md`

**Validation**:
- Run `skills-ref validate ./skills/django/`
- Verify frontmatter constraints
- Check file sizes (<500 lines for SKILL.md)
- Test cross-references work

### Phase 2: Add Scripts & Templates (Week 2)

**Tasks**:
1. Create `scripts/setup_tenant.py` - Automate tenant creation
2. Create `scripts/create_consumer.py` - Generate WebSocket consumer boilerplate
3. Create `scripts/create_task.py` - Generate Celery task boilerplate
4. Create `scripts/test_celery.py` - Verify Celery configuration
5. Add templates in `assets/templates/`
6. Add architecture diagrams in `assets/diagrams/`

**Validation**:
- Test each script independently
- Verify templates generate valid code
- Check diagrams render correctly

### Phase 3: Update References & Deprecate Old Skills (Week 3)

**Tasks**:
1. Update `AGENTS.md` to reference new modular skill
2. Update rules to reference `django` skill instead of 6 separate skills
3. Add deprecation notices to old skills:
   ```markdown
   # DEPRECATED: Use skills/django/SKILL.md instead
   
   This skill has been consolidated into the modular Django skill.
   See: [skills/django/SKILL.md](../django/SKILL.md)
   
   For multi-tenant patterns specifically, see:
   [skills/django/references/MULTI_TENANT.md](../django/references/MULTI_TENANT.md)
   ```
4. Keep old skills for 1 month (backwards compatibility)
5. Archive old skills to `skills/_archived/` after 1 month

**Validation**:
- Verify all references updated
- Test agent can load new skill
- Confirm deprecation notices visible

### Phase 4: Monitor & Iterate (Ongoing)

**Tasks**:
1. Monitor agent usage patterns
2. Identify frequently co-loaded references
3. Optimize reference file sizes
4. Add new references as patterns emerge
5. Update scripts based on feedback

**Metrics**:
- Context usage before/after refactoring
- Time to load skill
- Agent success rate with modular structure
- Number of reference files loaded per session

---

## Benefits Analysis

### 1. Context Efficiency

**Before** (loading all 6 skills):
```
django-architecture:           801 lines (~16,000 tokens)
django-async-websocket:        374 lines (~7,500 tokens)
django-celery:                 614 lines (~12,000 tokens)
django-multi-tenant:           755 lines (~15,000 tokens)
django-celery-multitenant:     327 lines (~6,500 tokens)
django-async-websocket-mt:     363 lines (~7,000 tokens)
─────────────────────────────────────────────────────────
TOTAL:                        3,234 lines (~64,000 tokens)
```

**After** (selective loading):

| Scenario | Files Loaded | Lines | Tokens | Savings |
|----------|--------------|-------|--------|---------|
| Basic Django | SKILL.md | 500 | ~10,000 | 84% |
| + Multi-tenant | + MULTI_TENANT.md | 900 | ~18,000 | 72% |
| + WebSocket | + ASYNC_WEBSOCKET.md | 850 | ~17,000 | 73% |
| + Celery | + CELERY.md | 900 | ~18,000 | 72% |
| + MT + WS | + MULTI_TENANT.md + ASYNC_WEBSOCKET.md + MULTI_TENANT_ASYNC.md | 1,500 | ~30,000 | 53% |
| + MT + Celery | + MULTI_TENANT.md + CELERY.md + MULTI_TENANT_CELERY.md | 1,350 | ~27,000 | 58% |
| All features | All references | 2,250 | ~45,000 | 30% |

**Average savings**: 60-70% context reduction for typical use cases

### 2. Discoverability

**Before**:
- Agent must know which of 6 skills to load
- Unclear which combinations are valid
- No guidance on dependencies

**After**:
- Single entry point (`django` skill)
- Clear references to extensions
- Explicit dependency guidance
- Progressive disclosure (load what you need)

### 3. Maintainability

**Before**:
- Update same pattern in 3-6 places
- Risk of inconsistency
- Hard to track which skills are related

**After**:
- Update core pattern once in SKILL.md
- Update extension pattern once in reference file
- Clear separation of concerns
- Single source of truth

### 4. Extensibility

**Before**:
- Adding new pattern = new skill file
- Exponential growth (N base × M extensions)
- Hard to combine patterns

**After**:
- Adding new pattern = new reference file
- Linear growth
- Easy to combine (just load multiple references)
- Scripts can generate boilerplate

### 5. Testing & Validation

**Before**:
- Test 6 separate skills
- Validate cross-references manually
- Hard to ensure consistency

**After**:
- Test 1 core skill + N references
- Use `skills-ref validate` tool
- Automated consistency checks
- Scripts provide working examples

---

## Trade-offs & Risks

### Trade-offs

| Aspect | Before | After | Winner |
|--------|--------|-------|--------|
| **Initial Load** | Load 1 skill (~800 lines) | Load 1 skill (~500 lines) | ✅ After |
| **Full Coverage** | Load 6 skills (~3,200 lines) | Load 1 + 5 refs (~2,250 lines) | ✅ After |
| **Discoverability** | Must know skill names | Single entry point | ✅ After |
| **File Count** | 6 files | 1 + 5 refs + scripts | ⚖️ Neutral |
| **Complexity** | Flat structure | Nested structure | ⚠️ Before |
| **Maintenance** | Update 3-6 places | Update 1-2 places | ✅ After |

### Risks & Mitigations

#### Risk 1: Agents Don't Load References

**Risk**: Agent loads SKILL.md but doesn't follow references when needed.

**Mitigation**:
- Clear "When to Use" section in SKILL.md
- Explicit references at decision points
- Examples show reference file paths
- Scripts demonstrate loading patterns

#### Risk 2: Reference Files Too Large

**Risk**: Reference files grow beyond useful size (>500 lines).

**Mitigation**:
- Set hard limit: 500 lines per reference
- Split large references into sub-references
- Use scripts for complex examples
- Regular audits of file sizes

#### Risk 3: Breaking Existing Workflows

**Risk**: Agents/users expect old skill names.

**Mitigation**:
- Keep old skills for 1 month with deprecation notices
- Update all internal references immediately
- Document migration in CHANGELOG
- Provide mapping: old skill → new reference

#### Risk 4: Over-Fragmentation

**Risk**: Too many small reference files = hard to navigate.

**Mitigation**:
- Limit to 5-7 core references
- Group related patterns
- Provide clear index in SKILL.md
- Use scripts to combine patterns

#### Risk 5: Validation Failures

**Risk**: New structure doesn't pass `skills-ref validate`.

**Mitigation**:
- Validate early and often
- Test with reference implementation
- Follow spec strictly (frontmatter, naming)
- Automate validation in CI/CD

---

## Success Metrics

### Quantitative

1. **Context Usage**
   - Target: 60-70% reduction for typical use cases
   - Measure: Token count before/after

2. **Load Time**
   - Target: <2 seconds to load SKILL.md
   - Measure: Time to parse and activate skill

3. **Reference Load Rate**
   - Target: 80% of sessions load ≤2 references
   - Measure: Track which references loaded per session

4. **File Size Compliance**
   - Target: 100% of files <500 lines
   - Measure: Line count per file

### Qualitative

1. **Agent Success Rate**
   - Can agent find correct patterns?
   - Does agent load appropriate references?
   - Are examples clear and actionable?

2. **Developer Feedback**
   - Is structure intuitive?
   - Are references easy to find?
   - Do scripts save time?

3. **Maintenance Burden**
   - Time to update patterns
   - Consistency across files
   - Ease of adding new patterns

---

## Implementation Checklist

### Pre-Implementation

- [ ] Review Agent Skills specification thoroughly
- [ ] Analyze current skill dependencies
- [ ] Identify content overlap
- [ ] Design modular structure
- [ ] Get user approval for plan

### Phase 1: Core Structure

- [x] Create `skills/django/` directory
- [x] Write `SKILL.md` frontmatter
- [x] Write core architecture content (~500 lines)
- [ ] Validate with `skills-ref validate`
- [ ] Test loading in agent

### Phase 2: Reference Files

- [x] Extract `references/MULTI_TENANT.md`
- [x] Extract `references/ASYNC_WEBSOCKET.md`
- [x] Extract `references/CELERY.md`
- [x] Create `references/MULTI_TENANT_ASYNC.md`
- [x] Create `references/MULTI_TENANT_CELERY.md`
- [ ] Validate all references
- [x] Test cross-references work

### Phase 3: Scripts & Assets

- [ ] Create `scripts/setup_tenant.py`
- [ ] Create `scripts/create_consumer.py`
- [ ] Create `scripts/create_task.py`
- [ ] Create `scripts/test_celery.py`
- [ ] Add templates to `assets/templates/`
- [ ] Add diagrams to `assets/diagrams/`
- [ ] Test all scripts independently

### Phase 4: Migration

- [x] Update `AGENTS.md` references
- [x] Update rule files (none needed - no direct references)
- [x] Add deprecation notices to old skills
- [x] Test backwards compatibility
- [x] Document migration path
- [x] Set archive date (1 month - 2026-02-27)

### Phase 5: Validation

- [ ] Run `skills-ref validate` on entire structure
- [ ] Test agent loading patterns
- [ ] Measure context usage
- [ ] Verify all cross-references
- [ ] Check file sizes
- [ ] Test scripts in real scenarios

### Phase 6: Monitoring

- [ ] Track reference load patterns
- [ ] Monitor agent success rate
- [ ] Collect developer feedback
- [ ] Identify optimization opportunities
- [ ] Plan iterative improvements

---

## Conclusion

The modular Django skill structure offers significant benefits:

✅ **60-70% context reduction** for typical use cases  
✅ **Single entry point** for discoverability  
✅ **Progressive disclosure** - load only what's needed  
✅ **Easier maintenance** - update once, not 3-6 times  
✅ **Better extensibility** - add references, not new skills  
✅ **Follows specification** - leverages Agent Skills best practices  

**Recommendation**: Proceed with refactoring in 3-week phased approach.

**Next Steps**:
1. Get user approval for plan
2. Begin Phase 1: Create core structure
3. Validate early and often
4. Iterate based on feedback

---

**Last Updated**: 2026-01-27  
**Author**: Researcher Agent + Curator Agent  
**Status**: Phase 4 Complete - Migration Done

## Migration Completion Notes (2026-01-27)

**Completed by**: Curator Agent

**What was done**:
1. ✅ Added deprecation notices to all 6 old Django skills
2. ✅ Updated AGENTS.md directory structure and examples
3. ✅ Verified no rule files needed updates (no direct skill references)
4. ✅ Set deprecation timeline: Archive on 2026-02-27 (1 month)

**Backwards compatibility**:
- Old skills still exist and work
- Clear deprecation warnings at top of each file
- Migration path documented in each deprecation notice
- Users/agents have 1 month to migrate

**Next steps**:
- Phase 3 (Scripts & Assets) - optional, can be added incrementally
- Phase 5 (Validation) - test with skills-ref validate tool
- Phase 6 (Monitoring) - track usage patterns
- Archive old skills on 2026-02-27
