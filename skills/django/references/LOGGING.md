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
                'query_string': request.GET.urlencode() if request.GET else '',
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
                'query_string': request.GET.urlencode(),
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