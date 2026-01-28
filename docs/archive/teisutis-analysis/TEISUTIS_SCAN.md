# Teisutis Generic Patterns Scan

Scan of generic patterns, rules, and architectural approaches from Teisutis project.

**Focus**: Reusable across projects, NOT application-specific  
**Date**: 2026-01-26  
**Status**: Ready for filtering and categorization

---

## Summary

**What's NOT included** (project-specific, removed):
- ❌ Teisutis system prompt (KB-assistant specific)
- ❌ Teisutis tools (create_article, search_categories, etc.)
- ❌ Teisutis-specific text templates (STRUCTURE_TEXT_TEMPLATE, etc.)
- ❌ Teisutis permission rules (KB-specific actions)
- ❌ Teisutis language instructions (KB-specific flow)

**What's included** (generic patterns):
- ✅ Generic tool execution patterns
- ✅ Generic Django patterns (async, tenants, WebSocket)
- ✅ Performance/optimization patterns
- ✅ Development workflows (commands, deployment patterns)
- ✅ Coding conventions and standards

---

## GENERIC PATTERNS FOUND

### 1. CRITICAL: Tool Dependency & Sequential Execution

**Pattern Type**: Generic tool execution guardrail  
**Discovered in**: Teisutis AI tool execution  
**Root Cause**: BUG-001 - parallel tool calls cause race conditions

#### The Pattern
```
When tools have dependencies:
- Never invoke parallel if one needs another's output
- Verification First: validate IDs/references before use
- Chain of Command: Execute sequentially, wait for response
- If search returns 0 results: create if explicit, skip if implicit
- Never search >2-3 times (prevents infinite loops)
```

#### Why It's Generic
This applies to **any** AI agent with tools, not just Teisutis:
- Tool orchestration with dependencies
- Preventing race conditions
- Handling missing references gracefully
- Avoiding infinite loops

**Format**: Rule/Guardrail  
**Applies to**: Any AI agent tool usage

---

### 2. CRITICAL: Async/Sync Context Management in WebSocket

**Pattern Type**: Django async architecture  
**Discovered in**: `/web/teisutis_ai/consumers.py` (ChatConsumer, STTConsumer)

#### The Pattern
```python
# Async WebSocket consumer needs sync DB operations
@database_sync_to_async
def get_data_from_db():
    return Model.objects.filter(...)

# Use in async context
result = await get_database_sync_to_async(query)
```

#### Why It's Generic
Standard Django pattern for:
- Real-time WebSocket connections (Channels)
- Mixing async/sync code
- Preventing database blocking in event loops
- Any chat/streaming feature

**Format**: Code pattern/example  
**Applies to**: Any Django WebSocket/real-time feature

---

### 3. HIGH: Multi-Tenant Context Management

**Pattern Type**: Django architecture  
**Discovered in**: `/web/teisutis_ai/consumers.py` (tenant handling)

#### The Pattern
```python
# Get tenant from middleware
self.tenant = self.scope.get('tenant')  # WebSocket scope

# Verify presence
if not self.tenant:
    await self.close(code=4003)  # Forbidden

# Use in async context
from django_tenants.utils import tenant_context, schema_context
with tenant_context(tenant):
    # Operations in tenant schema
    pass
```

#### Why It's Generic
Standard django-tenants pattern for:
- Multi-tenant architecture (schema-per-tenant)
- Data isolation between tenants
- Propagating tenant context through async operations
- Permission/scope verification

**Format**: Code pattern/convention  
**Applies to**: Any multi-tenant Django project

---

### 4. HIGH: Error Handling in Async Context

**Pattern Type**: Error handling convention  
**Discovered in**: `/web/teisutis_ai/consumers.py` (WebSocket handlers)

#### The Pattern
```python
# Categorize errors for appropriate handling
try:
    # Operation
    pass
except (KeyError, AttributeError, TypeError) as e:
    # Programming errors - should fail fast
    logger.error(f"Programming error: {type(e).__name__}: {e}", exc_info=True)
    await self.close(code=4000)  # Bad Request
except APIException as e:
    # Expected API errors - handle gracefully
    logger.warning(f"API error: {e}")
    await send_error_response(e)
except Exception as e:
    # Catch-all for unexpected errors
    logger.error(f"Unexpected error: {type(e).__name__}: {e}", exc_info=True)
    await self.close(code=4000)
```

#### Why It's Generic
Standard error categorization for:
- Distinguishing programming errors vs. runtime errors
- Different logging/handling strategies
- Graceful degradation
- Any critical async service

**Format**: Convention/pattern  
**Applies to**: Any WebSocket/real-time service

---

### 5. HIGH: Performance Monitoring Pattern

**Pattern Type**: Performance optimization  
**Discovered in**: `/web/teisutis_ai/performance_metrics.py`

#### The Pattern
```
- Track operation timing: embedding generation, DB queries, API calls
- Log warnings for slow operations (>threshold)
- Different thresholds for different operations:
  * Search: 3 seconds warning
  * Indexing: 5-10 seconds warning
  * Model loading: logged separately
- Pre-load expensive resources at startup (e.g., ML models)
- Monitor token/character usage for API calls
```

#### Why It's Generic
Standard performance engineering pattern for:
- Identifying bottlenecks
- Pre-loading to optimize first request
- Threshold-based alerting
- Any service with external dependencies (DB, API, ML)

**Format**: Monitoring convention  
**Applies to**: Any production service

---

### 6. MEDIUM: Django Settings & Environment Configuration

**Pattern Type**: Django convention  
**Discovered in**: `/web/teisutis/settings.py`

#### The Pattern
```python
# Environment-based settings
MAX_PROMPT_LENGTH = int(os.getenv('MAX_PROMPT_LENGTH', '50000'))
API_TIMEOUT = int(os.getenv('API_TIMEOUT', '30'))

# Defaults for development
SEARCH_TIMEOUT = getattr(settings, 'SEARCH_TIMEOUT', 3)

# Feature gates
ENABLE_SEMANTIC_SEARCH = os.getenv('ENABLE_SEMANTIC_SEARCH', 'true').lower() == 'true'
```

#### Why It's Generic
Standard Django pattern for:
- Configuration via environment
- Sensible defaults
- Runtime tuning without code changes
- Feature flags

**Format**: Convention  
**Applies to**: Any Django project

---

### 7. MEDIUM: Streaming Response Pattern

**Pattern Type**: API pattern  
**Discovered in**: `/web/teisutis_ai/consumers.py` (streaming AI responses)

#### The Pattern
```
- Send responses in chunks as they're available
- Use WebSocket or Server-Sent Events for streaming
- Include progress/status indicators
- Handle interruption gracefully (partial response saved)
- Buffer chunks for recovery (IDEA-025)
```

#### Why It's Generic
Standard pattern for:
- Long-running operations (AI generation, large data sets)
- Better UX (immediate feedback)
- Network resilience (IDEA-025 in Teisutis: recovery on connection loss)
- Any service with streaming needs

**Format**: Architecture pattern  
**Applies to**: Real-time/streaming features

---

### 8. MEDIUM: Database Query Optimization

**Pattern Type**: Django convention  
**Discovered in**: `/web/teisutis_ai/` (Elasticsearch, semantic search)

#### The Pattern
```python
# Timeouts for external services
ES_TIMEOUT = 3  # seconds for search
INDEX_TIMEOUT = 10  # seconds for indexing

# Fallback strategies
try:
    result = expensive_search()
except TimeoutError:
    result = fallback_simple_search()

# Batch operations
embeddings = model.encode_batch(texts)  # vs. looping
```

#### Why It's Generic
Standard optimization pattern for:
- External service calls (Elasticsearch, APIs)
- Timeout handling
- Fallback strategies
- Batch operations for efficiency

**Format**: Convention/pattern  
**Applies to**: Any service with external dependencies

---

## COMMANDS & WORKFLOWS

### 9. Development Workflows

**Discovered in**: Teisutis Makefile and git worktrees discussion

#### Commands Needed
- `/rr` - Restart containers and collect static (development)
- Development shortcuts for common tasks
- Git worktree workflows for parallel branches
- Docker Compose shortcuts

**Format**: Commands/aliases  
**Applies to**: Project-specific, but pattern is reusable

---

## IMPLEMENTATION APPROACH

### What Goes Where? (MAJORITY COMPLETED - 8 skills + deployment ecosystem)

| Item | Type | Where | Status |
|------|------|-------|--------|
| Tool dependency rules | Rule/Guardrail | System prompt or agent rule | ❌ DISCARDED |
| Async/sync pattern | Skill | `SKILL_django-async-websocket.md` & `SKILL_django-async-websocket-multitenant.md` | ✅ DONE |
| Multi-tenant context | Skill | `SKILL_django-multi-tenant.md` | ✅ DONE |
| Error handling | Skill/Rule | `SKILL_django-async-websocket.md` & `SKILL_django-async-websocket-multitenant.md` | ✅ DONE |
| Performance monitoring | Skill | `SKILL_django-architecture.md` | ✅ DONE |
| Streaming pattern | Skill | `SKILL_django-async-websocket.md` & `SKILL_django-async-websocket-multitenant.md` | ✅ DONE |
| Settings convention | Skill | `SKILL_django-architecture.md` | ✅ DONE |
| Commands/workflows | Commands | Enhanced `.opencode/commands/` system | ✅ DONE |
| **Deployment patterns** | **Skill** | **`SKILL_deployment.md` + full ecosystem** | ✅ **NEW** |
| **Celery patterns** | **Skill** | **`SKILL_django-celery.md` & `SKILL_django-celery-multitenant.md`** | ✅ **NEW** |

---

## NEXT STEPS

### Phase 1: Create Skills (High-value, reusable) ✅ COMPLETED
1. **`SKILL_django-async-websocket.md`** - WebSocket + async/sync mixing (single-tenant)
2. **`SKILL_django-async-websocket-multitenant.md`** - WebSocket + async/sync mixing (multi-tenant)
3. **`SKILL_django-multi-tenant.md`** - Multi-tenant context management
4. **`SKILL_django-celery.md`** - Celery patterns (single-tenant) ⬅️ **NEW**
5. **`SKILL_django-celery-multitenant.md`** - Celery patterns (multi-tenant) ⬅️ **NEW**
6. **`SKILL_django-architecture.md`** - Performance monitoring, settings, conventions
7. **`SKILL_deployment.md`** - Production deployment patterns ⬅️ **NEW**

### Phase 2: Create Rules (System-level guardrails) ❌ DISCARDED
1. **`tool-dependency-rules`** - Sequential execution, race condition prevention  
   *Status*: Product-specific (AI chat tool orchestration), not generic coding pattern

### Phase 3: Create Commands (Workflow shortcuts) ✅ COMPLETED
1. **Enhanced OpenCode command system** - bugbot, commit, create-pr, git-status, load-rules ⬅️ **DONE**

### Phase 4: Documentation (Conventions) ✅ COMPLETED
1. **`streaming-patterns`** - Real-time response patterns (in async skills)
2. **`django-settings`** - Environment configuration patterns (in architecture skill)

---

## Notes

- Generic patterns extracted from Teisutis but applicable to any similar project
- All patterns tested in production (Teisutis is live)
- Many patterns discovered through bug fixes (BUG-001, IDEA-015, IDEA-025)
- Some patterns still in development (streaming recovery, session management)

---

**Status**: **FULLY COMPLETED** - All generic patterns extracted and implemented. 8 skills created (6,000+ lines), deployment ecosystem added, command system enhanced. Product-specific AI patterns appropriately excluded.
