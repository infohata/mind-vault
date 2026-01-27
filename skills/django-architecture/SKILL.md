---
name: django-architecture
description: Core Django project architecture patterns including BaseModel abstractions, DRF conventions, ASGI setup, and common DRY patterns for organizing models, views, and middleware.
license: MIT
compatibility: opencode
---

## Overview

Core Django project architecture patterns for organizing models, views, serializers, and middleware. Covers BaseModel abstractions, DRF conventions, ASGI setup, and common DRY patterns. This skill covers standard Django architecture without multi-tenancy, Celery, or async/WebSocket specifics - see separate skills for those.

## When to Use

- Starting a new Django project
- Organizing app structure and models
- Setting up DRF viewsets and permissions
- Configuring middleware and ASGI
- Extracting common patterns into mixins/base classes
- Optimizing database queries
- Adding performance monitoring

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
    ├── project/                    # Project settings (same name as repo)
    │   ├── __init__.py
    │   ├── settings.py             # Main settings
    │   ├── asgi.py                 # Async Server Gateway Interface
    │   ├── wsgi.py                 # (if using traditional deployment)
    │   └── urls.py                 # Root URL configuration
    ├── core/                       # Shared utilities, abstract models
    │   ├── models.py               # BaseModel, abstract classes
    │   ├── mixins.py               # QuerySet and ViewSet mixins
    │   ├── permissions.py          # Custom permission classes
    │   ├── serializers.py          # Base serializers
    │   ├── decorators.py           # Reusable decorators
    │   └── middleware.py
    ├── auth/                       # Authentication app
    │   ├── models.py
    │   ├── serializers.py
    │   ├── urls.py
    │   ├── mixins.py
    │   ├── views/                  # Modular views (split by purpose)
    │   │   ├── __init__.py         # Consolidation facade
    │   │   ├── api.py              # REST API ViewSets
    │   │   ├── web.py              # Web class-based views
    │   │   ├── invitations.py      # Invitation workflow views
    │   │   └── utils.py            # Helper functions
    │   ├── tests/                  # Tests mirror views structure
    │   │   ├── __init__.py
    │   │   ├── test_api.py
    │   │   ├── test_web.py
    │   │   ├── test_invitations.py
    │   │   └── test_permissions.py
    │   ├── locale/                 # User-facing translations (gettext)
    │   ├── templates/auth/         # App-specific templates
    │   └── static/auth/            # App-specific static files
    ├── api/                        # Main API endpoints
    │   ├── models.py
    │   ├── views.py
    │   ├── serializers.py
    │   ├── urls.py
    │   ├── locale/
    │   ├── templates/api/
    │   ├── static/api/
    │   └── tests/
    ├── [feature]/                  # Feature-specific apps
    │   ├── models.py
    │   ├── views.py
    │   ├── serializers.py
    │   ├── urls.py
    │   ├── permissions.py
    │   ├── locale/
    │   ├── templates/[feature]/
    │   ├── static/[feature]/
    │   └── tests/
    ├── static/                     # Collected static files (production)
    │   ├── admin/
    │   ├── auth/
    │   ├── api/
    │   └── [feature]/
    ├── locale/                     # Compiled translations (production)
    └── logs/                       # Application logs
```

**Why `web/` subdirectory**:
- Clean separation: Infrastructure (docker-compose, nginx, docs, tools) at repo root
- Docker-friendly: `web/` service mounts to `/app` in container
- Django code self-contained: `web/` has everything Django needs
- Easy to find: All Django apps at one level (not scattered)

**Within `web/`, apps use flat structure (Django convention)**:
- Django auto-discovers `templates/` and `static/` within each app
- `locale/` contains source translations (gettext .po files)
- Run `python manage.py collectstatic` to gather app static files to root `static/`
- Nginx serves compiled static files directly (not through Django)

**In settings.py, register apps by their module name**:
```python
# web/project/settings.py
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'rest_framework',
    'core',          # Not 'apps.core'
    'auth',          # Not 'apps.auth'
    'api',           # Not 'apps.api'
    '[feature]',
]
```

**Docker Compose mounts `web/` to container**:
```yaml
services:
  web:
    build: .
    working_dir: /app           # Maps to web/ directory
    command: daphne -b 0.0.0.0 -p 8000 project.asgi:application
    volumes:
      - ./web:/app              # ← Mount web/ to /app
```

**Note**: The `project/` directory name should match your actual project name. Using the same name for both root and settings directory is Django convention and avoids confusion with `app.config`.

**Why this structure**:
- Each app is self-contained (models, views, serializers, permissions)
- `core/` app centralizes shared patterns (mixins, decorators, base classes)
- Static and templates separate from code
- Easy to find and modify patterns
- Follows Django conventions for discoverability

### BaseModel Abstraction

**Create abstract base models to reduce duplication**:

```python
# apps/core/models.py
from django.db import models
from django.utils import timezone

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
        self.is_deleted = True
        self.save(update_fields=['is_deleted', 'updated_at'])

    def restore(self):
        """Restore soft-deleted record."""
        self.is_deleted = False
        self.save(update_fields=['is_deleted', 'updated_at'])
```

**Use in your models**:

```python
class Article(BaseModel):
    title = models.CharField(max_length=255)
    content = models.TextField()
    author = models.ForeignKey(User, on_delete=models.CASCADE)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title
```

**Critical**: Always filter soft-deleted records in queries:

```python
# Correct: Exclude soft-deleted
Article.objects.filter(is_deleted=False)

# Wrong: Forgets soft-delete filter!
Article.objects.all()  # ❌ Includes deleted records
```

### Settings & Configuration

**Organize settings with environment variables**:

```python
# project/settings.py (where 'project' is your actual project name)
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

# Feature gates (enable features without code changes)
FEATURE_ENABLE_ELASTICSEARCH = os.getenv('FEATURE_ENABLE_ELASTICSEARCH', 'false').lower() == 'true'
FEATURE_ENABLE_CACHING = os.getenv('FEATURE_ENABLE_CACHING', 'true').lower() == 'true'

# Sensible defaults with overrides
SEARCH_TIMEOUT = int(os.getenv('SEARCH_TIMEOUT', '3'))  # seconds
API_TIMEOUT = int(os.getenv('API_TIMEOUT', '30'))       # seconds
BATCH_SIZE = int(os.getenv('BATCH_SIZE', '1000'))       # for bulk operations
```

**Why this pattern**:
- Configuration lives in environment, not code
- Same codebase works dev/staging/production
- Defaults work for development
- Feature gates allow A/B testing without deployment

### Modular Views & Tests (Split by Purpose)

**Don't use monolithic `views.py`** - Split into submodules by purpose/domain:

```python
# auth/views/__init__.py - Consolidation facade
from .api import UserViewSet, OrgViewSet, InvitationViewSet
from .web import UserListView, UserDetailView, SettingsView
from .invitations import InvitationAcceptView, InvitationRejectView

__all__ = [
    'UserViewSet', 'OrgViewSet', 'InvitationViewSet',
    'UserListView', 'UserDetailView', 'SettingsView',
    'InvitationAcceptView', 'InvitationRejectView',
]
```

```python
# auth/views/api.py - REST API endpoints only
from rest_framework import viewsets
from ..models import User, Org
from ..serializers import UserSerializer, OrgSerializer

class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    
    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

class OrgViewSet(viewsets.ModelViewSet):
    queryset = Org.objects.all()
    serializer_class = OrgSerializer
    # ...
```

```python
# auth/views/web.py - Web class-based views
from django.views.generic import ListView, DetailView
from ..models import User
from ..mixins import UserOwnershipMixin

class UserListView(ListView):
    model = User
    template_name = 'auth/user_list.html'
    context_object_name = 'users'
    paginate_by = 50

class UserDetailView(UserOwnershipMixin, DetailView):
    model = User
    template_name = 'auth/user_detail.html'
```

```python
# auth/views/invitations.py - Complex invitation workflow
from django.views import View
from ..models import Invitation
from ..serializers import InvitationSerializer

class InvitationAcceptView(View):
    """Handle invitation acceptance with security checks."""
    def post(self, request, token):
        try:
            invitation = Invitation.objects.get(token=token)
            invitation.accept(user=request.user)
            return JsonResponse({'status': 'accepted'})
        except Invitation.DoesNotExist:
            return JsonResponse({'error': 'Invalid token'}, status=400)

class InvitationRejectView(View):
    # Similar pattern...
```

**Mirror test structure to match views**:

```python
# auth/tests/test_api.py - API tests
from rest_framework.test import APITestCase
from ..models import User

class UserViewSetTestCase(APITestCase):
    def test_create_user(self):
        response = self.client.post('/api/users/', {...})
        self.assertEqual(response.status_code, 201)

# auth/tests/test_web.py - Web view tests
from django.test import TestCase, Client
from ..models import User

class UserListViewTestCase(TestCase):
    def test_list_displays_users(self):
        response = self.client.get('/users/')
        self.assertEqual(response.status_code, 200)

# auth/tests/test_invitations.py - Complex workflow tests
class InvitationWorkflowTestCase(TestCase):
    def test_invitation_accept_creates_user(self):
        # ...
```

**Why split views and tests**:
- ✅ Keep files under 1000 LOC (manageable, readable)
- ✅ Agent context stays focused (fewer imports per file)
- ✅ Easy to find related code (api.py = all API views)
- ✅ Tests mirror structure (test_api.py = tests for api.py)
- ✅ Reduce merge conflicts (different developers can work on api.py vs web.py)
- ✅ Clear separation of concerns (REST vs web vs workflows)

**Consolidation pattern** (safe refactoring):
- `__init__.py` imports and exports all views
- Code outside the app imports from consolidation facade: `from auth.views import UserViewSet`
- Internal refactoring (move view to different file) doesn't break external imports
- Single source of truth for what's exported

### DRF Patterns

**Base ViewSet with common functionality**:

```python
# apps/core/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

class BaseViewSet(viewsets.ModelViewSet):
    """Base viewset with common functionality."""
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """Override to add common optimizations."""
        queryset = super().get_queryset()
        # Add select_related/prefetch_related as needed
        return queryset

    def perform_create(self, serializer):
        """Hook for additional logic on create."""
        serializer.save()

    def perform_update(self, serializer):
        """Hook for additional logic on update."""
        serializer.save()
```

**Permission classes for authorization**:

```python
# apps/core/permissions.py
from rest_framework.permissions import BasePermission

class IsResourceOwner(BasePermission):
    """Only allow resource owner to modify."""
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user

class HasRequiredRole(BasePermission):
    """Check if user has required role."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        return request.user.role == self.required_role
```

**Use permissions in viewsets**:

```python
class ArticleViewSet(BaseViewSet):
    queryset = Article.objects.filter(is_deleted=False)
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticated, IsResourceOwner]
```

### Middleware Patterns

**Custom middleware for request context**:

```python
# apps/core/middleware.py
class RequestContextMiddleware:
    """Add context to request for downstream use."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Store user info on request
        request.user_context = {
            'user_id': request.user.id if request.user.is_authenticated else None,
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
    'django.middleware.csrf.CsrfViewMiddleware',
    'apps.core.middleware.RequestContextMiddleware',  # Your custom middleware
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
```

**Critical**: Middleware order matters! Context-setting middleware should run early.

### Static Files & Templates (Per-App)

**Django auto-discovers app-level static and templates**:

```python
# apps/auth/static/auth/css/auth.css - App-specific CSS
body.auth-page {
    background: #f0f0f0;
}
```

```python
# apps/auth/templates/auth/login.html - App-specific template
{% extends "base.html" %}
{% load static %}

{% block content %}
<div class="login-container">
    <img src="{% static 'auth/images/logo.png' %}" />
    <!-- ... -->
</div>
{% endblock %}
```

**Internationalization (i18n) workflow**:

```bash
# In each app directory, create locale structure for translations
python manage.py makemessages -l es  # Extract strings for Spanish

# apps/auth/locale/es/LC_MESSAGES/django.po
msgid "Welcome"
msgstr "Bienvenido"

# Compile translations
python manage.py compilemessages
```

**Production static file handling**:

```bash
# Collect all app static files to root static/ directory
python manage.py collectstatic --noinput

# Result: root static/ now contains all app static files
# static/
#   ├── admin/
#   ├── auth/css/auth.css
#   ├── api/js/api.js
#   └── [feature]/...
```

**Nginx configuration** (serves static directly, not through Django):

```nginx
server {
    listen 80;
    server_name example.com;

    # Serve static files directly (fast, no Django overhead)
    location /static/ {
        alias /path/to/project/static/;
    }

    # Serve media uploads
    location /media/ {
        alias /path/to/project/media/;
    }

    # Everything else goes to Django
    location / {
        proxy_pass http://127.0.0.1:8000;
    }
}
```

**Why per-app structure**:
- Django auto-discovers templates and static within apps (no configuration needed)
- Each app is truly self-contained (templates, CSS, JS live together)
- Easier to move/delete/test apps in isolation
- `collectstatic` handles the heavy lifting for production
- Nginx serves compiled static files (not Django)

### ASGI Configuration (Daphne)

**Pragmatic single-server setup with Daphne**:

```python
# project/asgi.py (where 'project' is your actual project name)
import os
from django.core.asgi import get_asgi_application
from django.urls import path

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')

# Initialize Django ASGI application
django_asgi_app = get_asgi_application()

async def application(scope, receive, send):
    """Single entry point for all HTTP/WebSocket."""
    if scope['type'] == 'http':
        await django_asgi_app(scope, receive, send)
    else:
        # WebSocket handling (see SKILL_django-async-websocket)
        await django_asgi_app(scope, receive, send)
```

**docker-compose.yml**:

```yaml
version: '3.8'
services:
  # HTTP + WebSocket on same server (Daphne)
  web:
    build: .
    command: daphne -b 0.0.0.0 -p 8000 project.asgi:application
    ports:
      - "8000:8000"
    depends_on:
      - postgres

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=project_db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### Common Abstractions - Mixins

**Reduce boilerplate with queryable mixins**:

```python
# apps/core/mixins.py
class SoftDeleteMixin:
    """Automatically filter out soft-deleted objects."""
    def get_queryset(self):
        return super().get_queryset().filter(is_deleted=False)

class TimestampMixin:
    """Add created_at/updated_at to list views."""
    def get_queryset(self):
        queryset = super().get_queryset()
        return queryset.order_by('-created_at')

class OptimizedQueryMixin:
    """Apply select_related/prefetch_related automatically."""
    select_related_fields = []
    prefetch_related_fields = []

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.select_related_fields:
            queryset = queryset.select_related(*self.select_related_fields)
        if self.prefetch_related_fields:
            queryset = queryset.prefetch_related(*self.prefetch_related_fields)
        return queryset
```

**Use in viewsets**:

```python
class ArticleViewSet(SoftDeleteMixin, OptimizedQueryMixin, BaseViewSet):
    queryset = Article.objects.all()
    serializer_class = ArticleSerializer
    select_related_fields = ['author']
    prefetch_related_fields = ['comments']
```

### Database Optimization

**Prevent N+1 query problems**:

```python
# Wrong: N+1 queries
articles = Article.objects.all()
for article in articles:
    print(article.author.name)  # ❌ One query per article!

# Correct: Select related (one-to-one, foreign key)
articles = Article.objects.select_related('author')
for article in articles:
    print(article.author.name)  # ✅ Only 2 queries total

# Correct: Prefetch related (many-to-many, reverse foreign key)
articles = Article.objects.prefetch_related('comments')
for article in articles:
    for comment in article.comments.all():  # ✅ Only 2 queries total
        print(comment.text)
```

**Batch operations**:

```python
# Inefficient: Loop with individual saves
for article in articles:
    article.status = 'published'
    article.save()  # ❌ One query per article!

# Efficient: Batch update
Article.objects.filter(
    status='draft'
).update(status='published')  # ✅ One query!

# Batch create
articles = [
    Article(title=f"Article {i}", author=user)
    for i in range(1000)
]
Article.objects.bulk_create(articles, batch_size=100)  # ✅ Efficient!
```

### Performance Monitoring

**Decorator-based timing and alerting**:

```python
# apps/core/decorators.py
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
                        f"{operation_name} took {elapsed_ms:.1f}ms (threshold: {warn_threshold_ms}ms)"
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

## Why It's Generic

- **BaseModel pattern**: Used across any Django project needing soft deletes and timestamps
- **Settings management**: Environment-based config standard for production apps
- **DRF conventions**: ViewSets, permissions, serializers are DRF best practices
- **Middleware**: Request context handling applies to any Django project
- **ASGI**: Daphne setup relevant for any project needing WebSocket support
- **Mixins**: Query optimization patterns reusable across models/views
- **Database optimization**: N+1 prevention, batch operations apply universally

These patterns **don't require multi-tenancy, Celery, or async** - they're core Django architecture applicable to any size project.

## Example Use Cases

- **REST APIs**: Any REST API project uses ViewSet + permission patterns
- **Content management**: Soft deletes, timestamps, performance monitoring
- **SaaS applications**: BaseModel abstraction, middleware, query optimization
- **Dashboard applications**: DRF + permissions for role-based access
- **Knowledge bases**: Complex data models, soft deletes, query optimization

## Related Skills

- [`SKILL_django-multi-tenant.md`](../django-multi-tenant/SKILL.md) - If using multi-tenancy, extends BaseModel
- [`SKILL_django-celery.md`](../django-celery/SKILL.md) - If using background tasks
- [`SKILL_django-async-websocket.md`](../django-async-websocket/SKILL.md) - If using real-time features

## References

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimization](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
- [ASGI Specification](https://asgi.readthedocs.io/)
- [Daphne Documentation](https://github.com/django/daphne)

---

**Last Updated**: 2026-01-26