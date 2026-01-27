# Backwards Compatibility Tracking

**Purpose**: Document skills/rules that may NOT be fully compatible with current Teisutis architecture/setup  
**Date**: 2026-01-26  
**Status**: Active (Insurance Policy)  
**Applies To**: mind-vault - Teisutis project integration

---

## Overview

This document tracks which skills and rules may have compatibility gaps with Teisutis's current setup. Use this as an "insurance policy" to:
- Identify potential integration issues before they become bugs
- Document workarounds or adaptations needed
- Track when Teisutis architecture changes require skill updates
- Prevent blindly copying patterns that don't work in Teisutis context

---

## Tracking Table

| Skill/Rule | Component | Status | Issue | Workaround/Notes | Last Checked |
|-----------|-----------|--------|-------|------------------|--------------|
| SKILL_django-architecture | Flat app structure | ✅ COMPATIBLE | Teisutis uses flat apps in `web/` dir (auth, core, api, etc.) | Identical structure - can directly apply | 2026-01-26 |
| SKILL_django-architecture | web/ subdirectory | ✅ COMPATIBLE | Teisutis separates infrastructure (docker, nginx, docs) from Django code | Skills now document this pattern explicitly | 2026-01-26 |
| SKILL_django-architecture | BaseModel soft deletes | ✅ COMPATIBLE | Teisutis uses this pattern extensively | Can directly apply to new models | 2026-01-26 |
| SKILL_django-architecture | DRF ViewSets | ✅ COMPATIBLE | Teisutis DRF patterns match skill | Can directly apply | 2026-01-26 |
| SKILL_django-architecture | ASGI/Daphne | ✅ COMPATIBLE | Teisutis uses Daphne setup | Can directly apply | 2026-01-26 |
| SKILL_django-architecture | Modular views/tests | ✅ COMPATIBLE | Teisutis auth app uses this pattern | Can directly apply | 2026-01-26 |
| SKILL_django-multi-tenant | TenantModel inheritance | ✅ COMPATIBLE | Teisutis uses django-tenants | Foundation for this skill | 2026-01-27 |
| SKILL_django-multi-tenant | User/UserScope pattern | ✅ COMPATIBLE | Multi-org access with granular permissions | Can directly apply | 2026-01-27 |
| SKILL_django-multi-tenant | 5-layer permission checking | ✅ COMPATIBLE | Token + org membership + admin + scope + escalation | Can directly apply | 2026-01-27 |
| SKILL_django-multi-tenant | Middleware ordering | ✅ COMPATIBLE | TenantMainMiddleware early in MIDDLEWARE list | Matches Teisutis pattern | 2026-01-27 |
| SKILL_django-celery | Signal-based task triggering | ✅ COMPATIBLE | Teisutis uses this approach | Can directly apply | 2026-01-27 |
| SKILL_django-celery | Tenant context in tasks | ✅ COMPATIBLE | Teisutis explicitly passes tenant_id (single-tenant version) | Can directly apply | 2026-01-27 |
| SKILL_django-celery | Retry patterns with backoff | ✅ COMPATIBLE | Standard Celery approach | Can directly apply | 2026-01-27 |
| SKILL_django-celery-multitenant | Signal-based task triggering | ✅ COMPATIBLE | Teisutis uses this approach with tenant context | Can directly apply | 2026-01-27 |
| SKILL_django-celery-multitenant | Tenant context in tasks | ✅ COMPATIBLE | Teisutis explicitly passes tenant_id with schema context | Can directly apply | 2026-01-27 |
| SKILL_django-celery-multitenant | Retry patterns with backoff | ✅ COMPATIBLE | Standard Celery approach | Can directly apply | 2026-01-27 |
| SKILL_django-async-websocket | @database_sync_to_async | ✅ COMPATIBLE | Teisutis uses extensively | Can directly apply | 2026-01-27 |
| SKILL_django-async-websocket | Tenant context in async | ✅ COMPATIBLE | Intentionally single-tenant only - tenant context handled in multi-tenant variant | No tenant code - clean separation | 2026-01-27 |
| SKILL_django-async-websocket | Group broadcasting | ✅ COMPATIBLE | Teisutis uses for real-time updates | Can directly apply | 2026-01-27 |
| SKILL_django-async-websocket-multitenant | @database_sync_to_async | ✅ COMPATIBLE | Teisutis uses extensively | Can directly apply | 2026-01-27 |
| SKILL_django-async-websocket-multitenant | Tenant context in async | ✅ COMPATIBLE | Teisutis uses tenant_context(tenant) in consumers | Can directly apply | 2026-01-27 |
| SKILL_django-async-websocket-multitenant | Group broadcasting | ✅ COMPATIBLE | Teisutis uses for real-time updates with tenant isolation | Can directly apply | 2026-01-27 |
| RULE_commit-approval | Every commit needs approval | ✅ COMPATIBLE | Principle is universal | Apply to all work | 2026-01-26 |
| RULE_git-workflow | Branch strategy | ✅ COMPATIBLE | Principle is universal | Apply to all work | 2026-01-26 |

---

## Known Integration Gaps

**All 6 Skills Verified ✅**

*Multi-Tenant Skill*
- UserScope pattern tested against Teisutis multi-org architecture
- Permission layers align with existing Teisutis RBAC model
- No integration gaps identified

*Celery Skills (Single & Multi-Tenant)*
- Signal-based patterns match Teisutis approach
- Tenant context explicit parameter passing verified
- Retry backoff patterns standard Celery approach

*Async/WebSocket Skills (Single & Multi-Tenant)*
- @database_sync_to_async usage matches Teisutis implementations
- Tenant context switching in consumers verified (multi-tenant version)
- Group broadcasting used in Teisutis for real-time features
- Single-tenant version cleaned of tenant contamination

*(No integration gaps identified - all skills aligned with Teisutis architecture)*

### Past Issues (Resolved)

**Issue**: App structure mismatch (RESOLVED)
- **Initial Thought**: Teisutis uses nested `web/teisutis_*` apps
- **Reality**: Teisutis uses flat apps in `web/` (auth, core, api, not prefixed)
- **Resolution**: Skills updated to document `web/` subdirectory pattern correctly
- **Status**: ✅ RESOLVED - Skills now match Teisutis exactly

**Issue**: Single-tenant WebSocket contamination (RESOLVED 2026-01-27)
- **Issue**: SKILL_django-async-websocket.md contained tenant code, confusing single-tenant projects
- **Resolution**: Removed all tenant code from single-tenant skill, created separate SKILL_django-async-websocket-multitenant.md
- **Status**: ✅ RESOLVED - Clean separation between single/multi-tenant variants

---

## Verification Checklist (Skills Ready for Teisutis Deployment)

- [x] Multi-tenant skill tested against Teisutis tenant resolution middleware ✅
- [x] UserScope pattern verified against Teisutis permission model ✅
- [x] Celery skills tested against actual Teisutis signal handlers and tasks (single & multi-tenant variants) ✅
- [x] Async skills tested against actual Teisutis consumers (single & multi-tenant variants) ✅
- [x] Middleware ordering verified (TenantMainMiddleware early) ✅
- [x] Permission layer testing verified (5-layer system matches Teisutis) ✅
- [x] Database isolation verified with multi-tenant queries ✅
- [x] Soft delete queries verified (is_deleted=False filtering) ✅
- [x] Celery retry patterns compatible ✅
- [x] Async context management safe (@database_sync_to_async usage) ✅
- [x] Single-tenant variants cleaned of multi-tenant contamination ✅

---

## Update Frequency

**Review when**:
- New skill is created
- Teisutis architecture changes significantly
- A skill is used in Teisutis project and issues are found
- New versions of Django, DRF, django-tenants, Celery released

**Last Audit**: 2026-01-27 (All 4 skills completed and verified)  
**Next Audit**: After skills deployed to Teisutis (in production)

---

## Issue Resolution Process

1. **Find Issue**: Developer discovers skill doesn't work with Teisutis setup
2. **Document Here**: Add row to tracking table with status `⚠️ ISSUE`
3. **Investigate**: Determine if issue is:
   - Skill error (fix skill)
   - Teisutis-specific (add workaround)
   - Version mismatch (document version requirement)
4. **Resolve**: Either fix skill or document workaround
5. **Update Status**: Change status back to ✅ or ⚠️ WORKAROUND

---

## Related Documents

- [`TEISUTIS_ARCHITECTURE_ANALYSIS.md`](TEISUTIS_ARCHITECTURE_ANALYSIS.md) - Technical analysis used to create skills
- [`DJANGO_ARCHITECTURE_PLAN.md`](DJANGO_ARCHITECTURE_PLAN.md) - Skill development roadmap
- Skills: 
  - `skills/SKILL_django-architecture.md`
  - `skills/SKILL_django-multi-tenant.md` (in progress)
  - `skills/SKILL_django-celery.md` (in progress)
  - `skills/SKILL_django-async-websocket.md` (in progress)

---

**Last Updated**: 2026-01-27  
**Maintained By**: mind-vault team  
**Purpose**: Insurance policy for skill/Teisutis compatibility

---

## Complete Skill Suite Summary

✅ **COMPLETED**: All 6 Django Architecture Skills
- **SKILL_django-architecture** (750+ lines) - Core patterns
- **SKILL_django-multi-tenant** (740+ lines) - Schema isolation
- **SKILL_django-celery** (600+ lines) - Single-tenant background tasks
- **SKILL_django-celery-multitenant** (650+ lines) - Multi-tenant background tasks
- **SKILL_django-async-websocket** (710+ lines) - Single-tenant real-time features (FIXED - no tenant contamination)
- **SKILL_django-async-websocket-multitenant** (750+ lines) - Multi-tenant real-time features

**Verification Status**: All patterns compatible with Teisutis
- ✅ 39 injection points documented
- ✅ 150+ code examples provided
- ✅ All critical safety warnings included
- ✅ Clean separation between single/multi-tenant variants
- ✅ Ready for immediate deployment

**Next Step**: Create PR to main branch and merge
