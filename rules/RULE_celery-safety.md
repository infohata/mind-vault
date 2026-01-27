# RULE_celery-safety

## Principle
Background tasks must never access request context or complex objects - all required data must be passed as simple parameters.

## Details
Celery tasks execute in background workers without access to Django's request context (request.user, request.session, etc.). Tasks also lose any in-memory state from the calling thread. All task parameters must be serializable (no model instances, complex objects, or file handles).

Error handling must distinguish between transient failures (network timeouts, temporary service unavailability) that should be retried, and permanent failures (invalid data, authentication errors) that should fail fast. Tasks should implement timeouts to prevent worker starvation.

## Examples
✅ **DO: Pass only IDs as parameters**
```python
@shared_task
def send_welcome_email(user_id):
    user = User.objects.get(id=user_id)
    send_mail(to=user.email, ...)
```

❌ **DON'T: Access request context in tasks**
```python
@shared_task
def send_welcome_email():
    user = request.user  # NameError: request doesn't exist
    send_mail(to=user.email, ...)
```

✅ **DO: Categorize errors for proper retry behavior**
```python
@shared_task(bind=True, max_retries=5)
def sync_external_api(self):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
    except requests.exceptions.Timeout as exc:
        # Transient - retry with backoff
        raise self.retry(exc=exc, countdown=60 * (2 ** self.request.retries))
    except ValueError as exc:
        # Permanent - fail fast
        return {'error': 'Invalid data provided'}
```

❌ **DON'T: Retry on permanent errors**
```python
@shared_task(bind=True, max_retries=5)
def sync_external_api(self):
    response = requests.get(url)  # Retries forever on auth failures, bad data, etc.
    return response.json()
```

✅ **DO: Use timeouts to prevent worker blocking**
```python
@shared_task
def download_file(url):
    response = requests.get(url, timeout=30)  # Prevents hanging
    return process_file(response.content)
```

❌ **DON'T: Allow synchronous operations to block workers**
```python
@shared_task
def download_file(url):
    response = requests.get(url)  # No timeout - can hang indefinitely
    return process_file(response.content)
```

## Why This Matters
Improper task design can lead to data corruption (using stale request context), worker starvation (hanging tasks), infinite retry loops, or security issues (passing sensitive objects). These guardrails ensure reliable, scalable background task processing that doesn't compromise system stability or data integrity.