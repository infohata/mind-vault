# SKILL_django-async-websocket

## Overview

Real-time communication patterns using Django Channels for WebSocket connections. Complete guide to implementing async consumers with tenant awareness, database access via `@database_sync_to_async`, error handling, and integration with Celery for task updates. Build on SKILL_django-architecture, SKILL_django-multi-tenant, and SKILL_django-celery.

## When to Use

- Building real-time chat or messaging systems
- Live data streaming (notifications, stock prices, sensor data)
- Real-time collaboration (shared documents, editing)
- Multiplayer/gaming features requiring low-latency updates
- Progress tracking for long-running background tasks
- Push notifications via WebSocket instead of polling

**DO NOT USE if**:
- Simple polling is acceptable (REST API with periodic requests)
- One-way broadcasts to many users (use HTTP Server-Sent Events)
- No persistent connections needed

## Pattern

### Installation & Configuration

```python
# requirements.txt
channels>=4.0.0
channels-redis>=4.1.0
daphne>=4.0.0
```

**settings.py** (at `web/project/settings.py`):

```python
# Add Channels
INSTALLED_APPS = [
    'daphne',  # MUST be first!
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'channels',  # ← WebSocket support
    'rest_framework',
    'core',
    'auth',
    'api',
    'teisutis_ai',
]

# Channels configuration
ASGI_APPLICATION = 'project.asgi.application'

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [('redis', 6379)],  # Docker Compose service
            'capacity': 1500,
            'expiry': 10,
        },
    },
}

# WebSocket timeout (how long idle connections persist)
WS_TIMEOUT = 300  # 5 minutes
```

**asgi.py** (at `web/project/asgi.py`):

```python
import os
import django
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')
django.setup()

from teisutis_ai.routing import websocket_urlpatterns

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': AuthMiddlewareStack(
        URLRouter(websocket_urlpatterns)
    ),
})
```

**routing.py** (at `web/teisutis_ai/routing.py`):

```python
from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'ws/chat/(?P<room_id>\w+)/$', consumers.ChatConsumer.as_asgi()),
    re_path(r'ws/notifications/$', consumers.NotificationConsumer.as_asgi()),
]
```

**docker-compose.yml**:

```yaml
services:
  # HTTP + WebSocket on same server (Daphne)
  web:
    build: .
    command: daphne -b 0.0.0.0 -p 8000 project.asgi:application
    ports:
      - "8000:8000"
    depends_on:
      - postgres
      - redis

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

### Core Consumer Pattern

**AsyncWebsocketConsumer for real-time connections**:

```python
# consumers.py - in app (teisutis_ai/consumers.py)
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django_tenants.utils import tenant_context
import json

class ChatConsumer(AsyncWebsocketConsumer):
    """
    WebSocket consumer for chat messages.
    
    Connection Flow:
    1. connect() - Accept/reject connection
    2. receive() - Handle incoming messages
    3. disconnect() - Clean up
    """
    
    async def connect(self):
        """Handle WebSocket connection."""
        # Extract URL parameters
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}'
        
        # Get tenant from scope (set by middleware)
        self.tenant = self.scope.get('tenant')
        if not self.tenant:
            await self.close(code=4003)  # 403 Forbidden
            return
        
        # Get user from scope (set by AuthMiddleware)
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4001)  # 401 Unauthorized
            return
        
        # Verify user can access this room (database check)
        has_access = await self.user_can_access_room(
            self.user.id,
            self.room_id,
            self.tenant.id
        )
        if not has_access:
            await self.close(code=4003)  # 403 Forbidden
            return
        
        # Join group (other consumers in room receive messages)
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        
        # Accept connection
        await self.accept()
        
        # Notify others that user joined
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'user_joined',
                'user_id': self.user.id,
                'username': self.user.email,
            }
        )
    
    async def receive(self, text_data):
        """Handle incoming message from client."""
        try:
            data = json.loads(text_data)
            message = data.get('message', '').strip()
            
            if not message:
                await self.send(json.dumps({
                    'error': 'Message cannot be empty',
                }))
                return
            
            # Save message to database (with tenant context)
            msg_obj = await self.save_message(
                user_id=self.user.id,
                room_id=self.room_id,
                message=message,
                tenant_id=self.tenant.id,
            )
            
            # Broadcast to room
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    'type': 'chat_message',
                    'id': msg_obj.id,
                    'user_id': self.user.id,
                    'username': self.user.email,
                    'message': message,
                    'timestamp': msg_obj.created_at.isoformat(),
                }
            )
        
        except json.JSONDecodeError:
            await self.send(json.dumps({
                'error': 'Invalid JSON',
            }))
        except Exception as exc:
            await self.send(json.dumps({
                'error': f'Error processing message: {str(exc)}',
            }))
    
    async def disconnect(self, close_code):
        """Handle WebSocket disconnection."""
        # Remove from group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )
        
        # Notify others that user left
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'user_left',
                'user_id': self.user.id,
                'username': self.user.email,
            }
        )
    
    # Event handlers (called by group_send)
    
    async def chat_message(self, event):
        """Broadcast chat message to all users in room."""
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'id': event['id'],
            'user_id': event['user_id'],
            'username': event['username'],
            'message': event['message'],
            'timestamp': event['timestamp'],
        }))
    
    async def user_joined(self, event):
        """Notify room that user joined."""
        await self.send(text_data=json.dumps({
            'type': 'user_joined',
            'user_id': event['user_id'],
            'username': event['username'],
        }))
    
    async def user_left(self, event):
        """Notify room that user left."""
        await self.send(text_data=json.dumps({
            'type': 'user_left',
            'user_id': event['user_id'],
            'username': event['username'],
        }))
    
    # Database access (sync wrapped in async)
    
    @database_sync_to_async
    def user_can_access_room(self, user_id, room_id, tenant_id):
        """Check if user has permission to access room."""
        from core.models import Tenant
        from teisutis_ai.models import ChatRoom
        
        try:
            tenant = Tenant.objects.get(id=tenant_id)
            
            # Must use tenant_context to access tenant schema
            with tenant_context(tenant):
                room = ChatRoom.objects.get(id=room_id)
                # Check if user is member
                return room.members.filter(id=user_id).exists()
        except:
            return False
    
    @database_sync_to_async
    def save_message(self, user_id, room_id, message, tenant_id):
        """Save message to database."""
        from django.contrib.auth.models import User
        from core.models import Tenant
        from teisutis_ai.models import ChatMessage
        
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            user = User.objects.get(id=user_id)
            msg_obj = ChatMessage.objects.create(
                user=user,
                room_id=room_id,
                content=message,
            )
        
        return msg_obj
```

**Key principles**:
- ✅ Verify tenant and user in `connect()`
- ✅ Use `@database_sync_to_async` for database queries
- ✅ Wrap tenant-dependent queries with `tenant_context()`
- ✅ Use groups for broadcasting (`group_send`)
- ✅ Handle JSON parsing errors gracefully
- ❌ Don't run blocking operations in async handlers
- ❌ Don't assume tenant is set (get from scope)

### Tenant Context in Async

**CRITICAL: tenant_context in @database_sync_to_async**:

```python
from channels.db import database_sync_to_async
from django_tenants.utils import tenant_context

class MyConsumer(AsyncWebsocketConsumer):
    @database_sync_to_async
    def get_user_data(self, user_id, tenant_id):
        """Access tenant-specific data."""
        from core.models import Tenant
        
        # Get tenant from public schema
        tenant = Tenant.objects.get(id=tenant_id)
        
        # Switch to tenant schema for queries
        with tenant_context(tenant):
            # All queries here use tenant schema
            data = SomeModel.objects.filter(user_id=user_id)
        
        return [d.to_dict() for d in data]
```

**Without tenant_context: ❌ Might access wrong schema**

```python
@database_sync_to_async
def bad_query(self, user_id, tenant_id):
    # This doesn't use tenant context!
    data = SomeModel.objects.filter(user_id=user_id)  # ❌ Wrong schema!
    return data
```

### Task Progress Updates

**Celery task sends progress via group_send**:

```python
# tasks.py
from celery import shared_task
from django_tenants.utils import tenant_context
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

@shared_task(bind=True)
def process_file(self, file_id, tenant_id, channel_name=None):
    """Process file and send progress updates."""
    from core.models import Tenant
    from uploads.models import File
    
    channel_layer = get_channel_layer()
    
    try:
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            file_obj = File.objects.get(id=file_id)
            
            # Process in steps
            for step in range(1, 11):
                # Do work...
                process_chunk(file_obj, step)
                
                # Send progress via Channels
                if channel_name:
                    async_to_sync(channel_layer.group_send)(
                        channel_name,  # WebSocket group
                        {
                            'type': 'file_progress',
                            'progress': step * 10,
                            'status': 'processing',
                            'message': f'Processing step {step}/10',
                        }
                    )
                
                # Also update Celery state for API polling
                self.update_state(
                    state='PROGRESS',
                    meta={'current': step, 'total': 10}
                )
        
        return {'status': 'complete'}
    
    except Exception as exc:
        if channel_name:
            async_to_sync(channel_layer.group_send)(
                channel_name,
                {
                    'type': 'file_progress',
                    'progress': 0,
                    'status': 'error',
                    'message': str(exc),
                }
            )
        raise
```

**WebSocket consumer receives updates**:

```python
class FileProcessingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.file_id = self.scope['url_route']['kwargs']['file_id']
        self.group_name = f'file_{self.file_id}'
        
        # Get tenant from scope
        self.tenant = self.scope.get('tenant')
        if not self.tenant:
            await self.close(code=4003)
            return
        
        # Trigger background task with channel name
        await self.trigger_file_processing(self.file_id, self.tenant.id)
        
        # Join group for updates
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
    
    @database_sync_to_async
    def trigger_file_processing(self, file_id, tenant_id):
        """Start background task with channel name for feedback."""
        from uploads.tasks import process_file
        
        # Pass channel name so task can send updates
        process_file.delay(
            file_id=file_id,
            tenant_id=tenant_id,
            channel_name=self.group_name,
        )
    
    async def file_progress(self, event):
        """Receive progress from background task."""
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'status': event['status'],
            'message': event['message'],
        }))
    
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)
```

### Error Handling in Async

**Categorize errors: Recoverable vs. Fatal**:

```python
class DataStreamConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.tenant = self.scope.get('tenant')
        if not self.tenant:
            await self.close(code=4003)
            return
        
        # Connect to data stream
        try:
            self.stream = await self.init_stream(self.tenant.id)
            await self.accept()
            await self.stream_loop()
        except ConnectionError as exc:
            # Recoverable - client can reconnect
            await self.close(code=1011)  # Service restart
        except Exception as exc:
            # Fatal - log and close
            await self.close(code=1002)  # Protocol error
    
    async def stream_loop(self):
        """Stream data continuously."""
        try:
            while True:
                try:
                    # Get next data point
                    data = await self.get_stream_data()
                    
                    # Send to client
                    await self.send(text_data=json.dumps(data))
                
                except TimeoutError:
                    # Transient - retry
                    continue
                except DataFormatError:
                    # Skip bad data - don't close connection
                    continue
                except ConnectionLost:
                    # Reconnect stream
                    self.stream = await self.init_stream(self.tenant.id)
        
        except Exception as exc:
            # Unexpected error - close connection
            await self.close(code=1002)
```

### Common Pitfalls

**❌ WRONG: Blocking operations in async**

```python
async def receive(self, text_data):
    # This blocks the event loop!
    time.sleep(5)  # ❌ Blocks all WebSocket connections
    response = process_data(text_data)  # ❌ If slow, blocks others
```

**✅ CORRECT: Use async/await or @database_sync_to_async**

```python
async def receive(self, text_data):
    # Async-friendly
    await asyncio.sleep(5)  # ✅ Non-blocking
    
    # Database query (wrapped)
    response = await self.process_data_async(text_data)  # ✅ Non-blocking
```

---

**❌ WRONG: Missing tenant verification**

```python
async def connect(self):
    self.user = self.scope['user']  # What if not authenticated?
    await self.accept()  # ❌ Unauthenticated user connected
```

**✅ CORRECT: Verify tenant and user**

```python
async def connect(self):
    self.tenant = self.scope.get('tenant')
    if not self.tenant:
        await self.close(code=4003)  # ✅ Reject
        return
    
    self.user = self.scope.get('user')
    if not self.user or not self.user.is_authenticated:
        await self.close(code=4001)  # ✅ Reject
        return
    
    await self.accept()
```

---

**❌ WRONG: Queries without tenant context**

```python
@database_sync_to_async
def get_data(self, user_id, tenant_id):
    # Uses default schema - might be public!
    return MyModel.objects.filter(user_id=user_id)  # ❌ Wrong schema
```

**✅ CORRECT: Explicit tenant context**

```python
@database_sync_to_async
def get_data(self, user_id, tenant_id):
    from core.models import Tenant
    
    tenant = Tenant.objects.get(id=tenant_id)
    with tenant_context(tenant):
        return MyModel.objects.filter(user_id=user_id)  # ✅ Correct schema
```

---

**❌ WRONG: Unhandled exceptions in receive**

```python
async def receive(self, text_data):
    data = json.loads(text_data)  # ❌ Crashes on bad JSON
    process(data)
```

**✅ CORRECT: Graceful error handling**

```python
async def receive(self, text_data):
    try:
        data = json.loads(text_data)
        process(data)
    except json.JSONDecodeError:
        await self.send(json.dumps({'error': 'Invalid JSON'}))
    except Exception as exc:
        await self.send(json.dumps({'error': 'Processing failed'}))
```

### 10 Async/WebSocket Injection Points

1. **settings.py** - ASGI_APPLICATION, CHANNEL_LAYERS, Daphne config
2. **asgi.py** - ProtocolTypeRouter, AuthMiddleware, URLRouter setup
3. **routing.py** - URL patterns for consumers (as_asgi())
4. **consumers.py** - AsyncWebsocketConsumer implementations
5. **@database_sync_to_async** - Database access in consumers
6. **tenant_context()** - Multi-tenant schema switching
7. **channel_layer.group_send()** - Broadcasting to groups
8. **scope['tenant']** - Tenant from middleware
9. **scope['user']** - User from AuthMiddleware
10. **docker-compose.yml** - Daphne instead of Gunicorn

**Verify all 10 locations** when implementing WebSocket.

### Testing Async Consumers

```python
# tests/test_consumers.py
from channels.testing import WebsocketCommunicator
from django.test import TestCase
from django_tenants.test.cases import TenantTestCase
from core.models import Tenant, User
from teisutis_ai.consumers import ChatConsumer

class ChatConsumerTestCase(TenantTestCase):
    """Test WebSocket consumer."""
    
    def setUp(self):
        self.tenant = Tenant.objects.create(name='Test Org')
        self.set_tenant(self.tenant)
        self.user = User.objects.create_user('test@example.com')
    
    async def test_chat_consumer_connect(self):
        """Test WebSocket connection."""
        communicator = WebsocketCommunicator(
            ChatConsumer.as_asgi(),
            'ws/chat/room123/',
            headers=[(b'origin', b'http://testserver')],
        )
        
        # Connect and verify
        connected, subprotocol = await communicator.connect()
        self.assertTrue(connected)
        
        # Send message
        await communicator.send_json_to({
            'message': 'Hello!',
        })
        
        # Receive confirmation
        response = await communicator.receive_json_from()
        self.assertEqual(response['type'], 'chat_message')
        self.assertEqual(response['message'], 'Hello!')
        
        # Disconnect
        await communicator.disconnect()
```

## Why It's Generic

- **Channels**: Industry-standard for Django real-time features
- **AsyncWebsocketConsumer**: Works with any real-time feature (chat, notifications, streaming)
- **@database_sync_to_async**: Standard pattern for mixing async/sync code
- **Multi-tenant support**: Works with any schema-per-tenant setup
- **Group broadcasting**: Generic pattern for any multi-user feature
- **Production-ready**: Used in Teisutis for chat, notifications, live AI responses

## Example Use Cases

- **Teisutis**: Live chat with AI, real-time KB updates, notification streaming
- **SaaS apps**: User collaboration, real-time notifications, live dashboards
- **E-commerce**: Live inventory updates, order status tracking
- **Analytics**: Real-time charts, live metric streaming
- **Support systems**: Live chat, ticket updates, agent presence

## Related Skills

- [`SKILL_django-architecture.md`](../skills/SKILL_django-architecture.md) - Core Django patterns (required foundation)
- [`SKILL_django-multi-tenant.md`](../skills/SKILL_django-multi-tenant.md) - Multi-tenant context required
- [`SKILL_django-celery.md`](../skills/SKILL_django-celery.md) - Background tasks sending updates via WebSocket

## Related Rules

- [`RULE_async-context-safety.md`](../rules/RULE_async-context-safety.md) - Async context critical guardrails (TBD)

## References

- [Django Channels Documentation](https://channels.readthedocs.io/)
- [Async Support in Django](https://docs.djangoproject.org/en/stable/topics/async/)
- [@database_sync_to_async](https://docs.djangoproject.org/en/stable/topics/async/#database-access)
- [Channels Testing](https://channels.readthedocs.io/en/stable/testing.html)
- [WebSocket Best Practices](https://www.rfc-editor.org/rfc/rfc6455)

---

**Last Updated**: 2026-01-27
