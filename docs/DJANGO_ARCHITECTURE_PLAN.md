# Django Architecture Skill Implementation Plan

**Purpose**: Extract and document Django architecture patterns from Teisutis into reusable skills  
**Date**: 2026-01-26  
**Status**: In Progress  
**Applies To**: mind-vault - skills for Django projects

---

## Overview

Extract Django architecture from Teisutis analysis into 4 focused skills:
1. Core Django architecture (non-tenant, non-Celery)
2. Multi-tenant patterns (separate, don't clutter non-MT projects)
3. Celery patterns (separate, don't clutter non-Celery projects)
4. Async/WebSocket patterns (separate, don't clutter synchronous projects)

---

## Skills to Create

### ✅ SKILL_django-architecture.md - Core Django

**Content**:
- [x] Django project structure - flat app layout (Django convention)
- [x] Model patterns - BaseModel abstraction, created_at/updated_at, soft deletes
- [x] Settings & configuration - environment-based, feature gates, sensible defaults
- [x] DRF patterns - ViewSet structure, permission patterns, serializers
- [x] Middleware - request context handling (generic middleware concept)
- [x] Per-app static/templates/locale - Django auto-discovery, collectstatic, Nginx serving
- [x] Modular views/tests organization - split by purpose (api.py, web.py, invitations.py)
- [x] Consolidation facade pattern - safe refactoring via __init__.py
- [x] ASGI configuration - Daphne setup, protocol routing
- [x] Common abstractions - mixins, base classes, DRY patterns
- [x] Database optimization - N+1 prevention, batch operations, timeouts
- [x] Performance monitoring - decorator-based observability

**Explicitly Separate** (don't include):
- ❌ Multi-tenant context/middleware
- ❌ Celery patterns
- ❌ WebSocket/async patterns

**Status**: ✅ Complete - File: `skills/SKILL_django-architecture.md` (~750 lines)

---

### ✅ SKILL_django-multi-tenant.md - Multi-tenant Specific

**Content**:
- [x] TenantModel inheritance pattern
- [x] TenantContextMiddleware - implementation and ordering
- [x] Tenant resolution strategies - header-based, domain-based fallback
- [x] Permission layers with tenant checking (5-layer system)
- [x] Tenant context propagation through request lifecycle
- [x] All 10 multi-tenant injection points identified
- [x] Common pitfalls - cross-tenant leaks, context loss
- [x] UserScope pattern for multi-org access with granular permissions
- [x] Examples from Teisutis

**Status**: ✅ Complete - File: `skills/SKILL_django-multi-tenant.md` (~740 lines)

---

### ✅ SKILL_django-celery.md - Celery Specific

**Content**:
- [ ] Signal handlers triggering Celery tasks
- [ ] Task patterns with explicit tenant_id parameter
- [ ] Celery + Channels bridge for real-time updates
- [ ] Background task context management
- [ ] Retry patterns and backoff
- [ ] All 9 Celery injection points identified
- [ ] Critical rule: Never assume request context in tasks
- [ ] Examples from Teisutis

**Status**: Pending

---

### ✅ SKILL_django-async-websocket.md - WebSocket/Async Specific

**Content**:
- [ ] AsyncWebsocketConsumer patterns
- [ ] @database_sync_to_async decorator usage
- [ ] Tenant context in async code
- [ ] Error handling and categorization in async
- [ ] asyncio.run() bridge for sync calls
- [ ] All 10 async/WebSocket injection points identified
- [ ] Connection lifecycle (resolve → verify → join → accept)
- [ ] Examples from Teisutis

**Status**: Pending

---

## Execution Plan

### Phase 1: Create Core Skill
- [x] Create SKILL_django-architecture.md
- [x] Include BaseModel patterns, settings, DRF basics
- [x] Include common abstractions (mixins, decorators)
- [x] Include database optimization patterns
- [x] Commit to feature/django-architecture branch
- **Status**: ✅ Complete (Commit: 15e3c19)

### Phase 2: Create Multi-tenant Skill
- [x] Create SKILL_django-multi-tenant.md
- [x] Document all 10 injection points
- [x] Include critical safety warnings
- [x] Commit to same branch
- **Status**: ✅ Complete (Commits: 5fb30cc, c35bfea)

### Phase 3: Create Celery Skill
- [ ] Create SKILL_django-celery.md
- [ ] Document all 9 injection points
- [ ] Include critical safety warnings
- [ ] Commit to same branch

### Phase 4: Create Async/WebSocket Skill
- [ ] Create SKILL_django-async-websocket.md
- [ ] Document all 10 injection points
- [ ] Include critical safety warnings
- [ ] Commit to same branch

### Phase 5: Review and PR
- [ ] Curator review all 4 skills
- [ ] Verify cross-references
- [ ] Create PR to main
- [ ] Merge when approved

---

## Source Material

**Analysis Document**: `/home/kestas/projects/mind-vault/docs/TEISUTIS_ARCHITECTURE_ANALYSIS.md`

Contains:
- 932 lines of detailed architecture breakdown
- 29 identified injection points (10 multi-tenant, 9 Celery, 10 async)
- 10 reusable architecture patterns
- Critical design decisions and warnings
- Code examples from Teisutis

---

## Key Design Principles

1. **Clarity over cleverness**: Each skill is self-contained, can be read in isolation
2. **Separation of concerns**: Multi-tenant/Celery/Async don't bleed into core skill
3. **Context efficiency**: Non-multi-tenant projects don't load MT skill
4. **Safety first**: Critical warnings prominently displayed
5. **Examples included**: All patterns have working code samples from Teisutis

---

## Cross-References

After all skills created:
- SKILL_django-architecture → "See SKILL_django-multi-tenant if using multi-tenancy"
- SKILL_django-architecture → "See SKILL_django-celery if using background tasks"
- SKILL_django-architecture → "See SKILL_django-async-websocket if using real-time features"
- Each skill → Back-references to core skill
- All skills → Reference to AGENTS.md roles (Architect, Test Engineer, etc.)

---

**Last Updated**: 2026-01-27

---

## Progress Summary

**Phase 1 ✅**: SKILL_django-architecture - Complete
- 750+ lines covering core Django patterns
- All core patterns documented with examples
- BaseModel, DRF, middleware, ASGI, database optimization

**Phase 2 ✅**: SKILL_django-multi-tenant - Complete  
- 740+ lines covering multi-tenant architecture
- UserScope pattern for multi-org access
- 5-layer permission system fully documented
- All 10 injection points with critical safety warnings
- Verified compatible with Teisutis (BACKWARDS_COMPATIBILITY_TRACKING.md)

**Phase 3 ⏳**: SKILL_django-celery - Next
- Signal handlers triggering background tasks
- Task patterns with explicit tenant_id parameter
- 9 injection points for Celery integration
- Retry patterns and error handling

**Phase 4 ⏳**: SKILL_django-async-websocket - Next
- AsyncWebsocketConsumer patterns
- @database_sync_to_async decorator usage
- Tenant context in async code
- 10 injection points for async/WebSocket integration
