# RULE_multi-tenant-safety

## Principle
Never access tenant data without explicit tenant context - all database queries must be schema-isolated.

## Details
Multi-tenant applications use separate database schemas for each tenant. Without proper tenant context, queries can accidentally access the wrong tenant's data or the public schema. The TenantMainMiddleware must run early to set request.tenant, and all database access must use tenant-aware patterns.

Models containing tenant-specific data must inherit from TenantModel (not use tenant_id foreign keys). Background tasks and WebSocket consumers must explicitly pass and verify tenant context to prevent cross-tenant data leaks.

## Examples
✅ **DO: Use tenant_context for database access**
```python
def get_articles_for_tenant(tenant):
    with tenant_context(tenant):
        return Article.objects.all()  # Guaranteed correct schema
```

❌ **DON'T: Query without tenant context**
```python
def get_articles():
    return Article.objects.all()  # ❌ Can access wrong schema
```

✅ **DO: Place TenantMainMiddleware early**
```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ✅ Must be early
    'django.middleware.common.CommonMiddleware',
    # ... other middleware
]
```

❌ **DON'T: Place tenant middleware too late**
```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
    'apps.auth.middleware.AuthMiddleware',
    'django_tenants.middleware.TenantMainMiddleware',  # ❌ Too late - other middleware runs without tenant context
]
```

✅ **DO: Use TenantModel for tenant-specific data**
```python
from django_tenants.models import TenantModel

class Article(TenantModel):  # ✅ Schema isolation
    title = models.CharField(max_length=200)
    content = models.TextField()
```

❌ **DON'T: Use tenant_id foreign keys**
```python
class Article(models.Model):  # ❌ Row-level filtering, not schema isolation
    tenant_id = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    title = models.CharField(max_length=200)
    content = models.TextField()
```

✅ **DO: Verify tenant access in views**
```python
class ArticleViewSet(viewsets.ModelViewSet):
    def get_queryset(self):
        # Automatic tenant scoping via TenantModel
        return Article.objects.all()

    def perform_create(self, serializer):
        # Tenant context set automatically
        serializer.save()
```

❌ **DON'T: Forget tenant context in custom queries**
```python
def get_tenant_users(tenant_id):
    # ❌ No tenant context - could access public or wrong schema
    return User.objects.filter(tenant_id=tenant_id)
```

✅ **DO: Pass tenant explicitly to background tasks**
```python
@shared_task
def process_tenant_data(tenant_id, data):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        # Process data in correct schema
        Article.objects.create(title=data['title'])
```

❌ **DON'T: Lose tenant context in async operations**
```python
async def websocket_receive(self, tenant_id, data):
    # ❌ No tenant context verification
    article = Article.objects.get(id=data['id'])  # Wrong schema possible
    await self.send(article.serialize())
```

## Why This Matters
Multi-tenant data leaks can expose sensitive customer information across organizations, violating compliance requirements (GDPR, HIPAA) and causing catastrophic security breaches. Schema isolation provides database-level guarantees, but only when tenant context is consistently applied. These guardrails prevent accidental cross-tenant access that could destroy trust and business relationships.