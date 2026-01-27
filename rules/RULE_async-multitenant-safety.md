# RULE_async-multitenant-safety

## Principle
Verify tenant context before accepting WebSocket connections - never trust user input for tenant identification.

## Details
WebSocket consumers must verify tenant context from middleware scope before accepting connections. Group names must include tenant identifiers to prevent cross-tenant message leaks. All database access in async consumers requires tenant_context() to ensure correct schema isolation.

Tenant verification must occur in connect() before accept() - closing connections for unauthorized access. Channel layer group operations must be tenant-scoped to maintain isolation.

## Examples
✅ **DO: Verify tenant from middleware scope**
```python
async def connect(self):
    self.tenant = self.scope.get('tenant')
    if not self.tenant:
        await self.close(code=4003)  # Tenant not found
        return

    self.user = self.scope.get('user')
    if not self.user or not self.user.is_authenticated:
        await self.close(code=4001)  # User not authenticated
        return

    await self.accept()
```

❌ **DON'T: Trust user input for tenant identification**
```python
async def connect(self):
    tenant_id = self.scope['query_string'].get('tenant_id')  # ❌ User controlled
    self.tenant = Tenant.objects.get(id=tenant_id)
    await self.accept()
```

✅ **DO: Include tenant in group names**
```python
async def connect(self):
    self.room_id = self.scope['url_route']['kwargs']['room_id']
    self.group_name = f'chat_{self.room_id}_{self.tenant.id}'  # ✅ Tenant-scoped
    await self.channel_layer.group_add(self.group_name, self.channel_name)
```

❌ **DON'T: Use tenant-agnostic group names**
```python
async def connect(self):
    self.room_id = self.scope['url_route']['kwargs']['room_id']
    self.group_name = f'chat_{self.room_id}'  # ❌ Cross-tenant leaks possible
    await self.channel_layer.group_add(self.group_name, self.channel_name)
```

✅ **DO: Use tenant_context for database queries**
```python
@database_sync_to_async
def get_room_messages(self, room_id, tenant_id):
    org = Org.objects.get(id=tenant_id)
    with tenant_context(org):
        room = ChatRoom.objects.get(id=room_id)
        return list(room.messages.all())
```

❌ **DON'T: Query without tenant context**
```python
@database_sync_to_async
def get_room_messages(self, room_id):
    # ❌ No tenant context - wrong schema possible
    room = ChatRoom.objects.get(id=room_id)
    return list(room.messages.all())
```

✅ **DO: Verify tenant membership before group operations**
```python
async def receive(self, text_data):
    data = json.loads(text_data)
    room_id = data.get('room_id')

    # Verify user has access to this room in this tenant
    room = await self.get_room_async(room_id, self.tenant.id)
    if not room:
        await self.send(json.dumps({'error': 'Room not found'}))
        return

    await self.channel_layer.group_send(
        f'room_{room_id}_{self.tenant.id}',  # ✅ Tenant-scoped
        {'type': 'chat_message', 'message': data['message']}
    )
```

❌ **DON'T: Skip membership verification**
```python
async def receive(self, text_data):
    data = json.loads(text_data)
    room_id = data.get('room_id')

    # ❌ No verification - user could access other tenant's rooms
    await self.channel_layer.group_send(
        f'room_{room_id}',  # ❌ Not tenant-scoped
        {'type': 'chat_message', 'message': data['message']}
    )
```

✅ **DO: Handle tenant context errors gracefully**
```python
async def receive(self, text_data):
    try:
        data = json.loads(text_data)
        messages = await self.get_messages_async(data['room_id'], self.tenant.id)
        await self.send(json.dumps({'messages': messages}))
    except ChatRoom.DoesNotExist:
        await self.send(json.dumps({'error': 'Room not found in this organization'}))
    except json.JSONDecodeError:
        await self.send(json.dumps({'error': 'Invalid message format'}))
```

❌ **DON'T: Let exceptions crash the consumer**
```python
async def receive(self, text_data):
    data = json.loads(text_data)  # ❌ Crashes on bad JSON
    messages = await self.get_messages_async(data['room_id'], self.tenant.id)  # ❌ Unhandled DoesNotExist
    await self.send(json.dumps({'messages': messages}))
```

## Why This Matters
WebSocket connections bypass traditional request middleware, making tenant verification critical. Without proper tenant scoping, users can access other organizations' real-time data, violating privacy and compliance requirements. Group name isolation prevents message cross-contamination between tenants. These guardrails ensure multi-tenant real-time applications maintain complete data isolation, preventing security breaches through WebSocket channels.