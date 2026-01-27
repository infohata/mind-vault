# Multi-Tenant + Async WebSocket

**WebSocket communication with tenant context**

## Critical Principle: Verify Tenant in connect()

WebSocket connections must verify tenant/organization before accepting. Tenant comes from middleware scope, never from user input.

```python
from channels.generic.websocket import AsyncWebsocketConsumer
from django_tenants.utils import tenant_context

class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        """Verify tenant and accept connection."""
        # Get tenant from scope (set by middleware, not user input)
        self.tenant = self.scope.get('tenant')
        if not self.tenant:
            await self.close(code=4003)  # Forbidden
            return

        # Get user (from AuthMiddleware)
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4001)  # Unauthorized
            return

        # Extract room from URL
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}_{self.tenant.id}'

        # Verify user can access this room in this tenant
        has_access = await self.user_can_access_room(
            self.user.id, self.room_id, self.tenant.id
        )
        if not has_access:
            await self.close(code=4003)
            return

        # Join tenant-scoped group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()

    @database_sync_to_async
    def user_can_access_room(self, user_id, room_id, tenant_id):
        """Verify user has permission in tenant schema."""
        try:
            org = Org.objects.get(id=tenant_id)
            with tenant_context(org):
                room = ChatRoom.objects.get(id=room_id)
                return room.members.filter(id=user_id).exists()
        except:
            return False
```

**Key principles**:
✅ **Get tenant from scope** - Set by middleware, not user input
✅ **Verify authentication** - Both user and tenant required
✅ **Check permissions** - In tenant schema context
✅ **Tenant in group name** - Prevents cross-tenant message leaks
❌ **Never trust user input** - For tenant identification
❌ **Never join groups** - Without verifying tenant access

## Receiving Messages With Tenant Context

```python
async def receive(self, text_data):
    """Handle incoming message in tenant context."""
    try:
        data = json.loads(text_data)
        message = data.get('message', '').strip()

        if not message:
            await self.send(json.dumps({'error': 'Empty message'}))
            return

        # Save message in tenant schema
        msg_obj = await self.save_message(
            user_id=self.user.id,
            room_id=self.room_id,
            message=message,
            tenant_id=self.tenant.id,
        )

        # Broadcast to tenant-scoped group
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'chat_message',
                'id': msg_obj.id,
                'user_id': self.user.id,
                'message': message,
                'timestamp': msg_obj.created_at.isoformat(),
            }
        )

    except json.JSONDecodeError:
        await self.send(json.dumps({'error': 'Invalid JSON'}))
    except Exception as exc:
        await self.send(json.dumps({'error': 'Processing failed'}))

@database_sync_to_async
def save_message(self, user_id, room_id, message, tenant_id):
    """Save message in tenant schema."""
    org = Org.objects.get(id=tenant_id)

    with tenant_context(org):
        user = User.objects.get(id=user_id)
        msg = ChatMessage.objects.create(
            user=user,
            room_id=room_id,
            content=message,
        )

    return msg

async def chat_message(self, event):
    """Broadcast message to client."""
    await self.send(text_data=json.dumps({
        'type': 'chat_message',
        'id': event['id'],
        'user_id': event['user_id'],
        'message': event['message'],
        'timestamp': event['timestamp'],
    }))
```

## Task Progress Updates (Celery + Tenant)

```python
class FileProcessingConsumer(AsyncWebsocketConsumer):
    """Track file processing with tenant context."""

    async def connect(self):
        """Connect and start background task."""
        self.tenant = self.scope.get('tenant')
        if not self.tenant:
            await self.close(code=4003)
            return

        self.file_id = self.scope['url_route']['kwargs']['file_id']
        self.group_name = f'file_{self.file_id}_{self.tenant.id}'

        # Trigger background task with channel name
        await self.start_processing(self.file_id, self.tenant.id)

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    @database_sync_to_async
    def start_processing(self, file_id, tenant_id):
        """Trigger background task."""
        from myapp.tasks import process_file_for_tenant

        process_file_for_tenant.delay(
            file_id=file_id,
            org_id=tenant_id,
            channel_name=self.group_name,
        )

    async def file_progress(self, event):
        """Receive progress from background task."""
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'status': event['status'],
        }))

    async def disconnect(self, close_code):
        """Clean up."""
        await self.channel_layer.group_discard(self.group_name, self.channel_name)
```

## Common Pitfalls

**❌ Getting tenant from request data**:
```python
async def connect(self):
    tenant_id = self.scope['query_string'].get('tenant_id')  # ❌ User input!
    self.tenant = Tenant.objects.get(id=tenant_id)
```

**✅ Get tenant from middleware scope**:
```python
async def connect(self):
    self.tenant = self.scope.get('tenant')  # ✅ Set by middleware
    if not self.tenant:
        await self.close(code=4003)
```

---

**❌ Group name without tenant**:
```python
async def connect(self):
    self.group_name = f'chat_{self.room_id}'  # ❌ Cross-tenant leaks!
```

**✅ Include tenant in group name**:
```python
async def connect(self):
    self.group_name = f'chat_{self.room_id}_{self.tenant.id}'  # ✅ Isolated
```

---

**❌ Database query without tenant context**:
```python
@database_sync_to_async
def get_room(self, room_id):
    return ChatRoom.objects.get(id=room_id)  # ❌ Wrong schema!
```

**✅ Use tenant_context for queries**:
```python
@database_sync_to_async
def get_room(self, room_id, tenant_id):
    org = Org.objects.get(id=tenant_id)
    with tenant_context(org):
        return ChatRoom.objects.get(id=room_id)  # ✅ Correct schema
```

---

**❌ Forgetting tenant verification**:
```python
async def connect(self):
    await self.accept()  # ❌ Accepts without verifying tenant
```

**✅ Verify before accepting**:
```python
async def connect(self):
    if not self.scope.get('tenant'):
        await self.close(code=4003)
        return

    if not self.scope.get('user'):
        await self.close(code=4001)
        return

    await self.accept()  # ✅ Verified
```

## Injection Points

1. **settings.py** - ASGI, CHANNEL_LAYERS (same as single-tenant)
2. **asgi.py** - ProtocolTypeRouter with middleware
3. **middleware** - Must set `scope['tenant']` before consumer
4. **consumers.py** - Verify `scope['tenant']` in `connect()`
5. **routing.py** - URL patterns for consumers
6. **group_name** - Always include `tenant.id` in group names

**Key difference**: Tenant verification must happen BEFORE `accept()`.