---
name: django-async-websocket-multitenant
description: Multi-tenant WebSocket patterns extending Channels with schema-per-tenant isolation, focusing on tenant context in async consumers.
license: MIT
compatibility: opencode
---

## Overview

Multi-tenant patterns for WebSocket real-time communication using Django Channels with schema-per-tenant isolation. Extension of [SKILL.md](../django-async-websocket/SKILL.md) showing how to handle organization/tenant context in async consumers. Use this skill when building WebSocket features for multi-tenant applications.

**Prerequisites**: Read [SKILL.md](../django-async-websocket/SKILL.md) first (core patterns).

**Related**: [SKILL.md](../django-multi-tenant/SKILL.md) (tenant architecture), [SKILL.md](../django-celery-multitenant/SKILL.md) (background tasks with tenants)

## When to Use

- Building real-time communication for multi-tenant applications
- WebSocket connections need access to organization/tenant-specific data
- Using schema-per-tenant architecture (each tenant gets separate database schema)
- Broadcasting messages within a tenant only (cross-tenant isolation)

**DO NOT USE if**:
- Single-tenant application (use [SKILL.md](../django-async-websocket/SKILL.md) instead)
- Using row-level security instead of schema-per-tenant
- WebSocket consumers don't need tenant context (stateless)

## Pattern

### Critical Principle: Verify Tenant in connect()

WebSocket connections must verify tenant/organization before accepting. Tenant must come from middleware (scope), not from user input.

```python
# consumers.py
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django_tenants.utils import tenant_context

class ChatConsumer(AsyncWebsocketConsumer):
    """
    Multi-tenant chat consumer.
    
    Connection flow:
    1. Get tenant from scope (set by middleware)
    2. Verify user has access
    3. Join group for broadcasting
    4. Accept connection
    """
    
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
            self.user.id,
            self.room_id,
            self.tenant.id
        )
        if not has_access:
            await self.close(code=4003)
            return
        
        # Join group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        
        await self.accept()
    
    @database_sync_to_async
    def user_can_access_room(self, user_id, room_id, tenant_id):
        """Verify user has permission in tenant schema."""
        from django_tenants.utils import tenant_context
        
        try:
            # Fetch organization/tenant
            org = Org.objects.get(id=tenant_id)
            
            # Switch to tenant schema for permission check
            with tenant_context(org):
                from myapp.models import ChatRoom
                room = ChatRoom.objects.get(id=room_id)
                # Check if user is member
                return room.members.filter(id=user_id).exists()
        except:
            return False
```

**Key points**:
- ✅ Get tenant from `scope` (set by middleware)
- ✅ Verify user authentication
- ✅ Check permission in tenant schema
- ✅ Use `tenant_id` in group name (prevents cross-tenant leaks)
- ❌ Never trust user input for tenant identification
- ❌ Never join group without verifying access

### Receiving Messages With Tenant Context

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
        
        # Broadcast to group (includes tenant in group name)
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
    from django_tenants.utils import tenant_context
    from myapp.models import ChatMessage
    from django.contrib.auth.models import User
    
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

### Task Progress Updates (Celery + Tenant)

```python
# consumers.py
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
        
        # Task will send updates to this channel
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

### Common Pitfalls

**❌ WRONG: Getting tenant from request data**

```python
async def connect(self):
    tenant_id = self.scope['query_string'].get('tenant_id')  # ❌ User input!
    self.tenant = Tenant.objects.get(id=tenant_id)
```

**✅ CORRECT: Get tenant from middleware scope**

```python
async def connect(self):
    self.tenant = self.scope.get('tenant')  # ✅ Set by middleware
    if not self.tenant:
        await self.close(code=4003)
```

---

**❌ WRONG: Group name without tenant**

```python
async def connect(self):
    self.group_name = f'chat_{self.room_id}'  # ❌ Cross-tenant leaks!
    await self.channel_layer.group_add(self.group_name, ...)
```

**✅ CORRECT: Include tenant in group name**

```python
async def connect(self):
    self.group_name = f'chat_{self.room_id}_{self.tenant.id}'  # ✅ Isolated
    await self.channel_layer.group_add(self.group_name, ...)
```

---

**❌ WRONG: Database query without tenant context**

```python
@database_sync_to_async
def get_room(self, room_id):
    from myapp.models import ChatRoom
    return ChatRoom.objects.get(id=room_id)  # ❌ Wrong schema!
```

**✅ CORRECT: Use tenant_context for queries**

```python
@database_sync_to_async
def get_room(self, room_id, tenant_id):
    from django_tenants.utils import tenant_context
    from myapp.models import ChatRoom
    
    org = Org.objects.get(id=tenant_id)
    with tenant_context(org):
        return ChatRoom.objects.get(id=room_id)  # ✅ Correct schema
```

---

**❌ WRONG: Forgetting tenant verification in connect()**

```python
async def connect(self):
    # Accepts any connection without verifying tenant
    await self.accept()  # ❌ Security issue
```

**✅ CORRECT: Verify before accepting**

```python
async def connect(self):
    if not self.scope.get('tenant'):
        await self.close(code=4003)
        return
    
    if not self.scope.get('user') or not self.user.is_authenticated:
        await self.close(code=4001)
        return
    
    await self.accept()  # ✅ Verified
```

### Async + Tenant Injection Points

1. **settings.py** - ASGI, CHANNEL_LAYERS (same as single-tenant)
2. **asgi.py** - ProtocolTypeRouter, middleware stack
3. **middleware** - Must set `scope['tenant']` before consumer
4. **consumers.py** - Verify `scope['tenant']` in `connect()`
5. **routing.py** - URL patterns for consumers
6. **group_name** - Always include `tenant.id` in group names

**Key difference**: Tenant verification must happen BEFORE `accept()`.

## Why It's Generic

- **Channels**: Industry-standard for Django WebSocket
- **Schema-per-tenant**: Standard multi-tenant pattern
- **Group broadcasting**: Works with any messaging pattern
- **Tenant context propagation**: Applies to any async code
- **Error handling**: Same principles as single-tenant (categorize errors)
- **Scope isolation**: Database-level plus application-level isolation

## Example Use Cases

- **Multi-tenant chat**: Organization-specific chat rooms
- **Collaboration**: Real-time document editing per organization
- **Notifications**: Push notifications scoped to organization
- **Live dashboards**: Organization-specific metrics and updates
- **Status tracking**: Order/ticket status within organization only
- **Presence**: Who's online in specific organization

## Related Skills

- [`SKILL_django-async-websocket.md`](../django-async-websocket/SKILL.md) - **Required foundation** - single-tenant WebSocket patterns
- [`SKILL_django-multi-tenant.md`](../django-multi-tenant/SKILL.md) - **Required reference** - explains `tenant_context()` and schema isolation
- [`SKILL_django-celery-multitenant.md`](../django-celery-multitenant/SKILL.md) - Background tasks that update WebSocket clients
- [`SKILL_django-architecture.md`](../django-architecture/SKILL.md) - Core Django patterns

## References

- [Django Channels Documentation](https://channels.readthedocs.io/)
- [Async Support in Django](https://docs.djangoproject.org/en/stable/topics/async/)
- [@database_sync_to_async](https://docs.djangoproject.org/en/stable/topics/async/#database-access)
- [django-tenants with Channels](https://django-tenants.readthedocs.io/)
- [Group Send Documentation](https://channels.readthedocs.io/en/latest/guide/databases.html)

---

**Last Updated**: 2026-01-27