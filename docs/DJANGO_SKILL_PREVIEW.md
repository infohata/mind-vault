# Django Skill Preview: New SKILL.md Structure

**Date**: 2026-01-27  
**Purpose**: Preview of proposed modular django/SKILL.md

---

## Proposed SKILL.md (Abbreviated)

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

**This skill covers**:
- Project structure and organization
- BaseModel abstractions (soft deletes, timestamps)
- Settings & environment configuration
- DRF ViewSets, permissions, serializers
- Middleware patterns
- ASGI configuration (basic)
- Database optimization (N+1 prevention, batch operations)
- Performance monitoring

**Optional Extensions** (load on-demand):
- [Multi-Tenant Architecture](references/MULTI_TENANT.md) - Schema-per-tenant isolation
- [Async WebSocket](references/ASYNC_WEBSOCKET.md) - Real-time communication
- [Celery Background Tasks](references/CELERY.md) - Async job processing
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md) - WebSocket with tenants
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md) - Tasks with tenants

## When to Use

**Use this skill when**:
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
- Combining patterns → [MULTI_TENANT_ASYNC.md](references/MULTI_TENANT_ASYNC.md) or [MULTI_TENANT_CELERY.md](references/MULTI_TENANT_CELERY.md)

## Pattern

### Project Structure

**Standard Django layout with infrastructure separation**:

```
git_repo_root/
├── docker-compose.yml              # Infrastructure
├── Dockerfile
├── nginx/
├── docs/
├── tools/
│
└── web/                            # ← All Django code here
    ├── manage.py
    ├── requirements.txt
    ├── .env.example
    ├── project/                    # Project settings
    │   ├── __init__.py
    │   ├── settings.py
    │   ├── asgi.py
    │   └── urls.py
    ├── core/                       # Shared utilities
    │   ├── models.py               # BaseModel
    │   ├── mixins.py
    │   ├── permissions.py
    │   └── middleware.py
    ├── auth/                       # Authentication app
    ├── api/                        # Main API endpoints
    └── [feature]/                  # Feature-specific apps
```

**Why `web/` subdirectory**:
- Clean separation: Infrastructure at repo root, Django code in `web/`
- Docker-friendly: `web/` service mounts to `/app` in container
- Django code self-contained: `web/` has everything Django needs

### BaseModel Abstraction

**Create abstract base models to reduce duplication**:

```python
# core/models.py
from django.db import models, transaction

class BaseModel(models.Model):
    """Abstract base model with common fields."""
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_deleted = models.BooleanField(default=False)

    class Meta:
        abstract = True
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def soft_delete(self):
        """Mark as deleted instead of removing."""
        with transaction.atomic():
            obj = self.__class__.objects.select_for_update().get(pk=self.pk)
            if obj.is_deleted:
                return False
            obj.is_deleted = True
            obj.save(update_fields=['is_deleted', 'updated_at'])
            return True
```

**Use in your models**:

```python
class Article(BaseModel):
    title = models.CharField(max_length=255)
    content = models.TextField()
    author = models.ForeignKey(User, on_delete=models.CASCADE)

    class Meta:
        ordering = ['-created_at']
```

**Critical**: Always filter soft-deleted records:

```python
# Correct
Article.objects.filter(is_deleted=False)

# Wrong - includes deleted records!
Article.objects.all()  # ❌
```

### Settings & Configuration

**Organize settings with environment variables**:

```python
# project/settings.py
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Environment-based configuration
SECRET_KEY = os.getenv('SECRET_KEY', 'dev-key-change-in-production')
DEBUG = os.getenv('DEBUG', 'false').lower() == 'true'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'project_db'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD', ''),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
        'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '600')),
    }
}

# Feature gates
FEATURE_ENABLE_CACHING = os.getenv('FEATURE_ENABLE_CACHING', 'true').lower() == 'true'
```

### DRF Patterns

**Base ViewSet with common functionality**:

```python
# core/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

class BaseViewSet(viewsets.ModelViewSet):
    """Base viewset with common functionality."""
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = super().get_queryset()
        # Add select_related/prefetch_related as needed
        return queryset
```

**Permission classes**:

```python
# core/permissions.py
from rest_framework.permissions import BasePermission

class IsResourceOwner(BasePermission):
    """Only allow resource owner to modify."""
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user
```

**Use in viewsets**:

```python
class ArticleViewSet(BaseViewSet):
    queryset = Article.objects.filter(is_deleted=False)
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticated, IsResourceOwner]
```

### Middleware Patterns

**Custom middleware for request context**:

```python
# core/middleware.py
from django.utils import timezone

class RequestContextMiddleware:
    """Add context to request for downstream use."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user_id = request.user.id if request.user.is_authenticated else None
        request.user_context = {
            'user_id': user_id,
            'timestamp': timezone.now(),
        }
        response = self.get_response(request)
        return response
```

**Add to settings**:

```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
    'core.middleware.RequestContextMiddleware',  # Your custom middleware
]
```

### ASGI Configuration (Basic)

**Pragmatic single-server setup with Daphne**:

```python
# project/asgi.py
import os
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')

django_asgi_app = get_asgi_application()

async def application(scope, receive, send):
    """Single entry point for all HTTP/WebSocket."""
    if scope['type'] == 'http':
        await django_asgi_app(scope, receive, send)
    else:
        # WebSocket handling
        await django_asgi_app(scope, receive, send)
```

**For WebSocket support**: See [ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md)

### Database Optimization

**Prevent N+1 query problems**:

```python
# Wrong: N+1 queries
articles = Article.objects.all()
for article in articles:
    print(article.author.name)  # ❌ One query per article!

# Correct: Select related
articles = Article.objects.select_related('author')
for article in articles:
    print(article.author.name)  # ✅ Only 2 queries total

# Correct: Prefetch related (many-to-many)
articles = Article.objects.prefetch_related('comments')
for article in articles:
    for comment in article.comments.all():  # ✅ Only 2 queries total
        print(comment.text)
```

**Batch operations**:

```python
# Inefficient
for article in articles:
    article.status = 'published'
    article.save()  # ❌ One query per article!

# Efficient
Article.objects.filter(status='draft').update(status='published')  # ✅ One query!
```

### Performance Monitoring

**Decorator-based timing and alerting**:

```python
# core/decorators.py
import time
import logging
from functools import wraps

logger = logging.getLogger(__name__)

def monitor_performance(operation_name, warn_threshold_ms=1000):
    """Alert if operation takes longer than threshold."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start = time.time()
            try:
                result = func(*args, **kwargs)
                return result
            finally:
                elapsed_ms = (time.time() - start) * 1000
                if elapsed_ms > warn_threshold_ms:
                    logger.warning(
                        f"{operation_name} took {elapsed_ms:.1f}ms "
                        f"(threshold: {warn_threshold_ms}ms)"
                    )
        return wrapper
    return decorator
```

**Use in views**:

```python
class ArticleViewSet(BaseViewSet):
    @monitor_performance('list_articles', warn_threshold_ms=500)
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)
```

## When NOT to Use These Patterns

### BaseModel Soft Deletes
- **Don't use for audit logs** (never delete, keep all history)
- **Don't use for temporary data** (should hard delete)
- **Don't use if you need referential integrity** (soft deletes break FK constraints)

### ASGI with Daphne
- **Don't use if no WebSocket/async needs** (Gunicorn is more mature)
- **Don't use for high-traffic HTTP-only APIs** (performance overhead)

### Performance Monitoring
- **Don't add to every method** (only critical paths)
- **Don't use in development** (affects debugging)

## Related References

**Core Extensions**:
- [Multi-Tenant Architecture](references/MULTI_TENANT.md) - Schema-per-tenant isolation
- [Async WebSocket](references/ASYNC_WEBSOCKET.md) - Real-time communication
- [Celery Background Tasks](references/CELERY.md) - Async job processing

**Combined Patterns**:
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md) - WebSocket with tenants
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md) - Tasks with tenants

**Additional Resources**:
- [Forms & Validation](references/FORMS.md) - Form patterns and validation

## Scripts & Tools

**Automation helpers** (in `scripts/`):
- `setup_tenant.py` - Create new tenant (multi-tenant projects)
- `create_consumer.py` - Generate WebSocket consumer boilerplate
- `create_task.py` - Generate Celery task boilerplate
- `test_celery.py` - Verify Celery configuration

**Templates** (in `assets/templates/`):
- `consumer_template.py` - WebSocket consumer template
- `task_template.py` - Celery task template
- `viewset_template.py` - DRF ViewSet template

## External References

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimization](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
- [ASGI Specification](https://asgi.readthedocs.io/)
- [Daphne Documentation](https://github.com/django/daphne)

---

**Last Updated**: 2026-01-27  
**Version**: 2.0  
**Replaces**: django-architecture, django-async-websocket, django-celery, django-multi-tenant, django-celery-multitenant, django-async-websocket-multitenant
```

---

## Key Features of New Structure

### 1. Clear Entry Point

```markdown
## Overview
Core Django project architecture patterns...

**Optional Extensions** (load on-demand):
- [Multi-Tenant Architecture](references/MULTI_TENANT.md)
- [Async WebSocket](references/ASYNC_WEBSOCKET.md)
- [Celery Background Tasks](references/CELERY.md)
```

Agent immediately sees what's available and how to access it.

### 2. Progressive Disclosure

```markdown
## When to Use

**Use this skill when**:
- Starting a new Django project
- [list of core use cases]

**Load additional references when**:
- Multi-tenancy required → [MULTI_TENANT.md](references/MULTI_TENANT.md)
- Real-time features needed → [ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md)
```

Agent knows when to load additional resources.

### 3. Focused Core Content

- ~500 lines (vs. 801 in old django-architecture)
- Covers essential patterns only
- References specialized patterns
- No duplication

### 4. Clear References

```markdown
**For WebSocket support**: See [ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md)
```

Explicit pointers at decision points.

### 5. Automation Support

```markdown
## Scripts & Tools

**Automation helpers** (in `scripts/`):
- `setup_tenant.py` - Create new tenant
- `create_consumer.py` - Generate WebSocket consumer
```

Agent can use scripts for common operations.

---

## Example Agent Workflow

### Task: "Build a multi-tenant Django app with chat"

**Agent thinks**:
1. "I need Django patterns" → Load `django/SKILL.md`
2. Read "When to Use" section
3. See "Multi-tenancy required → MULTI_TENANT.md"
4. See "Real-time features needed → ASYNC_WEBSOCKET.md"
5. Load `references/MULTI_TENANT.md`
6. Load `references/ASYNC_WEBSOCKET.md`
7. See reference to `references/MULTI_TENANT_ASYNC.md` for combining both
8. Load `references/MULTI_TENANT_ASYNC.md`

**Agent loads**:
- `SKILL.md` (500 lines)
- `MULTI_TENANT.md` (400 lines)
- `ASYNC_WEBSOCKET.md` (350 lines)
- `MULTI_TENANT_ASYNC.md` (250 lines)

**Total**: 1,500 lines (~30,000 tokens)

**vs. Old approach**: 2,293 lines (~46,000 tokens)

**Savings**: 35% (16,000 tokens)

---

## Conclusion

The new structure provides:

✅ **Clear entry point** - Single `django` skill  
✅ **Progressive disclosure** - Load only what's needed  
✅ **Focused content** - Core patterns in ~500 lines  
✅ **Explicit guidance** - References at decision points  
✅ **Automation support** - Scripts for common tasks  
✅ **30-42% context savings** - Typical use cases  

**Next Steps**: Get approval and begin implementation.

---

**Related Documents**:
- [Full Refactoring Plan](DJANGO_SKILL_REFACTORING_PLAN.md)
- [Executive Summary](DJANGO_REFACTORING_SUMMARY.md)
- [Before/After Comparison](DJANGO_REFACTORING_COMPARISON.md)

**Last Updated**: 2026-01-27
