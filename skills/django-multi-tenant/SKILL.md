---
name: django-multi-tenant
description: Multi-tenant architecture using django-tenants for schema-per-tenant isolation, including tenant resolution, context propagation, and permission layers for data isolation.
license: MIT
compatibility: opencode
---

## Overview

Multi-tenant architecture patterns using django-tenants for schema-per-tenant isolation. Complete guide to implementing multi-tenancy in Django with separate database schemas per tenant, automatic tenant resolution, context propagation, and permission layers. Use when data isolation at the database level is required. Build on [SKILL.md](../django-architecture/SKILL.md) for core patterns.

## When to Use

- Building SaaS applications with tenant isolation requirements
- Need separate database schemas per tenant (schema-per-tenant model)
- Data isolation is critical (HIPAA, GDPR, financial data)
- Supporting multiple organizations with independent data
- Implementing row-level security with tenant awareness

**DO NOT USE if**:
- Single-tenant application (use SKILL_django-architecture instead)
- Row-level security is sufficient (use row-filtering instead)
- Shared schema with row-level filtering needed (different pattern)

## Context: Tenant vs. Organization Model

**Important terminology**:

In this skill and related skills ([SKILL.md](../django-celery-multitenant/SKILL.md), [SKILL.md](../django-async-websocket-multitenant/SKILL.md)):
- **Tenant**: The isolated database schema (managed by django-tenants)
- **Organization**: Business entity model (e.g., `Org` model in your app)
- Both are the same thing in different contexts

**How they relate**:
- Your project has an Organization/Customer model (the business entity)
- django-tenants creates a separate schema for each (database-level isolation)
- When you see examples referencing an `Org` model: it maps to a Tenant schema
- Use `tenant_context(org)` to switch schemas for database queries

**In related skills**:
- [SKILL.md](../django-celery-multitenant/SKILL.md) shows how to pass org_id to background tasks
- [SKILL.md](../django-async-websocket-multitenant/SKILL.md) shows how to handle org context in WebSocket consumers
- Both reference this skill for `tenant_context()` patterns

## Pattern

### Core Concept: Schema-Per-Tenant

**What it is**:
- Each tenant gets separate PostgreSQL schema
- Complete data isolation at database level
- Tenant A never sees Tenant B's data (enforced by database)
- Separate migrations per schema
- Zero risk of cross-tenant leaks from query bugs

**Why it's different from row-level filtering**:
- Row-level: Shared schema, filter `WHERE tenant_id = X` (error-prone)
- Schema-per-tenant: Separate schema per tenant (fool-proof)

**Example**: 
- Project A customer → schema `public_1`
- Project B customer → schema `public_2`
- Same models, complete isolation

### Installation & Configuration

```python
# requirements.txt
django-tenants>=3.5.0
psycopg2-binary>=2.9
```

**settings.py** (project root settings):

```python
# Database backend must use TenantAwareDatabaseRouter
DATABASES = {
    'default': {
        'ENGINE': 'django_tenants.postgresql_backend',
        'NAME': 'main_db',
        'USER': 'postgres',
        'PASSWORD': 'password',
        'HOST': 'db',  # Docker Compose service name
        'PORT': '5432',
    }
}

# Default schema (for non-tenant models, public data)
PUBLIC_SCHEMA_NAME = 'public'
TENANT_SCHEMA_PREFIX = 'public_'  # Schemas named: public_a, public_b, etc.

# Installed apps - order matters!
INSTALLED_APPS = [
    'django_tenants',  # ← MUST be first
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'rest_framework',
    'core',
    'auth',
    'api',
    '[feature]',
]

# Middleware - order matters!
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ← Early
    'django.middleware.csrf.CsrfViewMiddleware',
    'apps.core.middleware.RequestContextMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# Router for tenant-aware queries
DATABASE_ROUTERS = ('django_tenants.routers.TenantSyncRouter',)
```

### Tenant Model (Public Schema)

**Create tenant records** (lives in public schema, shared by all):

```python
# core/models.py - in public schema
from django_tenants.models import TenantMixin, DomainMixin

class Tenant(TenantMixin):
    """Tenant organization (lives in public schema)."""
    name = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    # Required by django-tenants
    auto_create_schema = True

    def __str__(self):
        return self.name

class Domain(DomainMixin):
    """Domain routing (route request to correct schema)."""
    domain = models.CharField(max_length=255, unique=True)
    tenant = models.OneToOneField(Tenant, on_delete=models.CASCADE)
    is_primary = models.BooleanField(default=True)

    def __str__(self):
        return self.domain
```

### User Model: Shared Across Orgs (Public Schema)

**Critical Design Decision**: User lives in **public schema**, not tenant schema!

```python
# core/models.py - in PUBLIC schema (shared by all orgs)
from django.contrib.auth.models import AbstractUser

class User(AbstractUser):
    """
    User model in public schema - same user can access multiple orgs.
    
    WHY: One person = one login = multiple org access
    - john@company.com belongs to "Fancy Hotels" and "Pizza Place"
    - Uses same token to access both orgs
    - Token identifies USER only, not org access (see UserScope)
    """
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'auth_user'  # Live in public schema

    def __str__(self):
        return self.email
    
    def get_orgs(self):
        """All orgs this user has access to."""
        return Org.objects.filter(
            scope__userscope__user=self
        ).distinct()
```

### The UserScope Pattern (Multi-Org Access)

**The key insight**: Junction model linking User → Scope → Org

```python
# core/models.py - in PUBLIC schema
class Scope(models.Model):
    """
    Permission group within an Org.
    
    Examples: "Hotel", "Restaurant", "Kitchen", "Admin", etc.
    Allows granular permissions (admin in Hotel, write in Restaurant)
    """
    org = models.ForeignKey(Org, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('org', 'name')

    def __str__(self):
        return f"{self.org.name}/{self.name}"


class UserScope(models.Model):
    """
    Links User to Scope (permission group) within Org.
    
    KEY to secure multi-org access:
    - User → many UserScopes → multiple Orgs
    - Same user, different permissions per scope
    - Token identifies user; UserScope grants org access
    """
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    scope = models.ForeignKey(Scope, on_delete=models.CASCADE)
    permission = models.CharField(
        max_length=20,
        choices=[
            ('read', 'Read'),
            ('write', 'Write'),
            ('admin', 'Admin'),
            ('approve', 'Approve'),
        ]
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'scope')
        indexes = [
            models.Index(fields=['user', 'scope']),
            models.Index(fields=['scope', 'permission']),
        ]

    def __str__(self):
        return f"{self.user.email} → {self.scope.name} ({self.permission})"
```

**Data Example** (same user, multiple orgs):
```
john@company.com (User in public schema)
├── UserScope #1: Scope="Hotel" (Org="Fancy Hotels"), Permission="admin"
├── UserScope #2: Scope="Restaurant" (Org="Fancy Hotels"), Permission="write"
└── UserScope #3: Scope="Kitchen" (Org="Pizza Place"), Permission="admin"

Result: john can access Fancy Hotels (as admin+write) and Pizza Place (as admin)
```

### Other Tenant-Specific Models

Models that ARE per-tenant use `TenantModel`:

```python
# articles/models.py - in TENANT schema
from django_tenants.models import TenantModel

class Article(TenantModel):
    """Article model - separate per tenant schema."""
    title = models.CharField(max_length=255)
    content = models.TextField()
    scope = models.ForeignKey(Scope, on_delete=models.CASCADE)
    # Note: Scope is in public schema, Article is in tenant schema
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.title
```

**Critical difference**: 
- `User`, `Scope`, `UserScope`, `Org` = live in public schema (shared)
- `Article`, `Category`, `[feature]` models = live in tenant schema (isolated per org)

### Tenant Resolution Middleware

**Resolve which tenant from request**:

```python
# core/middleware.py
from django_tenants.middleware import TenantMainMiddleware
from django_tenants.utils import tenant_context
from .models import Tenant, Domain

class TenantResolutionMiddleware(TenantMainMiddleware):
    """
    Resolve tenant from:
    1. X-Tenant-ID header (API calls)
    2. Domain name (web requests)
    3. Session (fallback)
    """
    
    def process_request(self, request):
        # Try header first (API)
        tenant_id = request.META.get('HTTP_X_TENANT_ID')
        if tenant_id:
            try:
                tenant = Tenant.objects.get(id=tenant_id)
                request.tenant = tenant
                request.session['tenant_id'] = tenant.id
                return super().process_request(request)
            except Tenant.DoesNotExist:
                return self._tenant_not_found(request)
        
        # Try domain (web)
        hostname = self.get_hostname(request)
        try:
            domain = Domain.objects.get(domain=hostname)
            request.tenant = domain.tenant
            request.session['tenant_id'] = domain.tenant.id
            return super().process_request(request)
        except Domain.DoesNotExist:
            # Try session fallback
            tenant_id = request.session.get('tenant_id')
            if tenant_id:
                try:
                    request.tenant = Tenant.objects.get(id=tenant_id)
                    return super().process_request(request)
                except Tenant.DoesNotExist:
                    return self._tenant_not_found(request)
            
            return self._tenant_not_found(request)

    def _tenant_not_found(self, request):
        """Tenant not found - reject request."""
        from django.http import JsonResponse
        return JsonResponse({'error': 'Tenant not found'}, status=404)
```

**Critical**: Middleware must run early in MIDDLEWARE list!

### Tenant Context Propagation

**Use tenant context in queries**:

```python
from django_tenants.utils import tenant_context
from django.http import JsonResponse

def get_user_articles(request):
    """Get articles for current user in current tenant."""
    # Automatically scoped to current tenant
    articles = Article.objects.filter(author=request.user)
    
    # request.tenant is set by middleware
    # Queries automatically use correct schema
    return JsonResponse({
        'tenant': request.tenant.name,
        'articles': [a.title for a in articles]
    })
```

**In code without request context** (signals, tasks, etc.):

```python
from django_tenants.utils import tenant_context
from django.db import connection

def process_report(tenant_id):
    """Process report for specific tenant (no request context)."""
    try:
        tenant = Tenant.objects.get(id=tenant_id)
    except Tenant.DoesNotExist:
        return
    
    # Switch to tenant schema explicitly
    with tenant_context(tenant):
        # All queries here use tenant's schema
        articles = Article.objects.all()  # ← Tenant schema
        for article in articles:
            article.process()
    
    # Back to public schema after context manager
```

### Authentication: Token-Based with UserScope

**Critical Pattern**: Token identifies USER only, not org access!

```python
# core/views.py - Authentication
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

class LoginView(APIView):
    """
    Login returns token that's GLOBAL (all orgs).
    Org access is verified separately via UserScope.
    """
    def post(self, request):
        email = request.data['email']
        password = request.data['password']
        
        try:
            user = User.objects.get(email=email)
            if user.check_password(password):
                # Token lives in public schema, identifies user only
                token, created = Token.objects.get_or_create(user=user)
                return Response({'token': token.key})
        except User.DoesNotExist:
            pass
        
        return Response({'error': 'Invalid credentials'}, status=401)
```

**API Flow with UserScope**:

```python
# User logs in once
POST /api/auth/login/
→ {"token": "abc123..."}

# List all accessible orgs
GET /api/user/orgs/
Authorization: Token abc123...
→ [
    {
        "id": 1,
        "name": "Fancy Hotels",
        "scopes": [
            {"name": "Hotel", "permission": "admin"},
            {"name": "Restaurant", "permission": "write"}
        ]
    },
    {
        "id": 2,
        "name": "Pizza Place",
        "scopes": [{"name": "Kitchen", "permission": "admin"}]
    }
  ]

# Set current org (context for subsequent requests)
POST /api/user/set-org/
Authorization: Token abc123...
{"org_id": 1}
→ Sets session/header for requests

# Access org-specific data
GET /api/articles/
Authorization: Token abc123...
X-Org-ID: 1  # Or from session
→ Checks:
   Layer 1: Token valid? → User john ✓
   Layer 2: john in Org 1? (has UserScope with scope.org=1) ✓
   Layer 3: john has write+ in any scope? ✓
→ Returns articles from Org 1

# Switch org (same token!)
POST /api/user/set-org/
Authorization: Token abc123...
{"org_id": 2}

# Access different org
GET /api/articles/
Authorization: Token abc123...
X-Org-ID: 2
→ Same token, different org data
```

**Why Token ≠ Access**:
- Token proves "I am john@company.com"
- UserScope proves "john is in this org with this permission"
- Token is global; UserScope is per-org
- If token auth fails, reject immediately
- If UserScope fails, user doesn't belong to that org

### 5-Layer Permission Checking

**Layer 1: Token Authentication**
```python
from rest_framework.authentication import TokenAuthentication

class ArticleViewSet(viewsets.ModelViewSet):
    authentication_classes = [TokenAuthentication]
    # Verifies: Valid token? → User object
```

**Layer 2: Organization Membership**
```python
class IsOrgMember(BasePermission):
    """User has ANY scope in this org."""
    def has_permission(self, request, view):
        return UserScope.objects.filter(
            user=request.user,
            scope__org=request.tenant
        ).exists()
```

**Layer 3: Organization Admin**
```python
class IsOrgAdmin(BasePermission):
    """User has admin permission in ANY scope in this org."""
    def has_permission(self, request, view):
        return UserScope.objects.filter(
            user=request.user,
            scope__org=request.tenant,
            permission__in=['admin', 'approve']
        ).exists()
```

**Layer 4: Scope-Specific Permission**
```python
class CanManageScope(BasePermission):
    """User has write+ in article's specific scope."""
    def has_object_permission(self, request, view, obj):
        return UserScope.objects.filter(
            user=request.user,
            scope=obj.scope,  # Article in specific scope
            permission__in=['write', 'admin', 'approve']
        ).exists()
```

**Layer 5: Cross-Scope Privilege Escalation Check**
```python
# When moving article between scopes, verify BOTH
class ArticleSerializer(serializers.ModelSerializer):
    def validate_scope(self, value):
        """Prevent privilege escalation by moving to inaccessible scope."""
        user = self.context['request'].user
        old_scope = self.instance.scope
        new_scope = value
        
        # Can user access old scope?
        can_leave = UserScope.objects.filter(
            user=user, scope=old_scope,
            permission__in=['write', 'admin']
        ).exists()
        
        # Can user access new scope?
        can_enter = UserScope.objects.filter(
            user=user, scope=new_scope,
            permission__in=['write', 'admin']
        ).exists()
        
        if not (can_leave and can_enter):
            raise ValidationError("Cannot move: no access to destination scope")
        
        return value
```

**Apply all layers**:

```python
class ArticleViewSet(viewsets.ModelViewSet):
    authentication_classes = [TokenAuthentication]  # Layer 1
    permission_classes = [
        IsAuthenticated,      # Must be logged in
        IsOrgMember,          # Layer 2: In org?
        IsOrgAdmin,           # Layer 3: Admin in org?
    ]
    
    def get_queryset(self):
        # Query scoped to current org/schema automatically
        return Article.objects.all()
    
    def get_permissions(self):
        """Add object-level checks for detail views."""
        permissions = super().get_permissions()
        if self.action in ['retrieve', 'update', 'destroy']:
            permissions.append(CanManageScope())  # Layer 4
        return permissions
```

### Permission & Security Layers

**Permission class for API**:

```python
# core/permissions.py
from rest_framework.permissions import BasePermission

class IsTenantUser(BasePermission):
    """User belongs to request tenant."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        # Verify user's tenant matches request tenant
        user_tenant = request.user.tenant
        request_tenant = request.tenant
        
        if user_tenant != request_tenant:
            return False  # Cross-tenant access denied
        
        return True

class IsTenantAdmin(BasePermission):
    """User is admin in request tenant."""
    def has_permission(self, request, view):
        if not IsTenantUser().has_permission(request, view):
            return False
        
        return request.user.role == 'admin'  # or use django-guardian
```

**ViewSet with tenant protection**:

```python
# api/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from core.permissions import IsTenantUser, IsTenantAdmin

class ArticleViewSet(viewsets.ModelViewSet):
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticated, IsTenantUser, IsTenantAdmin]
    
    def get_queryset(self):
        """Auto-scoped to current tenant."""
        # Queries automatically use correct schema
        return Article.objects.all()
    
    def perform_create(self, serializer):
        """Save with current tenant."""
        serializer.save(tenant=self.request.tenant)
```

### Common Pitfalls & Solutions

**❌ WRONG: Cross-tenant leak**

```python
# This can leak data if schema isn't set!
articles = Article.objects.all()  # Might get wrong schema
```

**✅ CORRECT: Explicit tenant context**

```python
# Explicitly use tenant context
with tenant_context(tenant):
    articles = Article.objects.all()  # Guaranteed correct schema
```

---

**❌ WRONG: Middleware ordering**

```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ❌ Too late!
    'apps.auth.middleware.AuthMiddleware',
]
```

**✅ CORRECT: TenantMainMiddleware early**

```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ✅ Early
    'django.middleware.common.CommonMiddleware',
    'apps.auth.middleware.AuthMiddleware',
]
```

---

**❌ WRONG: Shared models with tenant data**

```python
# This tries to be multi-tenant but isn't!
class Article(models.Model):
    tenant_id = models.ForeignKey(Tenant)  # ❌ Row-filtering
    title = models.CharField()
```

**✅ CORRECT: TenantModel for isolation**

```python
# Complete schema isolation
class Article(TenantModel):  # ✅ Separate schema per tenant
    title = models.CharField()
```

### Multi-Tenant Injection Points (10 Locations)

1. **models.py** - `TenantModel` for tenant-specific models
2. **middleware.py** - Tenant resolution and request.tenant setting
3. **permissions.py** - IsTenantUser, IsTenantAdmin checks
4. **views.py** - get_queryset() auto-scoped to tenant
5. **serializers.py** - create() saves with current tenant
6. **settings.py** - TenantAwareDatabaseRouter, middleware order
7. **urls.py** - (optional) tenant-specific URL patterns
8. **signals.py** - Pass tenant_id explicitly to background tasks
9. **consumers.py** - WebSocket: scope['tenant_id'] verification
10. **asgi.py** - Middleware for WebSocket tenant resolution

**Verify all 10 locations** when implementing multi-tenancy.

### Testing Multi-Tenant Setup

```python
# tests/test_multi_tenant.py
from django.test import TestCase, Client
from django_tenants.test.cases import TenantTestCase
from core.models import Tenant, Domain

class TenantIsolationTestCase(TenantTestCase):
    """Test that tenants are isolated."""
    
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Create test tenants
        cls.tenant_a = Tenant.objects.create(name='Tenant A')
        cls.tenant_b = Tenant.objects.create(name='Tenant B')
        
        # Create test users
        self.set_tenant(cls.tenant_a)
        cls.user_a = User.objects.create_user('user@a.com')
        
        self.set_tenant(cls.tenant_b)
        cls.user_b = User.objects.create_user('user@b.com')
    
    def test_user_a_cannot_see_user_b(self):
        """Verify schema isolation."""
        self.set_tenant(self.tenant_a)
        users = User.objects.all()
        self.assertEqual(users.count(), 1)  # Only tenant A's user
        self.assertEqual(users.first().email, 'user@a.com')
```

## Why It's Generic

- **django-tenants**: Industry-standard multi-tenancy package
- **Schema-per-tenant**: Proven pattern for data isolation
- **Middleware-based**: Works with any view type (FBV, CBV, ViewSet)
- **Compatible with**: DRF, Celery, WebSocket (with proper context)
- **Production-ready**: Battle-tested pattern used in production SaaS applications
- **Security-first**: Database-level isolation (no query bugs)

## Example Use Cases

- **SaaS platforms**: Each customer account gets isolated schema
- **Multi-organization apps**: Each org completely separate
- **Compliance-required systems**: Healthcare, finance, government (HIPAA, GDPR)
- **Data privacy**: Regulatory data isolation requirements
- **API platforms**: Each API customer's data isolated

## Related Skills

- [`SKILL_django-architecture.md`](../django-architecture/SKILL.md) - Core Django patterns (required foundation)
- [`SKILL_django-celery.md`](../django-celery/SKILL.md) - Background tasks with tenant context
- [`SKILL_django-async-websocket.md`](../django-async-websocket/SKILL.md) - Real-time with tenant context

## References

- [django-tenants Documentation](https://django-tenants.readthedocs.io/)
- [Django Database Router](https://docs.djangoproject.com/en/stable/topics/db/multi-db/)
- [Middleware Ordering](https://docs.djangoproject.com/en/stable/topics/http/middleware/)
- [Backwards Compatibility Tracking](../docs/BACKWARDS_COMPATIBILITY_TRACKING.md)

---

**Last Updated**: 2026-01-26