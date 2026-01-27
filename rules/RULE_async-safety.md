# RULE_async-safety

## Principle
Async code must never block the event loop - all database access and I/O operations must use proper async patterns.

## Details
Django's async views and Channels consumers run on a shared event loop. Blocking operations (synchronous database queries, time.sleep, synchronous HTTP calls) will freeze the entire application, preventing other requests and WebSocket connections from being handled. All database access must use @database_sync_to_async decorators, and all I/O must be truly asynchronous.

WebSocket connections must verify user authentication before accepting to prevent unauthorized access. Error handling must gracefully manage malformed data and unexpected exceptions without crashing the consumer.

## Examples
✅ **DO: Use @database_sync_to_async for database access**
```python
async def receive(self, text_data):
    try:
        user_data = await self.get_user_data_async(self.user.id)
        await self.send(json.dumps({'user': user_data}))
    except Exception as exc:
        await self.send(json.dumps({'error': str(exc)}))

@database_sync_to_async
def get_user_data_async(self, user_id):
    return User.objects.get(id=user_id).serialize()
```

❌ **DON'T: Direct database queries in async code**
```python
async def receive(self, text_data):
    user = User.objects.get(id=self.user.id)  # ❌ Blocks event loop
    await self.send(json.dumps({'user': user.serialize()}))
```

✅ **DO: Verify user authentication before accepting connections**
```python
async def connect(self):
    self.user = self.scope.get('user')
    if not self.user or not self.user.is_authenticated:
        await self.close(code=4001)  # Reject unauthenticated
        return
    await self.accept()
```

❌ **DON'T: Accept connections without verification**
```python
async def connect(self):
    self.user = self.scope['user']  # What if None?
    await self.accept()  # ❌ Allows anonymous connections
```

✅ **DO: Handle errors gracefully in message processing**
```python
async def receive(self, text_data):
    try:
        data = json.loads(text_data)
        await self.process_message(data)
    except json.JSONDecodeError:
        await self.send(json.dumps({'error': 'Invalid JSON format'}))
    except Exception as exc:
        await self.send(json.dumps({'error': 'Processing failed'}))
```

❌ **DON'T: Let exceptions crash the consumer**
```python
async def receive(self, text_data):
    data = json.loads(text_data)  # ❌ Crashes on bad JSON
    await self.process_message(data)  # ❌ Unhandled exceptions crash consumer
```

✅ **DO: Use async-friendly operations**
```python
async def process_data(self, data):
    await asyncio.sleep(1)  # ✅ Non-blocking
    result = await self.external_api_call_async(data)  # ✅ Async I/O
    return result
```

❌ **DON'T: Block with synchronous operations**
```python
async def process_data(self, data):
    time.sleep(1)  # ❌ Blocks entire event loop
    result = requests.get(url, data=data)  # ❌ Synchronous HTTP blocks
    return result
```

## Why This Matters
Blocking operations in async code can cause complete application lockup, affecting all users and connections. Improper authentication allows unauthorized WebSocket access. Poor error handling can crash consumers, disconnecting users and potentially losing data. These guardrails ensure scalable, secure real-time applications that maintain responsiveness under load.