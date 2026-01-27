# Multi-Tenant Architecture

**Schema-per-tenant isolation using django-tenants**

## Core Concept: Schema-Per-Tenant

**What it is**:
- Each tenant gets separate PostgreSQL schema
- Complete data isolation at database level
- Tenant A never sees Tenant B's data (enforced by database)
- Separate migrations per schema
- Zero risk of cross-tenant leaks from query bugs

**Why it's different from row-level filtering**:
- Row-level: Shared schema, filter `WHERE tenant_id = X` (error-prone)
- Schema-per-tenant: Separate schema per tenant (fool-proof)

## Installation & Configuration

```python
# requirements.txt
django-tenants>=3.5.0
psycopg2-binary>=2.9

# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django_tenants.postgresql_backend',
        'NAME': 'main_db',
        'USER': 'postgres',
        'PASSWORD': 'password',
        'HOST': 'db',
        'PORT': '5432',
    }
}

PUBLIC_SCHEMA_NAME = 'public'
TENANT_SCHEMA_PREFIX = 'public_'

INSTALLED_APPS = [
    'django_tenants',  # ← MUST be first
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'rest_framework',
    # ... your apps
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ← Early!
    'django.middleware.common.CommonMiddleware',
    # ... other middleware
]

DATABASE_ROUTERS = ('django_tenants.routers.TenantSyncRouter',)
```

## Models: Public vs Tenant Schema

**Public schema models** (shared across all tenants):

```python
# core/models.py - PUBLIC SCHEMA
from django_tenants.models import TenantMixin, DomainMixin

class Tenant(TenantMixin):
    """Organization record in public schema."""
    name = models.CharField(max_length=255)
    auto_create_schema = True

class Domain(DomainMixin):
    """Domain routing to tenants."""
    domain = models.CharField(max_length=255, unique=True)
    tenant = models.OneToOneField(Tenant, on_delete=models.CASCADE)

class User(AbstractUser):
    """Users in public schema - can access multiple orgs."""
    email = models.EmailField(unique=True)

    class Meta:
        db_table = 'auth_user'  # Forces public schema
```

**Tenant schema models** (isolated per tenant):

```python
# articles/models.py - TENANT SCHEMA
from django_tenants.models import TenantModel

class Article(TenantModel):
    """Article in tenant schema - automatically isolated."""
    title = models.CharField(max_length=255)
    content = models.TextField()
    author = models.ForeignKey(User, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
```

**Critical difference**:
- `User` model in public schema (shared)
- `Article` model in tenant schema (isolated)

## Tenant Resolution Middleware

**Resolve tenant from request**:

```python
# core/middleware.py
from django_tenants.middleware import TenantMainMiddleware

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

**Critical**: `TenantMainMiddleware` must run early in MIDDLEWARE list!

## Tenant Context Propagation

**Automatic scoping in views** (with middleware):

```python
class ArticleViewSet(viewsets.ModelViewSet):
    def get_queryset(self):
        # Automatically scoped to current tenant schema
        return Article.objects.all()  # ← Safe: tenant schema only

    def perform_create(self, serializer):
        # Auto-scoped to current tenant
        serializer.save()  # ← Saves in tenant schema
```

**Explicit context** (no request context):

```python
from django_tenants.utils import tenant_context

def process_tenant_data(tenant_id, data):
    tenant = Tenant.objects.get(id=tenant_id)
    with tenant_context(tenant):
        # All queries use tenant's schema
        Article.objects.create(title=data['title'])
```

## Authentication Pattern

**Token identifies USER only, not org access**:

```python
# Login returns global token
class LoginView(APIView):
    def post(self, request):
        # Authenticate user
        user = User.objects.get(email=request.data['email'])
        if user.check_password(request.data['password']):
            token, _ = Token.objects.get_or_create(user=user)
            return Response({'token': token.key})

# API access requires both token AND org membership
class ArticleViewSet(viewsets.ModelViewSet):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsOrgMember]

    def get_queryset(self):
        return Article.objects.all()  # Scoped to current org
```

**Org membership verification**:

```python
class IsOrgMember(BasePermission):
    """User must belong to current org."""
    def has_permission(self, request, view):
        return UserScope.objects.filter(
            user=request.user,
            scope__org=request.tenant
        ).exists()
```

**Complete API authentication flow example**:

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

## UserScope Pattern (Multi-Org Access)

**Junction table for granular permissions**:

```python
class Scope(models.Model):
    """Permission group within org (e.g., 'Admin', 'Editor')."""
    org = models.ForeignKey(Org, on_delete=models.CASCADE)
    name = models.CharField(max_length=255)

class UserScope(models.Model):
    """User's permissions in specific scope."""
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    scope = models.ForeignKey(Scope, on_delete=models.CASCADE)
    permission = models.CharField(
        max_length=20,
        choices=[('read', 'Read'), ('write', 'Write'), ('admin', 'Admin')]
    )

    class Meta:
        unique_together = ('user', 'scope')
```

**Example**: john@company.com can be admin in "Hotel" scope but only write in "Restaurant" scope, both within the same organization.

## 5-Layer Permission Checking

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

## Common Pitfalls

**❌ Cross-tenant data leak**:
```python
# WRONG: No tenant context
articles = Article.objects.all()  # May access wrong schema
```

**✅ Correct**:
```python
# RIGHT: Explicit tenant context
with tenant_context(tenant):
    articles = Article.objects.all()  # Guaranteed correct schema
```

---

**❌ Wrong middleware order**:
```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ❌ Too late!
]
```

**✅ Correct order**:
```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ✅ Early!
    'django.middleware.common.CommonMiddleware',
]
```

---

**❌ Row-level filtering instead of schema isolation**:
```python
class Article(models.Model):  # ❌ Row filtering
    tenant_id = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    title = models.CharField(max_length=255)
```

**✅ Schema isolation**:
```python
class Article(TenantModel):  # ✅ Schema isolation
    title = models.CharField(max_length=255)
```

## Multi-Tenant Injection Points

1. **models.py** - Use `TenantModel` for tenant-specific data
2. **middleware.py** - Tenant resolution, set `request.tenant`
3. **permissions.py** - `IsOrgMember`, `IsOrgAdmin` checks
4. **views.py** - `get_queryset()` auto-scoped to tenant
5. **serializers.py** - `create()` saves in tenant schema
6. **settings.py** - `TenantAwareDatabaseRouter`, middleware order
7. **signals.py** - Pass `tenant_id` to background tasks
8. **consumers.py** - Verify `scope['tenant']` in WebSockets
9. **asgi.py** - Middleware for WebSocket tenant routing
10. **tests.py** - `TenantTestCase` for isolated testing

**Verify all 10 locations** when implementing multi-tenancy.

## Testing

```python
from django_tenants.test.cases import TenantTestCase

class TenantIsolationTest(TenantTestCase):
    def test_tenant_isolation(self):
        # Create test tenants
        tenant_a = Tenant.objects.create(name='Tenant A')
        tenant_b = Tenant.objects.create(name='Tenant B')

        # Switch to tenant A schema
        self.set_tenant(tenant_a)
        Article.objects.create(title='Tenant A Article')

        # Switch to tenant B schema
        self.set_tenant(tenant_b)
        articles = Article.objects.all()
        self.assertEqual(articles.count(), 0)  # Isolated!
```