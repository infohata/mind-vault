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

**get_current_tenant() vs connection.tenant**:

**✅ GOOD**: Use helper function for thread-safe tenant access
```python
from django_tenants.utils import get_current_tenant

def get_queryset(self):
    current_tenant = get_current_tenant()  # ✅ Handles all cases, thread-safe
    if not current_tenant:
        return Article.objects.none()
    return Article.objects.filter(org=current_tenant)
```

**❌ BAD**: Direct access to connection.tenant
```python
from django.db import connection

def get_queryset(self):
    current_tenant = connection.tenant  # ❌ Not thread-safe, doesn't handle FakeTenant
    return Article.objects.filter(org=current_tenant)
```

**Why**: `get_current_tenant()` properly handles `FakeTenant` instances used internally by django-tenants and ensures consistent behavior across all execution contexts.

### Pass explicit tenant over ambient connection state

`get_current_tenant()` reads `connection.tenant` — set by tenant-resolution middleware on the request thread, OR by an explicit `tenant_context(...)` / `set_tenant(...)` wrapper in background code. **When a function already holds the `Org` instance locally, pass it explicitly rather than relying on the ambient read.**

The ambient call works "today" because some caller upstream set it. The bug surfaces silently the day someone refactors that caller — the ambient state isn't there anymore, `get_current_tenant()` returns `None`, and your fallback path silently degrades (returns empty results, builds a wrong-host URL, writes to the wrong schema). No exception, no log entry; just wrong output.

**❌ FRAGILE**: depends on caller's tenant-context wrapper, defeats local reasoning
```python
def _load_attachments_by_ids(self, org_id: int, ids: List[int]) -> List[Dict]:
    with schema_context("public"):
        org = Org.objects.get(id=org_id)
    db_connection.set_tenant(org)
    qs = Attachment.objects.filter(id__in=ids)

    # Helper looks up tenant via ambient connection.tenant — works because
    # `set_tenant(org)` above set it. But if a future refactor moves the
    # set_tenant into a wrapper that this method no longer calls, the
    # helper silently falls back to {} and returns broken URLs.
    return AttachmentSerializer(
        qs, many=True, context=tenant_aware_serializer_context(),
    ).data
```

**✅ EXPLICIT**: function holds `org` locally — pass it through
```python
def _load_attachments_by_ids(self, org_id: int, ids: List[int]) -> List[Dict]:
    with schema_context("public"):
        org = Org.objects.get(id=org_id)
    db_connection.set_tenant(org)
    qs = Attachment.objects.filter(id__in=ids)

    # Helper signature: tenant_aware_serializer_context(tenant=None, ...).
    # When the tenant is already in scope, pass it. The helper stops
    # depending on whatever upstream set the ambient state.
    return AttachmentSerializer(
        qs, many=True, context=tenant_aware_serializer_context(tenant=org),
    ).data
```

**The principle generalises**: any helper that reads thread-local / connection-local / contextvar state has the same fragility class. If the caller already holds the canonical object (a tenant, a user, a request), pass it. The "ambient" read is the last-resort default for callers that genuinely don't know.

**When ambient is the right call**: at the boundary where the request first arrives — middleware, view, consumer's `connect()`. By the time you're three function calls deep, the boundary already resolved the value; pass it.

## DRF serializer context for request-less callers

DRF serializers commonly read `self.context['request']` to build URLs that depend on the request domain — `SerializerMethodField` for presigned S3 / MinIO URLs, `FileField.to_representation` calling `request.build_absolute_uri(file.url)`, custom hyperlink fields. **When a non-HTTP caller invokes the same serializer (WebSocket consumer, Celery task, AI tool executor, management command), `request` is missing — and the URL silently falls back to an internal Docker hostname.**

The failure shape:

1. `AttachmentSerializer.get_file_url(obj)` calls `generate_presigned_url(obj.file, request=self.context.get('request'))`.
2. Caller didn't pass context → `request` is `None`.
3. `generate_presigned_url(file, request=None)` falls through to `settings.AWS_S3_ENDPOINT_URL = 'http://minio:9000'`.
4. URL signed against internal hostname; `/storage/` nginx-proxy prefix step is skipped.
5. Browser receives `http://minio:9000/...?X-Amz-...` → `DNS_PROBE_FINISHED_NXDOMAIN`.
6. The bug is invisible in dev (single-tenant, `minio:9000` happens to be in `/etc/hosts` for the docker network) and surfaces only when a multi-tenant production user clicks the link.

The same bug class bites any project that:

- Uses DRF serializers, AND
- Has at least one non-HTTP caller path (WebSocket consumer, Celery task, AI tool executor, management command, signal handler), AND
- Returns URLs to clients (S3 presigned URLs, absolute hyperlinks for emails, tenant-aware redirects).

### The fix shape

Build a **request stub** at the call site that carries the four attributes DRF actually reads — `.scheme`, `.get_host()`, `.user`, `.build_absolute_uri()` — and put it in serializer context. The stub is duck-typed; DRF doesn't introspect the type, only attribute access.

```python
# core/utils.py (or equivalent in your project)

def make_request_for_host(public_host: str, user=None):
    """Duck-typed HTTP request for callers without a real one.

    Returns an object satisfying the four DRF / generate_presigned_url
    contracts:
    - .scheme            ('http' or 'https', derived from public_host)
    - .get_host()         host portion of public_host
    - .user               (forwarded if caller has one)
    - .build_absolute_uri(location)  Django-compatible absolute-URL builder
    """
    scheme = "https" if public_host.startswith("https") else "http"
    host = public_host.replace("https://", "").replace("http://", "").split("/")[0]

    class _Request:
        def __init__(self, s, h, u):
            self.scheme = s
            self._host = h
            self.user = u

        def get_host(self):
            return self._host

        def build_absolute_uri(self, location=None):
            if location is None:
                return f"{self.scheme}://{self._host}/"
            if location.startswith(("http://", "https://", "//")):
                return location
            if not location.startswith("/"):
                location = "/" + location
            return f"{self.scheme}://{self._host}{location}"

    return _Request(scheme, host, user)


def tenant_aware_serializer_context(tenant=None, user=None) -> dict:
    """DRF serializer context dict carrying a tenant-aware request stub.

    Returns {'request': <stub>} when a tenant primary domain can be
    resolved, else {}. Use this whenever DRF serializers must produce
    browser-reachable URLs but no HttpRequest is available.
    """
    t = tenant or get_current_tenant()
    if not t:
        return {}
    public_url = get_tenant_primary_domain_url(t)
    if not public_url:
        logger.warning(
            "tenant_aware_serializer_context: no primary domain for tenant id=%s",
            getattr(t, "id", "?"),
        )
        return {}
    return {'request': make_request_for_host(public_url, user=user)}
```

### Four attributes, not two

A naive stub with only `.scheme` and `.get_host()` will crash on `request.build_absolute_uri(file.url)` — DRF's `FileField.to_representation` calls it on the bare `file` field, separately from any custom `SerializerMethodField`. Likewise `.user` is read by `EventSerializer.to_representation` for permission probes (e.g. notes-stripping) and `ArticleSerializer.create` for `validated_data['author']`. Build the stub with all four upfront — discovering each gap mid-PR-review adds cycles.

### Don't try to "fix it in env"

The temptation is to set `AWS_S3_CUSTOM_DOMAIN` (or equivalent) to a single public hostname in production env. **In multi-tenant, that breaks every other tenant.** The codebase's "URL host derived from request domain" design is intentional; the fix is to thread the request to the serializer, not to hardcode a single host.

### Don't refactor `generate_presigned_url`

It's tempting to make `generate_presigned_url` smart enough to call `get_current_tenant()` itself when `request=None`. Resist — that couples a low-level signing helper to tenant context, fighting separation of concerns. The helper's contract (give me a request, I'll sign for that domain; give me nothing, I'll sign for the internal endpoint) is correct; the bug is callers passing `None` when they shouldn't.

## Schema Context Management

**Accessing public schema models** (shared across tenants):

```python
from django_tenants.utils import schema_context

with schema_context('public'):
    orgs = Org.objects.all()  # Query public schema
    domains = Domain.objects.filter(tenant=org)
```

**Tenant schema access**:

```python
from django_tenants.utils import tenant_context

tenant = Tenant.objects.get(id=tenant_id)
with tenant_context(tenant):
    articles = Article.objects.all()  # Query tenant schema
```

## WebSocket Consumers and Async Database Operations

**CRITICAL**: When using `@database_sync_to_async` in WebSocket consumers, tenant context from middleware does NOT automatically transfer to sync threads because Django's connection object is thread-local.

**✅ GOOD**: Explicit tenant context in async consumers
```python
from channels.db import database_sync_to_async
from django_tenants.utils import tenant_context

class ChatConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        # Tenant is set in scope by TenantChannelsMiddleware
        self.tenant = self.scope.get('tenant')
    
    @database_sync_to_async
    def get_conversation(self, conversation_id: str, tenant):
        """Get conversation with tenant context."""
        # CRITICAL: Set tenant context for this sync thread
        with tenant_context(tenant):
            return Conversation.objects.get(
                id=conversation_id,
                org=tenant
            )
```

**❌ BAD**: Assuming tenant context transfers automatically
```python
@database_sync_to_async
def get_conversation(self, conversation_id: str, tenant):
    # ❌ BAD: Tenant context from middleware doesn't transfer to sync threads
    # This will fail or query wrong schema!
    return Conversation.objects.get(id=conversation_id, org=tenant)
```

**Why**: `TenantChannelsMiddleware` sets tenant in one thread (via `@sync_to_async`), but `@database_sync_to_async` runs in different threads. Django's connection object is thread-local, so context doesn't transfer automatically. Always wrap database operations with `tenant_context(tenant)`.

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

## Serializer Validation and Scope Permissions

**Automatic tenant filtering in serializers**:

```python
class ArticleSerializer(serializers.ModelSerializer):
    category = serializers.PrimaryKeyRelatedField(
        queryset=Category.objects.none()  # Will be filtered by tenant
    )
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        current_tenant = get_current_tenant()
        if current_tenant:
            self.fields['category'].queryset = Category.objects.filter(org=current_tenant)
```

**ManyToMany scope validation** (CRITICAL for security):

**✅ GOOD**: Validate scope matching BEFORE database operations
```python
class ArticleSerializer(serializers.ModelSerializer):
    tag_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        allow_empty=True
    )
    
    def validate(self, attrs):
        """Validate tag scope matching before database operations."""
        tag_ids = attrs.get('tag_ids')
        
        if tag_ids is not None:
            current_tenant = get_current_tenant()
            if not current_tenant:
                return attrs
            
            # Get article scope (from instance for update, from attrs for create)
            article_scope = None
            if self.instance:
                # Update: use new scope if being updated, otherwise existing scope
                article_scope = attrs.get('scope', self.instance.scope)
            else:
                # Create: get scope from attrs
                article_scope = attrs.get('scope')
            
            if not article_scope:
                return attrs
            
            # Validate tags belong to current tenant AND match article scope
            tags = Tag.objects.filter(id__in=tag_ids, org=current_tenant, scope=article_scope)
            found_tag_ids = set(tags.values_list('id', flat=True))
            requested_tag_ids = set(tag_ids)
            
            invalid_ids = requested_tag_ids - found_tag_ids
            if invalid_ids:
                raise serializers.ValidationError({
                    'tag_ids': [f'Invalid tag IDs or tags from different scope: {sorted(invalid_ids)}']
                })
        
        return attrs
```

**Scope change permission validation** (CRITICAL for security):

**✅ GOOD**: Validate scope change permissions before database operations
```python
from kb.utils import check_scope_change_permissions

if 'scope' in update_data:
    is_allowed, error_message = check_scope_change_permissions(
        user=user,
        current_scope=object.scope,  # Source scope
        new_scope=update_data['scope'],  # Destination scope
        org=current_tenant
    )
    
    if not is_allowed:
        return {'error': error_message}  # or raise ValidationError
```

**Scope change validation utility**:
```python
def check_scope_change_permissions(user, current_scope, new_scope, org):
    """
    Users must have write/admin permissions for BOTH source and destination scopes.
    Prevents privilege escalation by moving content to inaccessible scopes.
    """
    # Can user access old scope?
    can_leave = UserScope.objects.filter(
        user=user, scope=current_scope,
        permission__in=['write', 'admin']
    ).exists()
    
    # Can user access new scope?
    can_enter = UserScope.objects.filter(
        user=user, scope=new_scope,
        permission__in=['write', 'admin']
    ).exists()
    
    if not (can_leave and can_enter):
        return False, "No permission to move content between these scopes"
    
    return True, None
```

**Why scope validation matters**:
- Prevents cross-scope data access (security vulnerability)
- Validates permissions BEFORE database operations
- Defense in depth: multiple validation layers
- Prevents privilege escalation attacks

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

### Tearing down a real tenant in tests (cross-schema cascade trap)

A test that exercises a **from-nothing** provision (a seed that creates the Org +
its schema + runs migrations) can't use `TenantTestCase`'s rolled-back atomic
block — the schema creation is real DDL. Use a non-atomic `TransactionTestCase`
against a **throwaway uuid schema name**, and tear down explicitly.

The trap: `org.delete()` (the ORM cascade) **fails** from the default/public
connection. The deletion collector walks every reverse FK onto the tenant row and
its public dependents — and some of those tables live in the *tenant* schema, not
public. Two ways it bites:

1. `admin` is typically a TENANT_APP, so `django_admin_log` (FK → `User`) lives in
   the tenant schema. Deleting a public `User` from the public connection runs
   `SELECT ... FROM django_admin_log ...`, which isn't on the public search-path →
   `ProgrammingError: relation "django_admin_log" does not exist`.
2. Public `Property`/`Scope`/`Org` have reverse FKs from tenant-schema content
   (`Article.property`, `Event.scope`, …). The collector queries those tenant
   tables from the public connection → same error.

`schema_context(tenant)` doesn't save you — the ORM delete resets the connection
schema mid-collection. The reliable teardown drops the schema first (raw DDL), then
**raw-SQL-deletes** the public rows, bypassing the ORM collector entirely (this is
also what a production org-deletion view does):

```python
class SeedProvisionTests(TransactionTestCase):   # NOT TestCase — real DDL
    def setUp(self):
        self.schema = f"seedtest_{uuid.uuid4().hex[:12]}"  # throwaway, unique

    def tearDown(self):
        org = Org.objects.filter(schema_name=self.schema).first()
        if org is None:
            return
        org._drop_schema(force_drop=True)        # drop tenant schema (DDL)
        with schema_context("public"):
            with connection.cursor() as c:        # raw deletes — no ORM cascade
                for tbl, col in [("userscope", "org_id"), ("property", "org_id"),
                                 ("scope", "org_id"), ("domain", "tenant_id")]:
                    c.execute(f"DELETE FROM <app>_{tbl} WHERE {col} = %s", [org.id])
                # synthetic global users created by the seed (after their FKs):
                c.execute("DELETE FROM <app>_user WHERE username LIKE %s", ["seed-%"])
                c.execute("DELETE FROM <app>_org WHERE id = %s", [org.id])
```

`auto_drop_schema` defaults to `True` on `TenantMixin` — but `org.delete()` (which
would trigger it) is exactly the call that fails above, so call `_drop_schema(
force_drop=True)` directly. For a foreign-org fixture you only need a Domain row
(not a full schema), set `org.auto_create_schema = False` before `save()` to skip
the migration cost.

Pairs with [`IDEMPOTENT_SEED_COMMANDS.md`](IDEMPOTENT_SEED_COMMANDS.md) (the seed
these tests exercise).