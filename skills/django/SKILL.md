---
name: django
description: Apply global cross-project Django backend dev conventions for models, views, signals, Channels, DRF, and all backend architecture before hitting templates or JS.
license: MIT
compatibility: opencode
metadata:
  author: mind-vault
  version: "4.1"
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
ASGI setup, database optimization, testing strategies, and development workflows.

**This skill covers**:
 - Project structure and organization
 - BaseModel abstractions (soft deletes, timestamps, BigAutoField)
 - Settings & environment configuration
 - DRF ViewSets, permissions, serializers
 - Mixins for reusable view functionality
 - Middleware patterns
 - ASGI configuration (basic)
 - Database optimization (N+1 prevention, batch operations, queryset patterns)
 - Performance monitoring
 - Logging configuration and audit trails
 - Translation workflows and locale handling
 - Testing patterns and best practices
 - Development workflow and environment management

**Optional Extensions** (load on-demand):
 - [Multi-Tenant Architecture](references/MULTI_TENANT.md) - Schema-per-tenant isolation
 - [Async WebSocket](references/ASYNC_WEBSOCKET.md) - Real-time communication
 - [Celery Background Tasks](references/CELERY.md) - Async job processing
 - [Logging Patterns](references/LOGGING.md) - Structured logging and monitoring
 - [Internationalization](references/I18N.md) - Translation workflows and locale handling
 - [Testing Patterns](references/TESTING.md) - Comprehensive testing strategies
 - [Development Workflow](references/DEVELOPMENT_WORKFLOW.md) - Environment config and processes

**Combined Patterns**:
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

**Primary key conventions**:
```python
class Article(BaseModel):
    # Use BigAutoField for primary keys (handles large datasets)
    id = models.BigAutoField(primary_key=True)
    title = models.CharField(max_length=255)
```

**Critical**: Always filter soft-deleted records:

```python
# Correct
Article.objects.filter(is_deleted=False)

# Wrong - includes deleted records!
Article.objects.all()  # ❌
```

### Schema-based Multi-tenancy vs FKs

When using purely schema-based multi-tenancy (e.g., `django-tenants`), **do not** place an `org` or `tenant` Foreign Key on models that reside in the tenant schema. The PostgreSQL schema provides the isolation.
- Use tenant-local BaseModel derivatives without an `org` FK for these tables.
- Reserve abstract mixins like `OwnedModel` (which contain the `org` FK) **strictly** for tables that live in the `public` schema (e.g. Users, Billing, Subscriptions, Organization directories).

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
```

**For comprehensive environment configuration patterns**: See [DEVELOPMENT_WORKFLOW.md](references/DEVELOPMENT_WORKFLOW.md)

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

### Permission DRY-ness via Probes

**Never duplicate authorization logic** between DRF `BasePermission` classes and standard Django views, forms, or template tags. Treat DRF permissions as the single source of truth.

When you need to evaluate permission in a non-DRF context, use a "permission probe" pattern to build a synthetic DRF request and feed it to the exact same `BasePermission` class:

```python
# Create a synthetic DRF request to reuse the DRF BasePermission
drf_request = build_drf_request(request, data=request.POST) 
has_perm = CanManageArticles().has_permission(drf_request, None)
```

### Mixins and Reusable Patterns

**Create mixins for common view functionality**:

```python
# core/mixins.py

class SoftDeleteMixin:
    """Handle soft delete operations."""
    def perform_destroy(self, instance):
        instance.soft_delete()

class AuditMixin:
    """Track who created/updated objects."""
    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)
    
    def perform_update(self, serializer):
        serializer.save(updated_by=self.request.user)

class HTMXMixin:
    """Handle HTMX requests and responses."""
    def get_template_names(self):
        if self.request.htmx:
            return [f"{self.model._meta.app_label}/partials/{self.model._meta.model_name}_form.html"]
        return super().get_template_names()
```

**Use mixins in views**:

```python
class ArticleViewSet(
    AuditMixin, SoftDeleteMixin,  # Reusable functionality
    viewsets.ModelViewSet
):
    queryset = Article.objects.filter(is_deleted=False)
    serializer_class = ArticleSerializer
```

### String Building with Optional Parts

When building strings from optional parts (append B to A, or use only B when A is empty), prefer `filter(None, [...])` + `join`:

```python
body = (base_value or "").strip()
if optional_part:
    line = "Label: " + optional_part
    body = "\n".join(filter(None, [body, line]))
```

- **Non-empty base**: both kept, joined by newline.
- **Empty base**: `filter(None, [...])` drops empty strings; result is just the new part.
- Avoids ternaries and explicit if/else for append vs replace logic.

### Formsets (modelformset with unique constraints)

When a model has a **UniqueConstraint** (e.g. `(author, preset)`), the formset must prevent duplicate rows or save will raise **IntegrityError** and leave the user with a 500.

**Pattern**:
1. **Formset-level validation**: Subclass `BaseModelFormSet`, override `clean()`, and collect the constrained field(s) from each form's `cleaned_data`. If any value is repeated (excluding deleted forms), raise `forms.ValidationError` with a clear message (e.g. "Duplicate reminder: you already have …").
2. **View safety net**: In the view, wrap the formset save loop in `try/except IntegrityError`. On exception, add an error message and re-render the form so the user can fix duplicates instead of seeing a 500.
3. **Shared table UI**: For multiple formsets (e.g. event reminders, profile defaults), use a shared partial (management form + table + add button) and a small JS module that handles TOTAL_FORMS, cloning the empty-form template, and reindexing on delete. Same contract (prefix, template id, tbody id, row class) keeps backend and frontend in sync.

**Why**: Duplicate (author, preset) is a common mistake when users add two rows with the same option; validating in the formset gives a clear error; catching IntegrityError handles races and edge cases.

### Date/time and timezone

**Centralize timezone handling** in one module (e.g. `core/timezone_utils.py`): `get_timezone_object`, `normalize_to_user_tz`, `validate_timezone_string`, `get_available_timezone_names`. Migrate all call sites (consumers, templatetags, auth forms/views) to use it so zoneinfo/pytz fallback and exception handling live in one place.

**Sensible date validation**: For forms and API that accept a `date` field, use shared constants (e.g. min/max from env) and a single `validate_sensible_date(value)` that raises `ValidationError` if out of range. Add widget attrs (min/max) for HTML5 date inputs from the same constants. Roll out incrementally (event/form serializer first, then other date-bearing forms when touched).

**All-day events and reminder time**: When exporting calendar events (e.g. iCal), for **date-only** (all-day) events use the user's **daily reminder time** (e.g. 09:00) so "1 day before" becomes that time on the previous day; export as absolute DATE-TIME in UTC. For timed events, keep relative TRIGGER (e.g. -PT15M). Compute the absolute trigger with a shared helper that takes event date, event time (or None), preset, user timezone, and daily_reminder_time.

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

**Queryset optimization patterns**:

```python
# List views - optimize for display
def get_queryset(self):
    return Article.objects.select_related(
        'category', 'author', 'scope'
    ).prefetch_related('tags').order_by('-created_at')

# Detail views - optimize for single object access
def get_queryset(self):
    return Article.objects.select_related(
        'category', 'category__parent', 'author', 'scope'
    ).prefetch_related('tags', 'events', 'events__attachments')
```

**When NOT to optimize**:
- Query used once with small result sets (< 10 items)
- Related objects not accessed in templates/views
- Performance impact negligible

**Test query optimization**:
```python
from django.test import TestCase

class ArticleTest(TestCase):
    def test_queryset_optimization(self):
        with self.assertNumQueries(2):  # Articles + prefetched tags
            articles = Article.objects.prefetch_related('tags')
            for article in articles:
                list(article.tags.all())
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
 - [Logging Patterns](references/LOGGING.md) - Structured logging and monitoring
 - [Internationalization](references/I18N.md) - Translation workflows and locale handling
 - [Testing Patterns](references/TESTING.md) - Comprehensive testing strategies
 - [Development Workflow](references/DEVELOPMENT_WORKFLOW.md) - Environment config and processes

**Combined Patterns**:
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md) - WebSocket with tenants
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md) - Tasks with tenants

**Deployment Integration**:
- [Deployment Skill](../../deployment/SKILL.md) - Production deployment patterns and automation

**Additional Resources**:
- [Forms & Validation](references/FORMS.md) - Form patterns and validation

## Scripts & Tools

**Automation helpers** (in `scripts/`):
- `run_tests.sh` - Comprehensive test execution with coverage reports

## External References

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimization](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
- [ASGI Specification](https://asgi.readthedocs.io/)
- [Daphne Documentation](https://github.com/django/daphne)

---

**Last Updated**: 2026-02-26
**Version**: 4.1
**Replaces**: django-architecture, django-async-websocket, django-celery, django-multi-tenant, django-celery-multitenant, django-async-websocket-multitenant