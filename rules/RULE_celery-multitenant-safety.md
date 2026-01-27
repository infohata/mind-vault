# RULE_celery-multitenant-safety

## Principle
Always pass tenant context explicitly to background tasks - never assume schema is set in workers.

## Details
Background task workers don't inherit tenant context from the calling request. All tasks must receive tenant_id as a parameter and establish tenant context using tenant_context() before any database operations. Complex objects (tenant instances, user objects) cannot be serialized - only IDs should be passed.

Bulk operations and any task that processes multiple records must include tenant verification to prevent cross-tenant data processing. Task parameters should be minimal and serializable.

## Examples
✅ **DO: Pass tenant_id to all tasks**
```python
@shared_task
def process_tenant_file(file_id, tenant_id):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        file_obj = File.objects.get(id=file_id)
        # Process file in correct tenant schema
        return process_file(file_obj)
```

❌ **DON'T: Assume tenant context in tasks**
```python
@shared_task
def process_tenant_file(file_id):
    # ❌ No tenant context - which schema?
    file_obj = File.objects.get(id=file_id)
    return process_file(file_obj)
```

✅ **DO: Pass tenant_id in bulk operations**
```python
@shared_task
def bulk_import_data(data_list, tenant_id):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        for data in data_list:
            Model.objects.create(**data)
```

❌ **DON'T: Process bulk data without tenant verification**
```python
@shared_task
def bulk_import_data(data_list):
    # ❌ Which tenant? Could process in wrong schema
    for data in data_list:
        Model.objects.create(**data)
```

✅ **DO: Pass tenant_id from signals**
```python
@receiver(post_save, sender=Document)
def trigger_processing(sender, instance, **kwargs):
    if kwargs.get('created'):
        process_document.delay(
            document_id=instance.id,
            tenant_id=instance.tenant.id  # ✅ Explicit tenant
        )
```

❌ **DON'T: Trigger tasks without tenant context**
```python
@receiver(post_save, sender=Document)
def trigger_processing(sender, instance, **kwargs):
    process_document.delay(document_id=instance.id)  # ❌ Missing tenant_id
```

✅ **DO: Use tenant_context in task error handling**
```python
@shared_task(bind=True, max_retries=3)
def process_with_tenant_context(self, data_id, tenant_id):
    try:
        tenant = get_tenant_by_id(tenant_id)
        with tenant_context(tenant):
            data = Data.objects.get(id=data_id)
            return process_data(data)
    except Data.DoesNotExist:
        # Tenant context needed even for error logging
        with tenant_context(tenant):
            logger.error(f"Data {data_id} not found in tenant {tenant.name}")
        raise self.retry(countdown=60)
```

❌ **DON'T: Lose tenant context during retries**
```python
@shared_task(bind=True, max_retries=3)
def process_with_tenant_context(self, data_id, tenant_id):
    try:
        tenant = get_tenant_by_id(tenant_id)
        with tenant_context(tenant):
            data = Data.objects.get(id=data_id)
            return process_data(data)
    except Data.DoesNotExist:
        logger.error(f"Data {data_id} not found")  # ❌ No tenant context for logging
        raise self.retry(countdown=60)
```

✅ **DO: Verify tenant access before processing**
```python
@shared_task
def send_tenant_notification(user_id, tenant_id, message):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        user = User.objects.get(id=user_id)
        # Verify user belongs to tenant
        if user.tenant != tenant:
            raise ValueError("User does not belong to tenant")
        send_notification(user, message)
```

❌ **DON'T: Skip tenant membership verification**
```python
@shared_task
def send_tenant_notification(user_id, tenant_id, message):
    tenant = get_tenant_by_id(tenant_id)
    with tenant_context(tenant):
        user = User.objects.get(id=user_id)  # ❌ Could be user from different tenant
        send_notification(user, message)
```

## Why This Matters
Background tasks lose all request context, including tenant schema. Without explicit tenant propagation, tasks can accidentally process data in the wrong tenant schema, causing data corruption, privacy violations, or compliance failures. These guardrails ensure tenant isolation is maintained in asynchronous operations, preventing cross-tenant data leaks that could compromise the entire multi-tenant application.