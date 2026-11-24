# Multi-Tenant + Celery

**Background tasks with tenant context**

## Critical Principle: Pass Tenant Context Explicitly

Background workers have no request context. Pass `org_id` as an explicit task parameter. Use `tenant_context()` to access the correct schema.

```python
from celery import shared_task

@shared_task(bind=True, max_retries=3)
def send_welcome_email(self, user_id, org_id):
    """
    Send welcome email to user in specific organization.

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

**Key principles**:
✅ **Pass org_id to tasks** - Identifies tenant/schema
✅ **Fetch organization first** - From public schema
✅ **Use tenant_context(org)** - Switch schemas for queries
✅ **Operations outside schema** - Email, API calls work normally
❌ **Never assume current schema** - In background workers
❌ **Never reference org directly** - Serialize org_id only

## Signal-Based Triggering with Tenant

```python
from django.db.models.signals import post_save
from django.dispatch import receiver

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

## Task With Real-Time Feedback (Channels + Tenant)

```python
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

## Error Handling With Tenant Context

```python
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
```

## Common Pitfalls

**❌ Passing organization object to task**:
```python
@shared_task
def process_for_org(self, org):  # ❌ Serialization issues
    with tenant_context(org):
        ...
```

**✅ Pass org_id only**:
```python
@shared_task
def process_for_org(self, org_id):  # ✅ ID is serializable
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        ...
```

---

**❌ Forgetting tenant context**:
```python
@shared_task
def process_tenant_data(self, file_id, org_id):
    file = File.objects.get(id=file_id)  # ❌ Wrong schema!
```

**✅ Always use tenant_context**:
```python
@shared_task
def process_tenant_data(self, file_id, org_id):
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        file = File.objects.get(id=file_id)  # ✅ Correct schema
```

---

**❌ Complex logic assumes single tenant**:
```python
@shared_task
def bulk_operation(self, data):
    for item in data:
        Model.objects.create(**item)  # ❌ Which tenant?
```

**✅ Include org_id in bulk operations**:
```python
@shared_task
def bulk_operation(self, data, org_id):
    org = Org.objects.get(id=org_id)
    with tenant_context(org):
        for item in data:
            Model.objects.create(**item)  # ✅ Correct tenant
```

---

**❌ Assuming `django_celery_results` rows live in one schema**:

With django-tenants + the `django-db` result backend, the worker writes each `TaskResult` row through its **tenant-aware connection** — into whichever schema the connection's `search_path` points at when the task finishes. Over months the "current writer" silently drifts between schemas as tenant context shifts; a production audit found ~28.5k rows scattered across **6 schemas**, each frozen at a different date (the public copy looked like writes "stopped" — they had just moved).

Consequences:

- **Audits and purges must sweep every schema** that has the table, not just `public`:

  ```sql
  select table_schema from information_schema.tables
  where table_name = 'django_celery_results_taskresult';
  -- then count/delete per schema
  ```

- **`celery.backend_cleanup` only cleans the schema it happens to run in** — it cannot be the retention strategy here.
- **The real fix is upstream**: `CELERY_TASK_IGNORE_RESULT = True` (see CELERY.md § Task Hygiene) so the rows aren't written at all; the backend stays installed for explicit opt-in tasks.
- Forensics caveat: without `CELERY_RESULT_EXTENDED = True`, `task_name` is NULL on every row — per-task breakdowns are unrecoverable after the fact.

## A worker refusing a just-provisioned tenant

Incident: a long-running Celery worker raised "tenant unknown" for a task about a tenant provisioned seconds earlier. The test passed locally and failed on the faster CI runner.

Cause: the worker learns new tenants only by re-reading the central registry. A miss is rate-limited (at most one refresh per N seconds) to protect the central DB. A task that arrived inside that window, right after provisioning, was refused.

Fix: the publisher stamps each task with the registry version it saw. On the worker, that claim proves the tenant existed when the task was sent, so it forces an immediate refresh. Unclaimed misses stay rate-limited: anyone can send a request with a made-up Host header, and a miss must not cost the central DB a query. A tenant still unknown after the refresh is refused (fail closed).

```python
# core/tenancy/registry.py
import threading
import time


class UnknownTenant(LookupError):
    pass


class TenantRegistry:
    """Per-process cache of tenant routes. load() -> (version, {tenant_id: route});
    the version increases on every provisioning."""

    def __init__(self, load, min_refresh_interval=30.0, clock=time.monotonic):
        self._load = load
        self._interval = min_refresh_interval
        self._clock = clock
        self._lock = threading.Lock()
        self.version, self._routes = load()
        self._last_refresh = clock()

    def resolve(self, tenant_id, claimed_version=None):
        route = self._routes.get(tenant_id)
        if route is not None:
            return route
        with self._lock:
            route = self._routes.get(tenant_id)  # another thread may have refreshed meanwhile
            if route is None:
                claim = claimed_version is not None and claimed_version > self.version
                due = self._clock() - self._last_refresh >= self._interval
                if claim or due:  # an unclaimed miss waits for the interval
                    self.version, self._routes = self._load()
                    self._last_refresh = self._clock()
                    route = self._routes.get(tenant_id)
        if route is None:
            raise UnknownTenant(tenant_id)  # still unknown after a refresh: fail closed
        return route
```

```python
# core/tenancy/celery_signals.py — publisher stamps, worker reads
from celery.signals import before_task_publish

from core.tenancy.registry import UnknownTenant
from core.tenancy.runtime import registry  # the process-wide TenantRegistry


@before_task_publish.connect
def stamp_route_version(headers=None, **kwargs):
    headers.setdefault("route_version", registry.version)


# in a task (bind=True), or in a base Task class:
#     route = registry.resolve(tenant_id, getattr(self.request, "route_version", None))
```

Checked on Celery 5.7 with the memory transport: a header set by `before_task_publish`, or passed as `apply_async(headers=...)`, reaches the worker as `self.request.route_version`.

- **Take claims only from a channel your own code writes.** Task headers qualify, since only your publishers put messages on the broker. Request input (Host, query string, client headers) never qualifies.
- **A claim newer than the version after a refresh** means the worker reads a lagging replica, or the claim is forged. Refuse the task and let Celery retry it with a countdown. Never accept the tenant on the claim alone.
- **This applies beyond DB-per-tenant routing.** Any tenant lookup cached per process (a domain → schema map, a tenant settings cache) has the same window.

Test: give the worker's registry a very long refresh interval, so only the claim can teach it about the new tenant. Provision, publish, and assert the task resolves. A second task naming a tenant that does not exist must still be refused. Against the old code, the first assertion fails every time; on a short interval it fails only on fast machines, which is how the incident hid.

```python
worker_registry = TenantRegistry(load, min_refresh_interval=10_000)
provision("t2")                                       # bumps the central version
assert route_for.delay("t2").get(timeout=10) == "db_t2"
assert route_for.delay("missing").get(timeout=10) == "REFUSED"
```

✅ DO: a miss with a claim newer than the cached version → refresh now; still missing → refuse.
❌ DON'T: shorten the refresh interval until CI goes green. The window shrinks but is still there, and every unclaimed miss then costs a central-DB query.
❌ DON'T: refresh on every miss. A stream of requests for made-up tenants then becomes a stream of queries against the central DB.

## Injection Points

1. **settings.py** - CELERY configuration (same as single-tenant)
2. **celery.py** - App setup (same as single-tenant)
3. **tasks.py** - Tasks now include `org_id` parameter
4. **models.py** - Signals must extract `org_id` before calling `.delay()`
5. **views.py** - Pass `request.org_id` or `current_org.id` to tasks
6. **signals.py** - Any custom signals must include `org_id`

**Key difference from single-tenant**: Always extract and pass `org_id` when triggering tasks.