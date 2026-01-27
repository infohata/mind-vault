---
name: django-celery-multitenant
description: Multi-tenant background task patterns extending Celery with schema-per-tenant isolation, focusing on propagating tenant context to background workers.
license: MIT
compatibility: opencode
---

# ⚠️ DEPRECATED: Use skills/django/SKILL.md instead

**This skill has been consolidated into the modular Django skill.**

**New location**: [skills/django/SKILL.md](../django/SKILL.md)

**For multi-tenant Celery patterns specifically, see**:
[skills/django/references/MULTI_TENANT_CELERY.md](../django/references/MULTI_TENANT_CELERY.md)

**Migration guide**:
- Core Django patterns → main SKILL.md
- Multi-tenant patterns → references/MULTI_TENANT.md
- Celery patterns → references/CELERY.md
- Multi-tenant + Celery → references/MULTI_TENANT_CELERY.md
- All patterns from this skill are preserved

**Deprecation timeline**: This file will be archived on **2026-02-27** (1 month from now).

---

## Overview

Multi-tenant patterns for background tasks using Celery with schema-per-tenant isolation. Extension of [SKILL.md](../django-celery/SKILL.md) showing how to propagate organization/tenant context to background workers. Use this skill when building Celery tasks for multi-tenant applications.

**Prerequisites**: Read [SKILL.md](../django-celery/SKILL.md) first (core patterns).

**Related**: [SKILL.md](../django-multi-tenant/SKILL.md) (tenant architecture), [SKILL.md](../django-async-websocket-multitenant/SKILL.md) (WebSocket with tenants)

## When to Use

- Building background tasks for multi-tenant applications
- Tasks need access to organization/tenant-specific data
- Using schema-per-tenant architecture (each tenant gets separate database schema)
- Tasks triggered by user actions in one tenant but must not access other tenants

**DO NOT USE if**:
- Single-tenant application
- Using row-level security instead of schema-per-tenant
- Tasks don't need tenant context (stateless tasks)

## Pattern

### Critical Principle: Pass Tenant Context Explicitly

Background workers have no request context. Pass `org_id` (or `tenant_id`) as an explicit task parameter. Use tenant_context() patterns to access the correct schema.

```python
# tasks.py
from celery import shared_task
from django.core.mail import send_mail

@shared_task(bind=True, max_retries=3)
def send_welcome_email(self, user_id, org_id):
    """
    Send welcome email to newly created user in specific organization.
    
    Args:
        user_id: User ID (in organization schema)
        org_id: Organization/Tenant ID (identifies which schema)
    """
    try:
        # Fetch organization to get tenant info
        org = Org.objects.get(id=org_id)
        
        # Switch to organization's schema for queries
        from django_tenants.utils import tenant_context
        with tenant_context(org):
            from django.contrib.auth.models import User
            user = User.objects.get(id=user_id)
        
        # Email operation (works without schema context)
        send_mail(
            subject='Welcome!',
            message=f'Hi {user.email}',
            from_email='noreply@example.com',
            recipient_list=[user.email],
        )
        
        return f'Email sent to {user.email}'
    
    except Org.DoesNotExist:
        return {'error': 'Organization not found'}
    
    except Exception as exc:
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

**Key points**:
- ✅ Always pass `org_id` to tasks (identifies tenant)
- ✅ Fetch organization from public schema first
- ✅ Use `tenant_context(org)` to switch schemas for queries
- ✅ Operations outside schema (email, API calls) work normally
- ❌ Never assume current schema is set in background worker
- ❌ Never reference org directly (serialize org_id only)

### Signal-Based Task Triggering with Tenant

```python
# models.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from .tasks import send_welcome_email

class User(AbstractUser):
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

@receiver(post_save, sender=User)
def user_created(sender, instance, created, **kwargs):
    """Trigger welcome email when user is created."""
    if created:
        # Get current tenant from signal context
        from django_tenants.utils import get_tenant_model
        Tenant = get_tenant_model()
        
        # Find org for this tenant (schema)
        org = Org.objects.get(tenant=Tenant.objects.current_tenant())
        
        send_welcome_email.delay(
            user_id=instance.id,
            org_id=org.id,  # Pass org_id explicitly
        )
```

### Task With Real-Time Feedback (Channels + Tenant)

```python
# tasks.py
from celery import shared_task
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django_tenants.utils import tenant_context

@shared_task(bind=True)
def process_file_for_tenant(self, file_id, org_id, channel_name=None):
    """
    Process file in background with tenant context and progress updates.
    
    Args:
        file_id: File ID in tenant schema
        org_id: Organization/Tenant ID
        channel_name: Channels group for WebSocket updates
    """
    try:
        # Get organization
        org = Org.objects.get(id=org_id)
        
        # Work in tenant schema
        with tenant_context(org):
            from uploads.models import File
            file_obj = File.objects.get(id=file_id)
            
            channel_layer = get_channel_layer()
            
            # Process with progress updates
            for step in range(1, 11):
                process_chunk(file_obj, step)
                
                # Send progress (works outside schema context)
                if channel_name:
                    async_to_sync(channel_layer.group_send)(
                        channel_name,
                        {
                            'type': 'file_progress',
                            'progress': step * 10,
                            'status': 'processing',
                        }
                    )
                
                self.update_state(
                    state='PROGRESS',
                    meta={'current': step, 'total': 10}
                )
        
        return {'status': 'complete', 'file_id': file_id, 'org_id': org_id}
    
    except Org.DoesNotExist:
        return {'error': 'Organization not found'}
    
    except Exception as exc:
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

### Error Handling With Tenant Context

```python
# tasks.py
from celery import shared_task
from django_tenants.utils import tenant_context
import requests

@shared_task(bind=True, max_retries=5)
def sync_external_data(self, org_id):
    """Sync data from external API into tenant schema."""
    try:
        org = Org.objects.get(id=org_id)
        
        # Call external API (no schema needed)
        response = requests.get(
            'https://api.example.com/data',
            timeout=10
        )
        response.raise_for_status()
        data = response.json()
        
        # Save to tenant schema
        with tenant_context(org):
            save_data_to_org(data)
        
        return {'status': 'synced', 'records': len(data), 'org_id': org_id}
    
    except Org.DoesNotExist:
        # Permanent - org was deleted
        return {'error': 'Organization not found'}
    
    except requests.exceptions.Timeout as exc:
        # Transient - retry
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    
    except ValueError as exc:
        # Permanent - bad data
        return {'error': 'Invalid data from API'}

def save_data_to_org(data):
    """Save data (assumes tenant_context is already set)."""
    # Implementation depends on your models
    pass
```

### Common Pitfalls

**❌ WRONG: Passing organization object to task**

```python
@shared_task
def process_for_org(self, org):  # ❌ Serialization issues
    with tenant_context(org):
        ...
```

**✅ CORRECT: Pass org_id only**

```python
@shared_task
def process_for_org(self, org_id):  # ✅ ID is serializable
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        ...
```

---

**❌ WRONG: Forgetting tenant context**

```python
@shared_task
def process_tenant_data(self, file_id, org_id):
    # Queries without context - wrong schema!
    file = File.objects.get(id=file_id)  # ❌ Might be in public schema
```

**✅ CORRECT: Always use tenant_context**

```python
@shared_task
def process_tenant_data(self, file_id, org_id):
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        file = File.objects.get(id=file_id)  # ✅ Correct schema
```

---

**❌ WRONG: Complex logic assumes single tenant**

```python
@shared_task
def bulk_operation(self, data):
    # Assumes all data is from current tenant
    for item in data:
        Model.objects.create(**item)  # ❌ Which tenant?
```

**✅ CORRECT: Include org_id in bulk operations**

```python
@shared_task
def bulk_operation(self, data, org_id):
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        for item in data:
            Model.objects.create(**item)  # ✅ Correct tenant
```

### Celery + Tenant Injection Points

1. **settings.py** - CELERY configuration (same as single-tenant)
2. **celery.py** - App setup (same as single-tenant)
3. **tasks.py** - Tasks now include `org_id` parameter
4. **models.py** - Signals must extract `org_id` before calling `.delay()`
5. **views.py** - Pass `request.org_id` or `current_org.id` to tasks
6. **signals.py** - Any custom signals must include `org_id`

**Key difference from single-tenant**: Always extract and pass `org_id` when triggering tasks.

## Why It's Generic

- **Schema-per-tenant**: Standard multi-tenant pattern with django-tenants
- **Tenant context propagation**: Works with any organization/tenant model
- **Signal patterns**: Django's decoupling, extended with org awareness
- **Error handling**: Same principles as single-tenant (categorize errors)
- **Retry strategies**: Exponential backoff, independent of tenancy
- **Channels integration** (optional): Works with WebSocket consumers

## Example Use Cases

- **Multi-tenant SaaS**: Process tenant-specific operations in background
- **Multi-organization apps**: Bulk imports/exports per organization
- **Compliance systems**: Generate reports per tenant, isolated data
- **Integration platforms**: Sync external data into specific tenant schema
- **Email/notifications**: Send organization-specific communications

## Related Skills

- [`SKILL_django-multi-tenant.md`](../django-multi-tenant/SKILL.md) - `tenant_context()` reference implementation
- [`SKILL_django-async-websocket-multitenant.md`](../django-async-websocket-multitenant/SKILL.md) - Similar patterns for WebSocket

## References

- [Celery Documentation](https://docs.celeryproject.org/)
- [django-tenants](https://django-tenants.readthedocs.io/)
- [Django Signals](https://docs.djangoproject.org/en/stable/topics/signals/)
- [tenant_context() documentation](https://django-tenants.readthedocs.io/en/latest/use.html#using-django-tenants)

---

**Last Updated**: 2026-01-27