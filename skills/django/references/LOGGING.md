# Django Logging Patterns

**Structured logging, monitoring, and audit trails for Django applications**

## Django Logging Configuration

**CRITICAL**: Proper logging configuration is essential for debugging, monitoring, and compliance. Never use print() statements for production logging.

### Basic Logging Setup

**✅ GOOD**: Configure Django logging in settings.py
```python
# settings.py
import os
import logging
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
        'simple': {
            'format': '{levelname} {message}',
            'style': '{',
        },
        'json': {
            'format': '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
            'style': '%',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'simple',
        },
        'file': {
            'class': 'logging.FileHandler',
            'filename': os.path.join(BASE_DIR, 'logs', 'django.log'),
            'formatter': 'verbose',
        },
        'json_file': {
            'class': 'logging.FileHandler',
            'filename': os.path.join(BASE_DIR, 'logs', 'django.json'),
            'formatter': 'json',
        },
    },
    'root': {
        'handlers': ['console', 'file'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['console', 'file'],
            'level': 'INFO',
            'propagate': False,
        },
        'myapp': {
            'handlers': ['console', 'json_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
    },
}
```

**Create logs directory**:
```bash
mkdir -p logs
touch logs/django.log logs/django.json
```

### Structured Logging Patterns

**✅ GOOD**: Use structured logging with context
```python
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class StructuredLogger:
    """Structured logging with consistent context."""
    
    @staticmethod
    def info(message: str, **context):
        """Log info with structured context."""
        logger.info(message, extra={'context': context})
    
    @staticmethod
    def error(message: str, error: Exception = None, **context):
        """Log error with exception and context."""
        if error:
            logger.error(message, exc_info=error, extra={'context': context})
        else:
            logger.error(message, extra={'context': context})

# Usage
StructuredLogger.info(
    "User login successful",
    user_id=user.id,
    ip_address=request.META.get('REMOTE_ADDR'),
    user_agent=request.META.get('HTTP_USER_AGENT')
)

try:
    process_data(data)
except ValueError as e:
    StructuredLogger.error(
        "Data processing failed",
        error=e,
        data_id=data.get('id'),
        user_id=request.user.id
    )
```

**❌ BAD**: Unstructured logging
```python
logger.info(f"User {user.id} logged in from {ip} with {user_agent}")
# ❌ Hard to parse, inconsistent format
```

## Request Logging Middleware

**Log all HTTP requests for debugging and security monitoring**:

```python
# core/middleware.py
import logging
import time
import json

logger = logging.getLogger(__name__)

class RequestLoggingMiddleware:
    """Log all HTTP requests with timing and context."""
    
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        start_time = time.time()
        
        # Log request start
        self._log_request(request, 'start')
        
        response = self.get_response(request)
        
        # Log request end with timing
        duration = time.time() - start_time
        self._log_response(request, response, duration)
        
        return response
    
    def _log_request(self, request, phase: str):
        """Log incoming request details."""
        logger.info(
            f"HTTP {request.method} {request.path}",
            extra={
                'phase': phase,
                'method': request.method,
                'path': request.path,
                # Parameter NAMES only: values can be tokens (see § Keep query strings out of the ASGI server's logs)
                'query_keys': sorted(request.GET.keys()),
                'user_id': request.user.id if request.user.is_authenticated else None,
                'ip': self._get_client_ip(request),
                'user_agent': request.META.get('HTTP_USER_AGENT', ''),
            }
        )
    
    def _log_response(self, request, response, duration: float):
        """Log response details."""
        logger.info(
            f"HTTP {request.method} {request.path} -> {response.status_code}",
            extra={
                'phase': 'end',
                'method': request.method,
                'path': request.path,
                'status_code': response.status_code,
                'duration_ms': round(duration * 1000, 2),
                'content_length': len(response.content) if hasattr(response, 'content') else 0,
            }
        )
    
    def _get_client_ip(self, request):
        """Get real client IP from various headers."""
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            return x_forwarded_for.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR')

# Add to settings.py
MIDDLEWARE = [
    'core.middleware.RequestLoggingMiddleware',
    # ... other middleware
]
```

## Keep query strings out of the ASGI server's logs

A production app passed a WebSocket session token in the socket URL. Turning off uvicorn's access
log (`--no-access-log`) does not keep that token out of the logs; this line is still written on
every connect:

```text
INFO:     203.0.113.7:51234 - "WebSocket /ws/chat/?ws_token=<token>" [accepted]
```

That line is not an access-log line. uvicorn writes it to the **`uvicorn.error`** logger at INFO,
with the path **and query string**, for every accepted WebSocket (and a `403` line, same shape,
for every refused one). `--no-access-log` only empties the `uvicorn.access` logger, so it does not
touch this line. The access logger, when on, also logs the full path with the query string for
every HTTP request.

Checked against uvicorn's source and release notes: the WebSocket lines carry the query string
from 0.19.0 on (release note: "Use path with query string on `WebSockets` logs", encode/uvicorn#1385);
0.18.3 and older logged the path only. Source read for 0.15.0, 0.16 to 0.18.3, 0.19.0, 0.20.0,
0.30.6 and 0.54.0; in 0.54.0 all three WebSocket implementations (`websockets`,
`websockets-sansio`, `wsproto`) log it, and `--no-access-log` only clears the `uvicorn.access`
handlers. Other ASGI servers: run the server-log test below rather than trusting their docs.

The first fix is to keep credentials out of URLs
([ASYNC_WEBSOCKET.md § Public API vs Authenticated Parity](ASYNC_WEBSOCKET.md#public-api-vs-authenticated-parity-token-in-the-first-message-never-the-url)).
This filter is the second, for whatever old or hostile clients still send:

```python
# <project>/logging_filters.py
import logging
from collections.abc import Mapping


def _cut(value):
    return value.split("?", 1)[0] if isinstance(value, str) else value


class DropQueryString(logging.Filter):
    """Cut the message and every str argument at the first '?'."""

    def filter(self, record):
        if not record.args:
            record.msg = _cut(record.msg)      # a pre-formatted message
        elif isinstance(record.args, Mapping):
            record.args = {k: _cut(v) for k, v in record.args.items()}
        else:                                   # uvicorn passes (client, path?query, ...)
            record.args = tuple(_cut(a) for a in record.args)
        return True


def install_query_string_filter():
    for name in ("uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        if not any(isinstance(f, DropQueryString) for f in logger.filters):
            logger.addFilter(DropQueryString())
```

```python
# <project>/asgi.py
from <project>.asgi_app import application  # noqa: F401  builds the router; runs django.setup()
from <project>.logging_filters import install_query_string_filter

install_query_string_filter()
```

Why it has this shape:

- **A logger filter, not a handler filter.** uvicorn logs straight on `uvicorn.error` and
  `uvicorn.access`, so a filter on those two loggers rewrites the record before any handler, file
  or log shipper sees it, whatever `--log-config` you use.
- **Cut the arguments, not the formatted line.** uvicorn's access formatter unpacks
  `record.args` by position (client, method, path, version, status), so the tuple keeps its
  length and the status code survives. A `?` inside some other `uvicorn.error` argument gets cut
  too; that costs little on a server-lines logger.
- **Installed from the ASGI module, after `django.setup()`.** uvicorn imports the app after it
  has applied its own logging config, so the filter lands last. Keep the router in its own
  module (`asgi_app.py`) so a test can serve it without the filter (negative control below).
- **App code is not covered.** Your own loggers, error trackers (which record request URLs) and
  request-logging middleware need the same rule: log `request.path` and the query parameter
  **names**, never their values (see § Request Logging Middleware above).
- **The reverse proxy logs the path only.** nginx's default `combined` format logs `$request`,
  which carries the query string, as do `$request_uri` and `$args`. Use `$uri`:

  ```nginx
  log_format path_only '$remote_addr - [$time_local] "$request_method $uri $server_protocol" '
                       '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
  access_log /var/log/nginx/access.log path_only;
  ```

  `$http_referer` can carry a query string too; drop it if your pages put tokens in URLs.

### The test: run the real server and read what it wrote

A unit test of the filter proves the filter. It does not prove the server's output is clean,
which is the claim that matters. Run the real server with a fresh marker in the URL and assert,
as a boolean, that the marker is absent. Add a control (the line was written at all) and a
negative control (without the filter the marker appears), or a server that stopped logging
WebSockets would make the test pass for the wrong reason.

```python
# tests/test_server_logs.py  (integration: starts a real uvicorn)
def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _wait_for(log, text, tries=100):
    for _ in range(tries):
        log.seek(0)
        if text in log.read():
            return
        time.sleep(0.1)


def server_log(app, *extra_args):
    """Serve `app`, send one WebSocket and one HTTP request whose URLs carry a fresh marker,
    and return (marker, everything the server wrote)."""
    marker = "m" + secrets.token_hex(16)   # a marker, never a real token
    port = _free_port()
    with tempfile.TemporaryFile("w+") as log:
        proc = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", app, "--port", str(port), "--lifespan", "off", *extra_args],
            cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT, text=True)
        try:
            _wait_for(log, "Uvicorn running on")
            try:
                with websockets.sync.client.connect(f"ws://127.0.0.1:{port}/ws/chat/?ws_token={marker}") as ws:
                    ws.recv(timeout=2)
            except websockets.exceptions.ConnectionClosed:
                pass
            try:  # urllib, not httpx: httpx logs every URL it fetches at INFO
                urllib.request.urlopen(f"http://127.0.0.1:{port}/api/ws-ticket/?ws_token={marker}", timeout=5)
            except urllib.error.HTTPError:
                pass
            time.sleep(0.3)
        finally:
            proc.terminate()
            proc.wait(timeout=10)
        log.seek(0)
        return marker, log.read()


class ServerLogTests(SimpleTestCase):
    def test_token_absent_from_server_log(self):
        marker, out = server_log("<project>.asgi:application")
        self.assertTrue('"WebSocket /ws/chat/" [accepted]' in out)  # control: the line was written
        self.assertFalse(marker in out)

    def test_token_absent_with_no_access_log(self):
        marker, out = server_log("<project>.asgi:application", "--no-access-log")
        self.assertTrue('"WebSocket /ws/chat/' in out)
        self.assertFalse(marker in out)

    def test_negative_control_without_filter_the_token_is_logged(self):
        marker, out = server_log("<project>.asgi_app:application", "--no-access-log")
        self.assertTrue(marker in out)
```

`assertFalse(marker in out)`, never `assertNotIn(marker, out)`: the failure message of
`assertNotIn` prints the whole captured log. Run app loggers at INFO to stderr in this test (a
production-like `LOGGING`) so a consumer that logs its query string shows up in `out` and turns
the test red. That is the mutation check for this test.

Verified end to end on uvicorn 0.54.0, Django 6.1, Channels 4.3: the negative control finds the
marker in the `[accepted]` line with `--no-access-log`; with the filter both runs are clean; a
consumer mutated to `logger.info()` its query string fails both clean-log tests.

## Database Query Logging

**Monitor slow queries and N+1 problems**:

```python
# settings.py - Add database logging
LOGGING['loggers']['django.db.backends'] = {
    'handlers': ['console', 'file'],
    'level': 'DEBUG',  # Log all SQL queries
    'propagate': False,
}

# For production - only log slow queries
LOGGING['loggers']['django.db.backends'] = {
    'handlers': ['file'],
    'level': 'WARNING',  # Only warnings/errors
    'propagate': False,
}
```

**Custom database logging**:
```python
# core/middleware.py
import logging
from django.db import connection
from django.utils import timezone

logger = logging.getLogger(__name__)

class DatabaseLoggingMiddleware:
    """Log database query counts and timing per request."""
    
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        # Reset query log
        connection.queries_log.clear()
        start_queries = len(connection.queries)
        
        response = self.get_response(request)
        
        # Log query statistics
        end_queries = len(connection.queries)
        query_count = end_queries - start_queries
        
        if query_count > 10:  # Alert on high query counts
            logger.warning(
                f"High query count: {query_count} queries for {request.path}",
                extra={
                    'path': request.path,
                    'method': request.method,
                    'query_count': query_count,
                    'user_id': request.user.id if request.user.is_authenticated else None,
                }
            )
        
        return response
```

## Security Audit Logging

**Log security-relevant events for compliance**:

```python
# core/logging.py
import logging
from django.contrib.auth.signals import user_logged_in, user_logged_out, user_login_failed
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

audit_logger = logging.getLogger('audit')

# Configure audit logger in settings.py
LOGGING['loggers']['audit'] = {
    'handlers': ['audit_file'],
    'level': 'INFO',
    'propagate': False,
}
LOGGING['handlers']['audit_file'] = {
    'class': 'logging.FileHandler',
    'filename': os.path.join(BASE_DIR, 'logs', 'audit.log'),
    'formatter': 'verbose',
}

@receiver(user_logged_in)
def log_user_login(sender, request, user, **kwargs):
    """Log successful user logins."""
    audit_logger.info(
        f"User login: {user.username}",
        extra={
            'event': 'user_login',
            'user_id': user.id,
            'username': user.username,
            'ip': request.META.get('REMOTE_ADDR'),
            'user_agent': request.META.get('HTTP_USER_AGENT'),
        }
    )

@receiver(user_login_failed)
def log_failed_login(sender, credentials, **kwargs):
    """Log failed login attempts."""
    audit_logger.warning(
        "Failed login attempt",
        extra={
            'event': 'login_failed',
            'username': credentials.get('username', 'unknown'),
        }
    )

@receiver(post_save, sender='auth.User')
def log_user_changes(sender, instance, created, **kwargs):
    """Log user creation/modification."""
    action = 'created' if created else 'modified'
    audit_logger.info(
        f"User {action}: {instance.username}",
        extra={
            'event': f'user_{action}',
            'user_id': instance.id,
            'username': instance.username,
        }
    )
```

## Error Monitoring and Alerting

**Log errors with full context and alerting**:

```python
# core/middleware.py
import logging
import traceback
from django.conf import settings

logger = logging.getLogger(__name__)

class ErrorLoggingMiddleware:
    """Catch and log unhandled exceptions."""
    
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        try:
            response = self.get_response(request)
            return response
        except Exception as e:
            self._log_error(request, e)
            raise  # Re-raise the exception
    
    def _log_error(self, request, exception):
        """Log error with full context."""
        logger.error(
            f"Unhandled exception: {exception}",
            exc_info=exception,
            extra={
                'path': request.path,
                'method': request.method,
                'user_id': request.user.id if request.user.is_authenticated else None,
                'user_agent': request.META.get('HTTP_USER_AGENT'),
                'ip': request.META.get('REMOTE_ADDR'),
                'query_keys': sorted(request.GET.keys()),  # names only, never values
                'post_data': self._sanitize_post_data(request.POST),
            }
        )
    
    def _sanitize_post_data(self, post_data):
        """Remove sensitive data from POST logging."""
        sensitive_keys = {'password', 'token', 'api_key', 'secret'}
        sanitized = {}
        for key, value in post_data.items():
            if key.lower() in sensitive_keys:
                sanitized[key] = '[REDACTED]'
            else:
                sanitized[key] = value
        return sanitized
```

## Log Aggregation and Monitoring

**Send logs to external services for monitoring**:

```python
# settings.py - Add external handlers
import os

# Sentry for error monitoring
if os.getenv('SENTRY_DSN'):
    LOGGING['handlers']['sentry'] = {
        'class': 'sentry_sdk.integrations.logging.EventHandler',
        'level': 'ERROR',
    }
    LOGGING['root']['handlers'].append('sentry')

# CloudWatch for AWS
if os.getenv('AWS_REGION'):
    LOGGING['handlers']['cloudwatch'] = {
        'class': 'watchtower.CloudWatchLogHandler',
        'level': 'INFO',
        'log_group': 'django-app',
        'stream_name': f"{os.getenv('ENVIRONMENT', 'dev')}-{os.getenv('HOSTNAME', 'unknown')}",
    }
    LOGGING['root']['handlers'].append('cloudwatch')
```

## Logging Best Practices

### Performance Considerations
- **Use appropriate log levels**: DEBUG for development, INFO for production
- **Avoid logging in hot paths**: Don't log every request in high-traffic endpoints
- **Use sampling for high-volume logs**: Log 1% of similar events
- **Compress old logs**: Use logrotate for file rotation

### Security Considerations
- **Never log sensitive data**: Passwords, tokens, PII
- **Use audit logs for compliance**: Separate security events
- **Implement log retention policies**: GDPR compliance
- **Monitor log access**: Audit who views logs

### Development vs Production
```python
# Development - detailed logging
LOGGING['root']['level'] = 'DEBUG'

# Production - structured logging
LOGGING['root']['level'] = 'INFO'
LOGGING['handlers']['json_file']['formatter'] = 'json'
```

## Common Logging Patterns

### Service Layer Logging
```python
class UserService:
    """User operations with comprehensive logging."""
    
    def create_user(self, data):
        logger.info("Creating user", email=data.get('email'))
        try:
            user = User.objects.create_user(**data)
            logger.info("User created successfully", user_id=user.id)
            return user
        except Exception as e:
            logger.error("User creation failed", error=str(e), email=data.get('email'))
            raise
```

### API Logging
```python
class ArticleViewSet(viewsets.ModelViewSet):
    def create(self, request, *args, **kwargs):
        logger.info(
            "Creating article",
            user_id=request.user.id,
            title=request.data.get('title')
        )
        return super().create(request, *args, **kwargs)
```

### Background Task Logging
```python
@shared_task
def process_data(data_id):
    logger.info("Starting data processing", data_id=data_id)
    try:
        # Processing logic
        logger.info("Data processing completed", data_id=data_id)
    except Exception as e:
        logger.error("Data processing failed", data_id=data_id, error=str(e))
        raise
```

## Log Analysis Tools

**Parse and analyze logs for insights**:

```bash
# Count errors by hour
grep "ERROR" logs/django.log | cut -d' ' -f1 | sort | uniq -c

# Find slow requests (>1s)
grep "duration_ms.*[0-9]\{4,\}" logs/django.log

# Count requests by endpoint
grep "HTTP.*->" logs/django.log | sed 's/.*HTTP \([A-Z]*\) \([^ ]*\).*-> \([0-9]*\).*/\1 \2 \3/' | sort | uniq -c
```

## External Resources

- [Django Logging Documentation](https://docs.djangoproject.com/en/stable/topics/logging/)
- [Python Logging Documentation](https://docs.python.org/3/library/logging.html)
- [Structured Logging](https://www.structlog.org/)
- [Sentry Django Integration](https://docs.sentry.io/platforms/python/guides/django/)
- [ELK Stack for Log Aggregation](https://www.elastic.co/elastic-stack)