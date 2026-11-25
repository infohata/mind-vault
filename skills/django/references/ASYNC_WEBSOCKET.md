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
        # A close() BEFORE accept() refuses the handshake: the browser sees HTTP 403 and never
        # the 4001/4003 code. Fine for cookie-authenticated sockets; accept first when the
        # client must act on the reason (see § Public API vs Authenticated Parity).
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

        # Verify user owns this task (a close before accept() reaches the client as HTTP 403)
        self.user = self.scope['user']
        if not self.user.is_authenticated or not await self.user_owns_task(self.user.id, self.task_id):
            await self.close(code=4403)  # app close codes are 4000-4999; 403 is not a valid one
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

## Public API vs Authenticated Parity (token in the first message, never the URL)

A production app let anonymous browsers own chat sessions by passing a session token as
`wss://<host>/ws/chat/?ws_token=<token>`. Every connect wrote that token into the reverse proxy's
access log and into the ASGI server's own log (uvicorn logs each accepted WebSocket with its
query string, see [LOGGING.md § Keep query strings out of the ASGI server's logs](LOGGING.md#keep-query-strings-out-of-the-asgi-servers-logs)),
and from there into log shipping and monitoring. A URL is logged by every hop that sees it; a
credential in one is a leaked credential. This section used to teach that pattern.

The intent stays: logged-in users and anonymous browsers go through **one** code path, each
scoped to what it owns. Only the transport of the credential changes.

**1. Mint a short-lived ticket over POST** (body in, body out — never a GET with the token in the URL):

```python
# views.py
TICKET_SALT = "ws-ticket"

@require_POST  # CSRF stays on
def ws_ticket(request):
    if request.user.is_authenticated:
        owner = f"user:{request.user.pk}"
    else:
        # An opaque id kept in the session, never the session key itself: the session key IS the
        # session cookie, and it also changes on login (cycle_key), orphaning what the user owned.
        owner = "anon:" + request.session.setdefault("anon_owner", secrets.token_urlsafe(16))
    ticket = signing.dumps({"owner": owner, "tenant": request.tenant_id}, salt=TICKET_SALT)
    return JsonResponse({"ticket": ticket, "expires_in": settings.WS_TICKET_MAX_AGE_SECONDS})
```

**2. The client connects with no credentials in the URL and sends the ticket first:**

```javascript
const { ticket } = await (await fetch("/api/ws-ticket/", {
  method: "POST", headers: { "X-CSRFToken": csrfToken },
})).json();
const ws = new WebSocket(`wss://${location.host}/ws/chat/`);   // no query string
ws.onopen = () => ws.send(JSON.stringify({ type: "auth", ticket }));
```

**3. The consumer accepts, waits briefly for the auth message, and closes with a specific code:**

```python
# consumers.py — close codes are 4000 + the HTTP status they mirror
CLOSE_UNAUTHENTICATED = 4401  # first message is not an auth message; ticket missing, forged or expired
CLOSE_WRONG_TENANT = 4403
CLOSE_AUTH_TIMEOUT = 4408
CLOSE_QUERY_STRING = 4414     # this endpoint takes no query string

class ChatConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.owner = None
        self._deadline = None
        await self.accept()  # accept first: a close BEFORE accept reaches the browser as a bare HTTP 403, no code
        if self.scope.get("query_string"):  # emptiness only: never decode, parse or log it
            await self.close(code=CLOSE_QUERY_STRING)
            return
        self._deadline = asyncio.create_task(self._expire_unauthenticated())

    async def _expire_unauthenticated(self):
        await asyncio.sleep(settings.WS_AUTH_TIMEOUT_SECONDS)  # a few seconds
        if self.owner is None:
            await self.close(code=CLOSE_AUTH_TIMEOUT)

    async def disconnect(self, code):
        if self._deadline:
            self._deadline.cancel()

    async def receive_json(self, content, **kwargs):
        if self.owner is None:
            if not isinstance(content, dict) or content.get("type") != "auth":
                await self.close(code=CLOSE_UNAUTHENTICATED)
                return
            await self._authenticate(content.get("ticket"))
            return
        ...  # normal messages; every query is filtered by self.owner

    async def _authenticate(self, ticket):
        if not isinstance(ticket, str):
            await self.close(code=CLOSE_UNAUTHENTICATED)
            return
        try:  # SignatureExpired is a subclass of BadSignature
            claim = signing.loads(ticket, salt=TICKET_SALT, max_age=settings.WS_TICKET_MAX_AGE_SECONDS)
        except signing.BadSignature:
            await self.close(code=CLOSE_UNAUTHENTICATED)
            return
        if claim.get("tenant") != self.scope["tenant_id"]:  # set by your tenant middleware
            await self.close(code=CLOSE_WRONG_TENANT)
            return
        if self._deadline:
            self._deadline.cancel()
        self.owner = claim["owner"]
        await self.send_json({"type": "auth.ok"})
```

**4. The REST side uses the same owner, read from the session or an `Authorization` header — never
`request.query_params`:**

```python
def get_queryset(self):
    if self.request.user.is_authenticated:
        return Model.objects.filter(author=self.request.user)
    anon_owner = self.request.session.get("anon_owner")
    if anon_owner:
        return Model.objects.filter(author__isnull=True, anon_owner=anon_owner)
    return Model.objects.none()
```

The rules, each tied to the example above:

- **No credential in any URL** — WebSocket, REST or redirect. Proxies, the ASGI server, error
  trackers and browser history all keep URLs. The ticket travels in a POST body and in the
  socket's first message, which nothing logs by default.
- **Accept, then close with a code.** A `close()` before `accept()` makes the server refuse the
  handshake with HTTP 403 (ASGI spec), so the browser sees only a failed connect (often code 1006)
  and cannot tell "log in again" from "wrong tenant". Accept first when the client must act on
  the reason. 4000 + the HTTP status (4401, 4403, 4408, 4414) reads at a glance in client code
  and logs.
- **Refuse any query string on an endpoint that takes none.** Check only that
  `scope["query_string"]` is empty. Decoding, parsing or logging it handles the token you are
  trying to keep out.
- **Short timeout, short ticket.** An unauthenticated socket gets a few seconds; the ticket a
  minute or less, so a ticket that leaks anyway is soon useless. Make it single-use if replay
  inside that minute matters (store a nonce, refuse it the second time).
- **The ticket carries no secret worth stealing beyond its own minute.** `signing.dumps` output
  is signed, not encrypted, so the payload holds only an opaque owner id and the tenant.
- **Same-origin browsers may not need a ticket at all.** When the session cookie reaches the
  socket, `AuthMiddlewareStack` already puts the user and `scope["session"]` on the scope. The
  ticket is for clients whose cookie does not arrive: cross-origin embeds, native apps.
- **Strip query strings from the server logs as well** (the filter in
  [LOGGING.md § Keep query strings out of the ASGI server's logs](LOGGING.md#keep-query-strings-out-of-the-asgi-servers-logs)).
  The refusal above stops the app from *using* a URL token. It does not stop the server from
  *writing* one that an old or hostile client sends.

### Moving an existing app off URL tokens

Old clients keep sending `?ws_token=` until they update. Accept it behind a dated setting, in one
place, and delete that place with the setting:

```python
# settings.py
WS_URL_TOKEN_ACCEPTED_UNTIL = env.date("WS_URL_TOKEN_ACCEPTED_UNTIL", default=None)  # e.g. two weeks out

# consumers.py, inside connect(), replacing the plain refusal
if self.scope.get("query_string"):
    until = settings.WS_URL_TOKEN_ACCEPTED_UNTIL
    if until is not None and datetime.date.today() <= until:
        values = parse_qs(self.scope["query_string"].decode("ascii", "replace")).get("ws_token", [])
        await self._authenticate(values[0] if len(values) == 1 else None)  # the only reader; delete with the setting
    else:
        await self.close(code=CLOSE_QUERY_STRING)
    return
```

During the window the ASGI server and the proxy still write every URL token to their logs. Ship
the log filter and the proxy's path-only log format **before** opening the window, keep the window
short, and treat the tokens already in old logs as leaked (expire them, rotate what they protect).

### Tests that prove it

Assert booleans only (`assertTrue(code == 4414)`, `assertFalse(marker in out)`): a failing
`assertEqual` or `assertIn` prints both sides, and one side can be a token, straight into CI logs.

```python
def make_ticket(tenant="tenant-a.example", owner="anon:test"):
    return signing.dumps({"owner": owner, "tenant": tenant}, salt=TICKET_SALT)


async def closed_with(path, first_message=None, timeout=2):
    """The close code the server sent, or None when the socket stayed open."""
    comm = WebsocketCommunicator(application, path, headers=[(b"host", b"tenant-a.example")])
    connected, _ = await comm.connect()
    assert connected
    if first_message is not None:
        await comm.send_json_to(first_message)
    try:
        out = await comm.receive_output(timeout=timeout)
    except asyncio.TimeoutError:
        out = None
    await comm.disconnect()
    return out.get("code") if out and out["type"] == "websocket.close" else None

class FirstMessageAuthTests(SimpleTestCase):
    async def test_valid_token_in_url_without_first_message_is_refused(self):
        self.assertTrue(await closed_with(f"/ws/chat/?ws_token={make_ticket()}") == 4414)

    @override_settings(WS_AUTH_TIMEOUT_SECONDS=0.2)
    async def test_no_first_message_times_out(self):
        self.assertTrue(await closed_with("/ws/chat/") == 4408)

    async def test_forged_ticket_is_refused(self):
        forged = make_ticket()[:-2] + "xx"
        self.assertTrue(await closed_with("/ws/chat/", {"type": "auth", "ticket": forged}) == 4401)

    # plus: valid first message -> {"type": "auth.ok"}; expired ticket (patch
    # django.core.signing.time.time while minting) -> 4401; other tenant -> 4403;
    # non-auth first message -> 4401; GET on the ticket endpoint -> 405.
```

The test that matters most is the first one: a **valid** token in the URL, no first message. A
refusal test with a junk query string (`?x=1`) also passes for a consumer that refuses junk but
still honours a real token; only a valid token proves the URL is never read. The second proof, that the ASGI server's real output carries no token, needs the
real server and lives in [LOGGING.md § Keep query strings out of the ASGI server's logs](LOGGING.md#keep-query-strings-out-of-the-asgi-servers-logs).

**Mutation check before you trust the suite:** make `connect()` authenticate from
`scope["query_string"]` and the URL-token test must fail; make it `logger.info()` the query
string and the server-log test must fail. A suite that stays green under either change is
not testing this.

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
