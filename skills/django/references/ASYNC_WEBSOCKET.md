# Async WebSocket

**Real-time communication using Django Channels**

## Installation & Configuration

```python
# requirements.txt
channels>=4.0.0
channels-redis>=4.1.0
daphne>=4.0.0

# settings.py
INSTALLED_APPS = [
    'daphne',  # MUST be first!
    'channels',
    # ... other apps
]

ASGI_APPLICATION = 'project.asgi.application'

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [('redis', 6379)],
            'capacity': 1500,
            'expiry': 10,
        },
    },
}
```

**asgi.py**:
```python
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': AuthMiddlewareStack(
        URLRouter(websocket_urlpatterns)
    ),
})
```

**routing.py**:
```python
websocket_urlpatterns = [
    re_path(r'ws/chat/(?P<room_id>\w+)/$', consumers.ChatConsumer.as_asgi()),
]
```

## Core Consumer Pattern

**AsyncWebsocketConsumer for real-time connections**:

```python
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async

class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        """Handle WebSocket connection."""
        # Extract URL parameters
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}'

        # Verify user authentication
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4001)  # 401 Unauthorized
            return

        # Verify room access permission
        has_access = await self.user_can_access_room(self.user.id, self.room_id)
        if not has_access:
            await self.close(code=4003)  # 403 Forbidden
            return

        # Join room group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()

        # Notify others user joined
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'user_joined',
                'user_id': self.user.id,
                'username': self.user.email,
            }
        )

    async def receive(self, text_data):
        """Handle incoming message."""
        try:
            data = json.loads(text_data)
            message = data.get('message', '').strip()

            if not message:
                await self.send(json.dumps({'error': 'Message cannot be empty'}))
                return

            # Save to database
            msg_obj = await self.save_message(self.user.id, self.room_id, message)

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
            await self.send(json.dumps({'error': 'Invalid JSON'}))
        except Exception as exc:
            await self.send(json.dumps({'error': f'Error: {str(exc)}'}))

    async def disconnect(self, close_code):
        """Handle disconnection."""
        pass

    # Event handlers for group messages

    async def chat_message(self, event):
        """Broadcast chat message to client."""
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'id': event['id'],
            'user_id': event['user_id'],
            'username': event['username'],
            'message': event['message'],
            'timestamp': event['timestamp'],
        }))

    async def user_joined(self, event):
        """Notify client user joined."""
        await self.send(text_data=json.dumps({
            'type': 'user_joined',
            'user_id': event['user_id'],
            'username': event['username'],
        }))

    # Database access (sync wrapped in async)

    @database_sync_to_async
    def user_can_access_room(self, user_id, room_id):
        """Check room access permission."""
        try:
            room = ChatRoom.objects.get(id=room_id)
            return room.members.filter(id=user_id).exists()
        except:
            return False

    @database_sync_to_async
    def save_message(self, user_id, room_id, message):
        """Save message to database."""
        user = User.objects.get(id=user_id)
        return ChatMessage.objects.create(
            user=user,
            room_id=room_id,
            content=message,
        )
```

## Key Principles

✅ **Verify user in connect()** - Never trust unauthenticated connections
✅ **Use @database_sync_to_async** - All database access must be wrapped
✅ **Use groups for broadcasting** - group_send() for multi-user messaging
✅ **Handle errors gracefully** - JSON parsing, validation, exceptions
❌ **Don't block the event loop** - No sync I/O or long operations
❌ **Don't assume authentication** - Always verify user context

## Error Handling Patterns

**Categorize errors for proper handling**:

```python
async def receive(self, text_data):
    try:
        data = json.loads(text_data)

        # Validate message content
        if not data.get('message', '').strip():
            await self.send(json.dumps({
                'error': 'Message cannot be empty',
                'code': 'EMPTY_MESSAGE'
            }))
            return

        # Process message
        await self.process_message(data)

    except json.JSONDecodeError:
        await self.send(json.dumps({
            'error': 'Invalid JSON format',
            'code': 'INVALID_JSON'
        }))

    except ValidationError as exc:
        await self.send(json.dumps({
            'error': f'Validation error: {str(exc)}',
            'code': 'VALIDATION_ERROR'
        }))

    except Exception as exc:
        # Log unexpected errors
        logger.error(f"Unexpected error in WebSocket: {exc}", exc_info=True)
        await self.send(json.dumps({
            'error': 'Internal server error',
            'code': 'INTERNAL_ERROR'
        }))
```

## Broadcasting Patterns

**Group messaging for multi-user communication**:

```python
# Join group on connect
await self.channel_layer.group_add(
    f'room_{self.room_id}',
    self.channel_name
)

# Send to all in group
await self.channel_layer.group_send(
    f'room_{self.room_id}',
    {
        'type': 'room_message',  # Handler method name
        'message': 'Hello everyone!',
        'user_id': self.user.id,
    }
)

# Handle in event method
async def room_message(self, event):
    await self.send(text_data=json.dumps({
        'type': 'room_message',
        'message': event['message'],
        'user_id': event['user_id'],
    }))
```

## Celery Integration

**Background task progress updates via WebSocket**:

```python
# consumer.py
class TaskProgressConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.task_id = self.scope['url_route']['kwargs']['task_id']
        self.group_name = f'task_{self.task_id}'

        # Verify user owns this task
        if not await self.user_owns_task(self.user.id, self.task_id):
            await self.close(code=403)
            return

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def task_progress(self, event):
        """Receive progress updates from Celery."""
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'message': event['message'],
        }))

# In Celery task
from channels.layers import get_channel_layer

@shared_task(bind=True)
def long_running_task(self, task_id, user_id):
    channel_layer = get_channel_layer()

    for i in range(0, 100, 10):
        # Update progress
        channel_layer.group_send(
            f'task_{task_id}',
            {
                'type': 'task_progress',
                'progress': i,
                'message': f'Processing step {i//10}',
            }
        )
        time.sleep(1)  # Simulate work

    return 'Task completed'
```

## Testing

```python
from channels.testing import WebsocketCommunicator
from django.test import TestCase

class ChatConsumerTest(TestCase):
    async def test_chat_message(self):
        communicator = WebsocketCommunicator(
            ChatConsumer.as_asgi(),
            'ws/chat/room123/',
        )

        # Connect
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        # Send message
        await communicator.send_json_to({'message': 'Hello!'})

        # Receive response
        response = await communicator.receive_json_from()
        self.assertEqual(response['type'], 'chat_message')
        self.assertEqual(response['message'], 'Hello!')

        await communicator.disconnect()
```

## Common Pitfalls

**❌ Blocking database queries**:
```python
async def receive(self, text_data):
    user = User.objects.get(id=user_id)  # ❌ Blocks event loop!
    await self.send(json.dumps({'user': user.email}))
```

**✅ Async database access**:
```python
async def receive(self, text_data):
    user = await self.get_user_async(user_id)  # ✅ Non-blocking
    await self.send(json.dumps({'user': user.email}))

@database_sync_to_async
def get_user_async(self, user_id):
    return User.objects.get(id=user_id)
```

## Public API vs Authenticated Parity (Session-Scoped Ownership)

When building WebSocket features (like chat sessions) exposed to both logged-in users and anonymous public browsers, do not branch your API logic completely.
Instead, use **Session-Scoped Ownership** (`ws_token`) for the anonymous users to manage state symmetrically:

1. Allow the WebSocket to connect, but require the client to pass their Django `session_key` (e.g. as a query parameter `?ws_token=...`).
2. Persist this `session_key` on any objects they create (if `request.user.is_anonymous`).
3. For REST API actions or WebSocket commands, enforce object-level validation by comparing the passed `ws_token` against the record's stored `session_key`.

```python
# API example for anonymous session parity matching WS consumer
def get_queryset(self):
    ws_token = self.request.query_params.get("ws_token")
    if self.request.user.is_authenticated:
        return Model.objects.filter(author=self.request.user)
    elif ws_token:
        # Prevent crossover by tracking anonymous session ownership perfectly
        return Model.objects.filter(author__isnull=True, session_key=ws_token)
    return Model.objects.none()
```

---

**❌ Unauthenticated connections**:
```python
async def connect(self):
    # Assumes user is authenticated
    self.user = self.scope['user']  # ❌ May be None!
    await self.accept()
```

**✅ Proper authentication**:
```python
async def connect(self):
    self.user = self.scope.get('user')
    if not self.user or not self.user.is_authenticated:
        await self.close(code=4001)  # ✅ Reject unauthenticated
        return
    await self.accept()
```

---

**❌ No error handling**:
```python
async def receive(self, text_data):
    data = json.loads(text_data)  # ❌ Crashes on bad JSON
    await self.process_message(data)
```

**✅ Graceful error handling**:
```python
async def receive(self, text_data):
    try:
        data = json.loads(text_data)
        await self.process_message(data)
    except json.JSONDecodeError:
        await self.send(json.dumps({'error': 'Invalid JSON'}))
    except Exception as exc:
        await self.send(json.dumps({'error': 'Processing failed'}))
```

## Per-Message Resource Caps

When a WebSocket message accepts client-supplied lists (attachments, tool calls, batched events) and feeds them into a paid downstream — LLM tokens, transcription minutes, third-party API quota — the consumer is the right place to enforce the cap. Clients can submit lists of any length; the model / service will dutifully process all of them; the bill arrives later.

The boundary rule: validate at the consumer (where `request.user`, `org`, and `client_ip` are visible), not deeper. Models, serializers, and tool executors are too far inside — by the time a list reaches them you've already paid for the iteration.

```python
# settings.py — env-overridable, frozen, documented
AI_MAX_ATTACHMENTS_PER_MESSAGE = int(os.getenv('AI_MAX_ATTACHMENTS_PER_MESSAGE', '5'))
```

```python
# consumer
class ChatConsumer(AsyncJsonWebsocketConsumer):

    async def receive_json(self, content, **kwargs):
        attachment_ids = content.get('attachment_ids') or []

        # Cap before any DB / model / LLM work.
        if len(attachment_ids) > settings.AI_MAX_ATTACHMENTS_PER_MESSAGE:
            await self.send_json({
                'type': 'error',
                'error': 'TOO_MANY_ATTACHMENTS',
                'limit': settings.AI_MAX_ATTACHMENTS_PER_MESSAGE,
                'received': len(attachment_ids),
            })
            return  # do NOT proceed to the LLM call

        # ... normal flow
```

Three reasons the cap belongs here, not at the model layer:

1. **Cost control happens before the spend.** Validating after the LLM call has already streamed tokens means the user is billed for the over-cap request. The cap is preventive, not corrective.
2. **The `org` / `user` / `client_ip` context is right here.** Per-tenant or per-user overrides (a paid tier that allows 20 attachments while free is capped at 5) are a one-line lookup at the consumer; pushed deeper, every internal helper would need to know about plan tier.
3. **Failure mode is surface-able.** A consumer-level rejection sends a structured error frame the JS client can render as a UX message ("you can attach up to 5 files per message"); a model-level `ValidationError` raised three layers in surfaces as a generic 500 or a swallowed exception.

For HTTP endpoints (DRF views), apply the same rule: cap in the view's `validate()` / `clean()` / `perform_create` *before* calling out to the LLM client. The principle is shape-of-input check at the boundary, not after the spend.

Pairs with: env-driven settings parsed once into typed values (see [django/SKILL.md → Env-driven allowlists / denylists as `frozenset`](../SKILL.md)) and LLM output post-processing (see [django/SKILL.md → LLM output post-processing — strip-and-trust pattern](../SKILL.md)) — three pieces of the same hot-path discipline: cap input at the boundary, post-strip the output, frozen settings so the policy can't drift mid-request.
## Persisting partial streamed content across a mid-stream disconnect

**Fires when** a consumer streams generated content (LLM tokens, reasoning, any long response) and must persist whatever streamed **even if the client disconnects mid-stream**.

The accumulator that collects the streamed chunks **MUST be instance state** (`self._streaming_buf`), never a method-local in the receive/stream handler. `disconnect(self, close_code)` is a *separate method* — it can only reach `self.*`. A method-local buffer built up in the stream loop is **unreachable from `disconnect`**, so a mid-stream disconnect persists empty/partial content (exactly the reload gap the persistence was meant to close).

```python
async def receive(self, text_data):
    self._streaming_buf = ""            # instance state, init ONCE before the loop
    self._streaming_reasoning = ""      #   (not inside the per-iteration tool loop)
    async for chunk in stream:
        self._streaming_buf += chunk    # survives across tool-call iterations — do NOT reset per iteration
    await self._save(content=self._streaming_buf, reasoning=self._streaming_reasoning)

async def disconnect(self, close_code):
    # reachable ONLY because the buffer is on self, not a receive()-local
    await self._persist_partial_if_any()   # reads self._streaming_buf
```

Two more rules that travel with this:

1. **Don't reset the accumulator per tool-call iteration.** A multi-iteration response (tool call → result → answer) streams across several passes of the inner loop; resetting per pass drops everything but the last. Init once *before* the loop.
2. **Thread the field through EVERY save site** — success, error/failed, and the disconnect path — and consolidate them onto one `_build_update_fields()` helper so a fifth save site can't silently forget the new field. The disconnect path is the one a method-local can't reach and the one that's easiest to forget; an explicit disconnect-persist test is worth its weight.

Pairs with: [`OPENROUTER_REASONING_API.md`](OPENROUTER_REASONING_API.md) (the reasoning channel this most often accumulates).
