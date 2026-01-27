# Celery Background Tasks

**Asynchronous job processing with Django**

## Critical Principle: No Request Context

Tasks run in background workers **without request context**. You cannot access `request.user`, `request.session`, or any request-specific data. All required context must be passed explicitly as task parameters.

## Installation & Configuration

```python
# requirements.txt
celery>=5.3.0
redis>=4.5.0

# settings.py
CELERY_BROKER_URL = 'redis://redis:6379/0'  # Task queue
CELERY_RESULT_BACKEND = 'redis://redis:6379/0'  # Result storage
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'

# Task execution settings
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60  # 30 minutes hard limit
CELERY_TASK_SOFT_TIME_LIMIT = 25 * 60  # 25 minutes soft limit

# Retry settings
CELERY_TASK_AUTORETRY_FOR = (Exception,)
CELERY_TASK_MAX_RETRIES = 3
CELERY_TASK_DEFAULT_RETRY_DELAY = 60

# Timezone consistency
CELERY_TIMEZONE = 'UTC'
CELERY_ENABLE_UTC = True
```

**celery.py**:
```python
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')

app = Celery('project')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

@app.task(bind=True)
def debug_task(self):
    """Test task to verify Celery is working."""
    print(f'Request: {self.request!r}')
```

## Core Task Pattern

```python
from celery import shared_task

@shared_task(bind=True, max_retries=3)
def send_welcome_email(self, user_id):
    """
    Send welcome email to user.

    Args:
        user_id: ID of user to email
    """
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
        # Permanent error - don't retry
        return {'error': 'User not found'}

    except Exception as exc:
        # Transient error - retry with backoff
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

**Key principles**:
✅ **Pass IDs as parameters** - All context must be explicit
✅ **Fetch from database** - No request object available
✅ **Categorize errors** - Permanent vs transient
✅ **Use exponential backoff** - For retry delays
❌ **Don't access request** - Doesn't exist in workers
❌ **Don't assume user context** - Always explicit

## Signal-Based Triggering

**Models trigger tasks via Django signals**:

```python
from django.db.models.signals import post_save
from django.dispatch import receiver

@receiver(post_save, sender=User)
def user_created(sender, instance, created, **kwargs):
    """Trigger welcome email when user is created."""
    if created:
        send_welcome_email.delay(user_id=instance.id)
```

**In views**:
```python
class RegisterView(APIView):
    def post(self, request):
        # Create user - signal triggers task automatically
        user = User.objects.create_user(
            email=request.data['email'],
            password=request.data['password'],
        )
        # Signal fires → send_welcome_email.delay(user_id=...)
        return Response({'user_id': user.id}, status=201)
```

## Task Progress & Real-Time Updates

**Track progress with Channels integration**:

```python
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

@shared_task(bind=True)
def process_large_file(self, file_id, channel_name=None):
    """Process file with progress updates."""
    try:
        file_obj = File.objects.get(id=file_id)
        channel_layer = get_channel_layer()

        for step in range(1, 11):
            # Do work...
            process_chunk(file_obj, step)

            # Send WebSocket progress update
            if channel_name:
                async_to_sync(channel_layer.group_send)(
                    channel_name,
                    {
                        'type': 'file_progress',
                        'progress': step * 10,
                        'status': 'processing',
                    }
                )

            # Update Celery state for polling
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

**WebSocket consumer**:
```python
class FileProcessingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.file_id = self.scope['url_route']['kwargs']['file_id']
        self.group_name = f'file_{self.file_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def file_progress(self, event):
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'status': event['status'],
        }))
```

## Error Handling & Retry Strategies

**Categorize errors: Transient (retry) vs. Permanent (fail)**

```python
@shared_task(bind=True, max_retries=5)
def sync_external_data(self):
    """Sync data from external API."""
    try:
        response = requests.get(
            'https://api.example.com/data',
            timeout=10
        )
        response.raise_for_status()

        data = response.json()
        save_data(data)

        return {'status': 'synced', 'records': len(data)}

    except requests.exceptions.Timeout as exc:
        # Transient - RETRY
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)

    except requests.exceptions.ConnectionError as exc:
        # Transient - RETRY
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)

    except ValueError as exc:
        # Permanent - FAIL FAST
        return {
            'status': 'failed',
            'error': 'Invalid data from API',
            'details': str(exc)
        }
```

**Retry backoff patterns**:

```python
# Exponential backoff: 60s, 120s, 240s
countdown = 60 * (2 ** self.request.retries)

# Fibonacci: 60s, 60s, 120s, 180s, 300s
fibonacci = [60, 60, 120, 180, 300]
countdown = fibonacci[min(self.request.retries, len(fibonacci)-1)]

# Capped exponential: Max 1 hour
countdown = min(60 * (2 ** self.request.retries), 3600)
```

## Task Monitoring & Logging

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

## Common Pitfalls

**❌ Accessing request in task**:
```python
@shared_task
def send_email(email):
    user = request.user  # ❌ NameError: request doesn't exist
```

**✅ Pass required data**:
```python
@shared_task
def send_email(user_id):
    user = User.objects.get(id=user_id)  # ✅ Explicit
```

---

**❌ Passing complex objects**:
```python
@shared_task
def process(user):  # ❌ Serialization issues
```

**✅ Pass only IDs**:
```python
@shared_task
def process(user_id):  # ✅ Simple serialization
```

---

**❌ Not categorizing errors**:
```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    response = requests.get(url)  # Retries on ANY error
```

**✅ Distinguish error types**:
```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
    except requests.exceptions.Timeout:
        raise self.retry(countdown=60)  # Transient
    except ValueError:
        return {'error': 'Bad data'}  # Permanent
```

---

**❌ Blocking operations**:
```python
@shared_task
def download_file():
    data = requests.get('bigfile.com/data.zip')  # Blocks worker!
```

**✅ Use timeouts**:
```python
@shared_task
def download_file():
    data = requests.get(
        'bigfile.com/data.zip',
        timeout=30  # ✅ Prevents hanging
    )
```

## Celery Injection Points

1. **settings.py** - CELERY_BROKER_URL, limits, retry config
2. **celery.py** - App config, auto-discovery
3. **tasks.py** - Task definitions with error handling
4. **models.py** - Signal handlers triggering tasks
5. **views.py** - Task calls via `.delay()`
6. **consumers.py** - Progress updates via WebSocket
7. **docker-compose.yml** - Worker service config
8. **Makefile** - Worker shortcuts

## Testing Tasks

```python
from django.test import TestCase
from celery import current_app

class CeleryTaskTestCase(TestCase):
    """Test tasks in eager mode (synchronous)."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        current_app.conf.task_always_eager = True

    def test_send_welcome_email(self):
        user = User.objects.create_user(
            email='test@example.com',
            password='testpass'
        )

        result = send_welcome_email.delay(user_id=user.id)

        self.assertEqual(result.status, 'SUCCESS')
        self.assertIn('test@example.com', result.result)
```