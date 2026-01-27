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
    def process_request(self, request):
        # Try X-Tenant-ID header first (API calls)
        tenant_id = request.META.get('HTTP_X_TENANT_ID')
        if tenant_id:
            try:
                tenant = Tenant.objects.get(id=tenant_id)
                request.tenant = tenant
                return super().process_request(request)
            except Tenant.DoesNotExist:
                return JsonResponse({'error': 'Tenant not found'}, status=404)

        # Try domain name (web requests)
        hostname = self.get_hostname(request)
        try:
            domain = Domain.objects.get(domain=hostname)
            request.tenant = domain.tenant
            return super().process_request(request)
        except Domain.DoesNotExist:
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