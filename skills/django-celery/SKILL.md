---
name: django-celery
description: Background task patterns with Celery for reliable asynchronous job processing, including error handling, retry strategies, and Channels integration for single-tenant Django projects.
license: MIT
compatibility: opencode
---

# ⚠️ DEPRECATED: Use skills/django/SKILL.md instead

**This skill has been consolidated into the modular Django skill.**

**New location**: [skills/django/SKILL.md](../django/SKILL.md)

**For Celery patterns specifically, see**:
[skills/django/references/CELERY.md](../django/references/CELERY.md)

**Migration guide**:
- Core Django patterns → main SKILL.md
- Celery-specific patterns → references/CELERY.md
- All patterns from this skill are preserved

**Deprecation timeline**: This file will be archived on **2026-02-27** (1 month from now).

---

## Overview

Background task patterns using Celery for asynchronous job processing in Django. Complete guide to implementing reliable async tasks with error handling, retry strategies, and Channels integration for real-time updates. Single-tenant projects only.

**For multi-tenant projects**: See [SKILL.md](../django-celery-multitenant/SKILL.md)

## When to Use

- Implementing background tasks that don't block user requests
- Sending emails, generating reports, processing files asynchronously
- Long-running operations triggered by user actions
- Scheduled jobs (cron-like tasks)
- Integration with Celery + Redis + Channels for real-time feedback

**DO NOT USE if**:
- Task is critical path (user must wait for result)
- Task needs synchronous database lock
- No task queue infrastructure available
- Using multi-tenant architecture (use [SKILL.md](../django-celery-multitenant/SKILL.md))

## Pattern

### Critical Principle: No Request Context in Tasks

Tasks run in background workers **without request context**. You cannot access `request.user`, `request.session`, or any request-specific data. All required context must be passed explicitly as task parameters.

### Installation & Configuration

```python
# requirements.txt
celery>=5.3.0
redis>=4.5.0
```

**settings.py** (at `web/project/settings.py`):

```python
# Celery Configuration
CELERY_BROKER_URL = 'redis://redis:6379/0'  # Redis for task queue
CELERY_RESULT_BACKEND = 'redis://redis:6379/0'  # Result storage
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'

# Task execution settings
CELERY_TASK_TRACK_STARTED = True  # Track task status
CELERY_TASK_TIME_LIMIT = 30 * 60  # 30 minutes hard limit
CELERY_TASK_SOFT_TIME_LIMIT = 25 * 60  # 25 minutes soft limit (signals)

# Timezone consistency
CELERY_TIMEZONE = 'UTC'
CELERY_ENABLE_UTC = True

# Retry settings
CELERY_TASK_AUTORETRY_FOR = (Exception,)  # Retry on any exception
CELERY_TASK_MAX_RETRIES = 3  # Max 3 attempts
CELERY_TASK_DEFAULT_RETRY_DELAY = 60  # Wait 60s between retries
```

**celery.py** (at `web/project/celery.py`):

```python
import os
from celery import Celery

# Set default Django settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')

app = Celery('project')
app.config_from_object('django.conf:settings', namespace='CELERY')

# Auto-discover tasks from all apps
app.autodiscover_tasks()

@app.task(bind=True)
def debug_task(self):
    """Test task to verify Celery is working."""
    print(f'Request: {self.request!r}')
```

**asgi.py** (Channels integration):

```python
import os
import django
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')
django.setup()

from myapp.routing import websocket_urlpatterns

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': AuthMiddlewareStack(
        URLRouter(websocket_urlpatterns)
    ),
})
```

### Core Task Pattern

```python
# tasks.py - in an app (auth/tasks.py, core/tasks.py, api/tasks.py)
from celery import shared_task
from django.core.mail import send_mail

@shared_task(bind=True, max_retries=3)
def send_welcome_email(self, user_id):
    """
    Send welcome email to newly created user.
    
    Args:
        user_id: ID of user to email
    """
    from django.contrib.auth.models import User
    
    try:
        # Fetch user from database (explicit)
        user = User.objects.get(id=user_id)
        
        # Send email
        send_mail(
            subject='Welcome!',
            message=f'Hi {user.email}',
            from_email='noreply@example.com',
            recipient_list=[user.email],
        )
        
        return f'Email sent to {user.email}'
    
    except User.DoesNotExist:
        # User was deleted - don't retry
        return {'error': 'User not found'}
    
    except Exception as exc:
        # Transient error - retry with exponential backoff
        retry_delay = 60 * (2 ** self.request.retries)  # 60s, 120s, 240s
        raise self.retry(exc=exc, countdown=retry_delay)
```

**Key principles**:
- ✅ Pass all required IDs as explicit parameters
- ✅ Fetch context from database (no request object available)
- ✅ Categorize errors: permanent errors return result, transient errors retry
- ✅ Use exponential backoff for retries
- ❌ Don't access `request` object (doesn't exist in background worker)
- ❌ Don't assume current user is set

### Signal-Based Task Triggering

**Models trigger tasks via Django signals**:

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
        send_welcome_email.delay(user_id=instance.id)
```

**In views, trigger via signal**:

```python
# views.py
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import User

class RegisterView(APIView):
    def post(self, request):
        # Create user - signal triggers task automatically
        user = User.objects.create_user(
            email=request.data['email'],
            password=request.data['password'],
        )
        
        # Signal fires post_save → send_welcome_email.delay(user_id=...)
        # → Background worker sends email (no blocking)
        
        return Response({'user_id': user.id}, status=201)
```

### Task State & Real-Time Feedback (Channels)

**Track task progress with WebSocket (optional)**:

```python
# tasks.py
from celery import shared_task
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

@shared_task(bind=True)
def process_large_file(self, file_id, channel_name=None):
    """
    Process file in background.
    Optionally sends progress updates via WebSocket (Channels).
    
    Args:
        file_id: File to process
        channel_name: Channels group name for real-time updates (optional)
    """
    from uploads.models import File
    
    try:
        file_obj = File.objects.get(id=file_id)
        channel_layer = get_channel_layer()
        
        # Process with progress updates
        for step in range(1, 11):
            # Do actual work...
            process_chunk(file_obj, step)
            
            # Send progress via WebSocket (if channel provided)
            if channel_name:
                async_to_sync(channel_layer.group_send)(
                    channel_name,
                    {
                        'type': 'file_progress',
                        'progress': step * 10,
                        'status': 'processing',
                    }
                )
            
            # Also update Celery state (for polling via API)
            self.update_state(
                state='PROGRESS',
                meta={'current': step, 'total': 10}
            )
        
        return {'status': 'complete', 'file_id': file_id}
    
    except File.DoesNotExist:
        return {'error': 'File not found'}
    
    except Exception as exc:
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

**WebSocket consumer receiving updates**:

```python
# consumers.py
from channels.generic.websocket import AsyncWebsocketConsumer
import json

class FileProcessingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.file_id = self.scope['url_route']['kwargs']['file_id']
        self.group_name = f'file_{self.file_id}'
        
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
    
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)
    
    async def file_progress(self, event):
        """Receive progress updates from task."""
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'status': event['status'],
        }))
```

### Error Handling & Retry Strategies

**Categorize errors**: Transient (retry) vs. Permanent (fail)

```python
# tasks.py
from celery import shared_task
import requests

@shared_task(bind=True, max_retries=5)
def sync_external_data(self):
    """
    Sync data from external API.
    Retry on network errors, fail fast on validation errors.
    """
    try:
        # Call external API with timeout
        response = requests.get(
            'https://api.example.com/data',
            timeout=10
        )
        response.raise_for_status()
        
        data = response.json()
        save_data(data)
        
        return {'status': 'synced', 'records': len(data)}
    
    except requests.exceptions.Timeout as exc:
        # Network timeout - TRANSIENT - RETRY
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    
    except requests.exceptions.ConnectionError as exc:
        # Connection failed - TRANSIENT - RETRY
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    
    except ValueError as exc:
        # Invalid data - PERMANENT - FAIL FAST
        return {
            'status': 'failed',
            'error': 'Invalid data from API',
            'details': str(exc)
        }
```

**Error categorization**:
- **Transient**: Network timeouts, connection errors, temporary database locks → RETRY
- **Permanent**: Invalid data, missing resources, validation errors → FAIL FAST (don't retry)

**Retry backoff patterns**:

```python
# Linear backoff (same delay each time)
# 60s, 60s, 60s
countdown = 60

# Exponential backoff (double each time)
# 60s, 120s, 240s
countdown = 60 * (2 ** self.request.retries)

# Fibonacci backoff (realistic growth)
# 60s, 60s, 120s, 180s, 300s
fibonacci = [60, 60, 120, 180, 300]
countdown = fibonacci[min(self.request.retries, len(fibonacci)-1)]

# Max backoff cap (don't wait forever)
countdown = min(60 * (2 ** self.request.retries), 3600)  # Max 1 hour
```

### Task Monitoring & Logging

**Add observability to tasks**:

```python
# tasks.py
import logging
from celery import shared_task
import time

logger = logging.getLogger(__name__)

@shared_task(bind=True)
def analyze_data(self, dataset_id):
    """Analyze dataset with timing and logging."""
    start_time = time.time()
    task_id = self.request.id
    
    logger.info(
        f'Task {task_id} started',
        extra={
            'task_name': 'analyze_data',
            'dataset_id': dataset_id,
        }
    )
    
    try:
        # Actual work...
        result = compute_analysis(dataset_id)
        
        duration = time.time() - start_time
        logger.info(
            f'Task {task_id} completed',
            extra={
                'task_name': 'analyze_data',
                'duration_seconds': duration,
                'result_size': len(result),
            }
        )
        
        return result
    
    except Exception as exc:
        duration = time.time() - start_time
        logger.error(
            f'Task {task_id} failed',
            exc_info=exc,
            extra={
                'task_name': 'analyze_data',
                'duration_seconds': duration,
                'retries': self.request.retries,
            }
        )
        
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

### Common Pitfalls

**❌ WRONG: Accessing request in task**

```python
@shared_task
def send_email(email):
    user = request.user  # ❌ NameError: request doesn't exist
    send_mail(...)
```

**✅ CORRECT: Pass required data as parameters**

```python
@shared_task
def send_email(user_id):
    user = User.objects.get(id=user_id)
    send_mail(...)
```

---

**❌ WRONG: Passing complex objects to tasks**

```python
@shared_task
def process(user):  # ❌ Serialization issues
    send_mail(...)
```

**✅ CORRECT: Pass only IDs**

```python
@shared_task
def process(user_id):  # ✅ ID is simple to serialize
    user = User.objects.get(id=user_id)
    send_mail(...)
```

---

**❌ WRONG: Not categorizing errors**

```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    response = requests.get(url)  # Retries on ANY error
    # If API is down, retries forever
```

**✅ CORRECT: Distinguish transient vs. permanent errors**

```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
    except requests.exceptions.Timeout as exc:
        # Transient - retry
        raise self.retry(exc=exc, countdown=60 * (2 ** self.request.retries))
    except ValueError as exc:
        # Permanent - fail fast
        return {'error': 'Bad data'}
```

---

**❌ WRONG: Synchronous work blocks worker**

```python
@shared_task
def download_and_process():
    data = requests.get('https://bigfile.com/data.zip')  # Blocks worker!
    process_large_file(data)
```

**✅ CORRECT: Use timeouts and async**

```python
@shared_task
def download_and_process():
    # Set timeout to prevent hanging
    data = requests.get(
        'https://bigfile.com/data.zip',
        timeout=30  # ✅ Will raise Timeout exception
    )
    process_large_file(data)
```

---

**❌ WRONG: No error categorization**

```python
@shared_task
def sync_api():
    response = requests.get(url)  # Retry on EVERYTHING
    # If API is down, retries forever
```

**✅ CORRECT: Categorize errors**

```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
    except requests.exceptions.Timeout:
        # Transient - retry
        raise self.retry(countdown=60)
    except ValueError:
        # Invalid data - fail fast
        return {'error': 'Bad data'}
```

### Celery Injection Points

1. **settings.py** - CELERY_BROKER_URL, task limits, retry configuration
2. **celery.py** - App configuration, auto-discovery
3. **tasks.py** - Task definitions with proper error handling
4. **models.py** - Signal handlers that trigger tasks
5. **views.py** - Task calls via `.delay()` or `.apply_async()`
6. **Channels consumers** (optional) - Receiving progress updates via WebSocket
7. **docker-compose.yml** - Celery worker service configuration
8. **Makefile** (optional) - Shortcuts for running workers
9. **Logging** - Task progress and error monitoring

**Verify relevant locations** when implementing Celery integration.

### Testing Celery Tasks

```python
# tests/test_tasks.py
from django.test import TestCase
from django.contrib.auth.models import User
from celery import current_app
from auth.tasks import send_welcome_email

class CeleryTaskTestCase(TestCase):
    """Test Celery tasks in eager mode (synchronous)."""
    
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Run tasks immediately (no queue)
        current_app.conf.task_always_eager = True
    
    def test_send_welcome_email(self):
        """Test welcome email task."""
        user = User.objects.create_user(
            email='test@example.com',
            password='testpass'
        )
        
        result = send_welcome_email.delay(user_id=user.id)
        
        
        # In eager mode, result is available immediately
        self.assertEqual(result.status, 'SUCCESS')
        self.assertIn('test@example.com', result.result)
```

## Why It's Generic

- **Celery**: Industry-standard task queue for Django
- **Signal patterns**: Django's built-in mechanism for decoupling
- **Error handling**: Applies to any external API/service integration
- **Retry strategies**: Exponential backoff, error categorization work universally
- **Channels integration** (optional): Real-time progress updates

These patterns work for any single-tenant Django application.

## Example Use Cases

- **Email systems**: Welcome emails, password resets, notifications
- **Data processing**: Report generation, file processing, data exports
- **External integrations**: API syncs, payment processing, webhook handlers
- **Scheduled jobs**: Cleanup tasks, maintenance, periodic reports
- **Real-time feedback**: Task progress tracking via WebSocket (with Channels)

## Related Skills

- [`SKILL_django-architecture.md`](../django-architecture/SKILL.md) - Core Django patterns (required foundation)
- [`SKILL_django-celery-multitenant.md`](../django-celery-multitenant/SKILL.md) - For multi-tenant applications, how to propagate organization context in tasks
- [`SKILL_django-async-websocket.md`](../django-async-websocket/SKILL.md) - Real-time updates via WebSocket

## References

- [Celery Documentation](https://docs.celeryproject.org/)
- [Django Signals](https://docs.djangoproject.org/en/stable/topics/signals/)
- [Django Channels](https://channels.readthedocs.io/)
- [Redis Configuration](https://redis.io/documentation)
- [Retry Strategies](https://docs.celeryproject.org/en/stable/userguide/tasks.html#retries)

---

**Last Updated**: 2026-01-27