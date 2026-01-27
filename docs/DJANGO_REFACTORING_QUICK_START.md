# Django Skill Refactoring: Quick Start Guide

**Date**: 2026-01-27  
**For**: User review and decision

---

## TL;DR

**Proposal**: Consolidate 6 Django skills into 1 modular skill with selective loading.

**Benefits**:
- 60-70% context savings for typical use cases
- Single entry point for better discoverability
- Easier maintenance (update once, not 3-6 times)
- Better extensibility (add references, not skills)

**Timeline**: 3 weeks

**Risk**: Low (1-month deprecation period for backwards compatibility)

---

## What You Need to Know

### Current State

```
6 separate skills:
├── django-architecture (801 lines)
├── django-async-websocket (374 lines)
├── django-celery (614 lines)
├── django-multi-tenant (755 lines)
├── django-celery-multitenant (327 lines)
└── django-async-websocket-multitenant (363 lines)

Total: 3,234 lines
```

### Proposed State

```
1 modular skill:
skills/django/
├── SKILL.md (500 lines) - Core patterns
├── references/ (6 files, ~1,750 lines) - Load on-demand
├── scripts/ (4 files) - Automation helpers
└── assets/ (templates & diagrams)
```

### How It Works

**Agent loads**:
1. `django/SKILL.md` (~500 lines) - Always
2. References as needed:
   - Need multi-tenancy? → Load `references/MULTI_TENANT.md`
   - Need WebSocket? → Load `references/ASYNC_WEBSOCKET.md`
   - Need Celery? → Load `references/CELERY.md`
   - Need combinations? → Load extension references

**Result**: Agent loads only what's needed, saving 60-70% context.

---

## Documents to Review

### 1. Executive Summary (Start Here)
**File**: [DJANGO_REFACTORING_SUMMARY.md](DJANGO_REFACTORING_SUMMARY.md)  
**Length**: ~2 pages  
**Content**: High-level overview, benefits, risks, timeline

### 2. Full Plan (Detailed)
**File**: [DJANGO_SKILL_REFACTORING_PLAN.md](DJANGO_SKILL_REFACTORING_PLAN.md)  
**Length**: ~15 pages  
**Content**: Complete refactoring plan with:
- Agent Skills specification analysis
- Current skill analysis
- Proposed structure
- Migration strategy
- Success metrics

### 3. Before/After Comparison (Visual)
**File**: [DJANGO_REFACTORING_COMPARISON.md](DJANGO_REFACTORING_COMPARISON.md)  
**Length**: ~8 pages  
**Content**: Side-by-side comparisons:
- Structure comparison
- Loading scenarios (7 examples)
- Context savings table
- Discoverability comparison
- Maintenance comparison

### 4. Preview (Concrete Example)
**File**: [DJANGO_SKILL_PREVIEW.md](DJANGO_SKILL_PREVIEW.md)  
**Length**: ~6 pages  
**Content**: Preview of new `SKILL.md` structure:
- Frontmatter
- Core content
- References
- Scripts & tools

---

## Key Questions for You

### 1. Timing
**Q**: Is 3-week timeline acceptable?  
**Breakdown**:
- Week 1: Core structure + reference files
- Week 2: Scripts + assets
- Week 3: Migration + deprecation

**Your input**: _______________________________

### 2. Backwards Compatibility
**Q**: Is 1-month deprecation period sufficient?  
**Plan**:
- Keep old skills for 1 month with deprecation notices
- Update all internal references immediately
- Archive old skills after 1 month

**Your input**: _______________________________

### 3. Scripts Priority
**Q**: Which automation scripts would be most valuable?  
**Proposed**:
- `setup_tenant.py` - Create new tenant
- `create_consumer.py` - Generate WebSocket consumer
- `create_task.py` - Generate Celery task
- `test_celery.py` - Verify Celery setup

**Your input**: _______________________________

### 4. Validation Tool
**Q**: Do you have access to `skills-ref` validation tool?  
**Why**: Agent Skills specification provides validation tool  
**Alternative**: Manual validation against spec

**Your input**: _______________________________

### 5. Implementation Approach
**Q**: Should we implement all at once or phase by phase?  
**Options**:
- A) All at once (3 weeks, then switch)
- B) Phase by phase (validate each phase before next)

**Your input**: _______________________________

---

## Decision Matrix

| Factor | Current (6 skills) | Proposed (1 modular) | Winner |
|--------|-------------------|---------------------|--------|
| Context usage | 64k tokens (all) | 10-45k tokens (selective) | ✅ Proposed |
| Discoverability | Must know 6 skills | Single entry point | ✅ Proposed |
| Maintenance | Update 3-6 places | Update 1 place | ✅ Proposed |
| Extensibility | Exponential growth | Linear growth | ✅ Proposed |
| Complexity | Flat (simple) | Nested (complex) | ⚠️ Current |
| Backwards compat | N/A | 1-month deprecation | ⚖️ Neutral |

**Recommendation**: Proceed with refactoring.

---

## Next Steps (If Approved)

### Week 1: Core Structure
- [ ] Create `skills/django/` directory
- [ ] Write `SKILL.md` (~500 lines)
- [ ] Extract reference files
- [ ] Validate with `skills-ref validate` (if available)
- [ ] Test loading in agent

### Week 2: Scripts & Assets
- [ ] Create automation scripts
- [ ] Add templates
- [ ] Add diagrams
- [ ] Test scripts

### Week 3: Migration
- [ ] Update `AGENTS.md` and rules
- [ ] Add deprecation notices to old skills
- [ ] Test backwards compatibility
- [ ] Document migration path

---

## Questions?

**Clarifications needed**:
1. _______________________________
2. _______________________________
3. _______________________________

**Concerns**:
1. _______________________________
2. _______________________________
3. _______________________________

**Suggestions**:
1. _______________________________
2. _______________________________
3. _______________________________

---

## Approval

**Decision**: [ ] Approve  [ ] Reject  [ ] Needs Changes

**If Needs Changes**:
- _______________________________
- _______________________________
- _______________________________

**If Approved**:
- Start date: _______________________________
- Priority: [ ] High  [ ] Medium  [ ] Low
- Special instructions: _______________________________

---

## Contact

**Questions**: Ask researcher agent  
**Documents**: All in `docs/` directory  
**Status**: Awaiting your decision

---

**Last Updated**: 2026-01-27
