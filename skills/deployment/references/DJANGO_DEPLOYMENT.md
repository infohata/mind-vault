# Django Deployment

## Overview
Django-specific deployment patterns extending the generic [deployment skill](../deployment/SKILL.md), focusing on Django ORM migrations, static/media file handling, Django settings management, and integration with Django monitoring tools. Provides production-ready deployment configurations for Django applications with multi-tenant support.

## When to Use
Django applications requiring:
- Safe database migrations during deployment
- Static and media file management
- Environment-specific Django settings
- Multi-tenant deployment considerations
- Integration with Django ecosystem tools
- Production-ready configurations for Django Channels, Celery, etc.

## Pattern

### Django-Specific Health Checks

#### Django Health Check Endpoint
**Comprehensive Django health checks:**
```python
# core/health.py
from django.http import JsonResponse
from django.db import connection
from django.core.management import call_command
from django.conf import settings
import redis
import os

def django_health_check(request):
    """Enhanced health check for Django applications."""
    health_status = {
        'status': 'healthy',
        'service': 'django-app',
        'version': getattr(settings, 'VERSION', 'unknown'),
        'environment': getattr(settings, 'ENVIRONMENT', 'unknown'),
        'checks': {
            'database': check_database_migrations(),
            'redis': check_redis_connection(),
            'static_files': check_static_files(),
            'media_storage': check_media_storage(),
            'celery': check_celery_workers() if hasattr(settings, 'CELERY_BROKER_URL') else {'status': 'not_configured'},
            'channels': check_channels() if 'channels' in settings.INSTALLED_APPS else {'status': 'not_configured'},
        },
        'timestamp': timezone.now().isoformat()
    }

    # Check if any critical service is unhealthy
    critical_checks = ['database', 'redis']
    if any(health_status['checks'][check]['status'] != 'healthy' for check in critical_checks if health_status['checks'][check]['status'] != 'not_configured'):
        health_status['status'] = 'unhealthy'

    status_code = 200 if health_status['status'] == 'healthy' else 503
    return JsonResponse(health_status, status=status_code)

def check_database_migrations():
    """Check if all migrations are applied."""
    try:
        # Check for unapplied migrations
        from django.core.management.sql import sql_migrate
        from django.db import models
        from django.apps import apps

        unapplied = []
        for app_config in apps.get_app_configs():
            for model in app_config.get_models():
                if hasattr(model._meta.apps, 'check_models'):
                    # Django 3.2+ migration check
                    try:
                        call_command('check', app_labels=[app_config.label], verbosity=0)
                    except SystemCheckError:
                        unapplied.append(app_config.label)

        if unapplied:
            return {
                'status': 'unhealthy',
                'message': f'Unapplied migrations in: {", ".join(unapplied)}',
                'details': {'unapplied_apps': unapplied}
            }

        return {
            'status': 'healthy',
            'message': 'All migrations applied',
            'details': {'applied_migrations': get_applied_migrations_count()}
        }
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Migration check failed: {str(e)}'
        }

def get_applied_migrations_count():
    """Get count of applied migrations."""
    from django.db.migrations.recorder import MigrationRecorder
    return MigrationRecorder(connection).applied_migrations().__len__()

def check_redis_connection():
    """Check Redis connectivity."""
    try:
        if hasattr(settings, 'CACHES') and 'default' in settings.CACHES:
            cache_config = settings.CACHES['default']
            if cache_config.get('BACKEND') == 'django.core.cache.backends.redis.RedisCache':
                import redis
                host = cache_config.get('LOCATION', 'redis:6379').split(':')[0]
                port = int(cache_config.get('LOCATION', 'redis:6379').split(':')[1])
                r = redis.Redis(host=host, port=port, db=0, socket_connect_timeout=5)
                r.ping()
                return {'status': 'healthy', 'message': 'Redis connection OK'}
        return {'status': 'not_configured', 'message': 'Redis not configured'}
    except Exception as e:
        return {'status': 'unhealthy', 'message': f'Redis connection failed: {str(e)}'}

def check_static_files():
    """Check if static files are collected and accessible."""
    try:
        static_root = getattr(settings, 'STATIC_ROOT', None)
        if not static_root or not os.path.exists(static_root):
            return {'status': 'unhealthy', 'message': 'STATIC_ROOT not configured or missing'}

        # Check for essential static files
        admin_css = os.path.join(static_root, 'admin', 'css', 'base.css')
        if not os.path.exists(admin_css):
            return {'status': 'unhealthy', 'message': 'Admin static files not collected'}

        return {'status': 'healthy', 'message': 'Static files collected'}
    except Exception as e:
        return {'status': 'error', 'message': f'Static files check failed: {str(e)}'}

def check_media_storage():
    """Check media file storage accessibility."""
    try:
        media_root = getattr(settings, 'MEDIA_ROOT', None)
        if not media_root:
            return {'status': 'not_configured', 'message': 'Media storage not configured'}

        # Test write access
        test_file = os.path.join(media_root, '.health_check')
        with open(test_file, 'w') as f:
            f.write('health_check')
        os.remove(test_file)

        return {'status': 'healthy', 'message': 'Media storage accessible'}
    except Exception as e:
        return {'status': 'unhealthy', 'message': f'Media storage check failed: {str(e)}'}

def check_celery_workers():
    """Check Celery worker connectivity."""
    try:
        from celery import Celery
        app = Celery()
        app.config_from_object(settings, namespace='CELERY')

        # Check if broker is accessible
        inspect = app.control.inspect()
        active_workers = inspect.active()

        if not active_workers:
            return {'status': 'warning', 'message': 'No active Celery workers'}

        return {
            'status': 'healthy',
            'message': f'Celery workers active: {len(active_workers)}',
            'details': {'active_workers': len(active_workers)}
        }
    except Exception as e:
        return {'status': 'unhealthy', 'message': f'Celery check failed: {str(e)}'}

def check_channels():
    """Check Django Channels configuration."""
    try:
        from channels.layers import get_channel_layer
        layer = get_channel_layer()

        # Test channel layer connectivity
        if hasattr(layer, 'send'):
            return {'status': 'healthy', 'message': 'Channels layer configured'}
        else:
            return {'status': 'warning', 'message': 'Channels layer not fully configured'}
    except Exception as e:
        return {'status': 'unhealthy', 'message': f'Channels check failed: {str(e)}'}
```

### Django Settings for Production

#### Environment-Specific Settings
**Production-ready Django settings:**
```python
# settings/production.py
import os
from .base import *

# Production environment settings
ENVIRONMENT = 'production'
DEBUG = False
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY')

# Security settings
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31536000  # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# Allowed hosts
ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', 'example.com').split(',')

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('DB_NAME'),
        'USER': os.environ.get('DB_USER'),
        'PASSWORD': os.environ.get('DB_PASSWORD'),
        'HOST': os.environ.get('DB_HOST', 'db'),
        'PORT': os.environ.get('DB_PORT', '5432'),
        'OPTIONS': {
            'sslmode': 'require',
        },
        'CONN_MAX_AGE': 600,  # Persistent connections
        'ATOMIC_REQUESTS': False,  # Better performance
    }
}

# Cache
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': os.environ.get('REDIS_URL', 'redis://redis:6379/1'),
    }
}

# Static files
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STATICFILES_STORAGE = 'django.contrib.staticfiles.storage.ManifestStaticFilesStorage'

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

# Email
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.environ.get('EMAIL_HOST')
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', 587))
EMAIL_USE_TLS = True
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD')

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(asctime)s %(name)s %(levelname)s %(message)s',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
        'file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/django/app.log',
            'maxBytes': 10*1024*1024,  # 10MB
            'backupCount': 5,
            'formatter': 'json',
        },
        'mail_admins': {
            'level': 'ERROR',
            'class': 'django.utils.log.AdminEmailHandler',
            'include_html': True,
        },
    },
    'root': {
        'handlers': ['console', 'file', 'mail_admins'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['console', 'file'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.request': {
            'handlers': ['mail_admins'],
            'level': 'ERROR',
            'propagate': False,
        },
    },
}

# Performance optimizations
USE_TZ = True
USE_I18N = True
USE_L10N = True

# Compression
MIDDLEWARE.insert(1, 'django.middleware.gzip.GZipMiddleware')

# Security middleware
MIDDLEWARE.insert(1, 'django.middleware.security.SecurityMiddleware')

# Version info (for health checks)
try:
    with open(os.path.join(BASE_DIR, 'VERSION')) as f:
        VERSION = f.read().strip()
except:
    VERSION = None
```

### Django Deployment Scripts

#### SCSS/Sass Compilation Before Collectstatic
**Critical**: When using SCSS/Sass (e.g. libsass, `compile_scss` management command), always compile before collectstatic:

```bash
# Compile SCSS first (theme.scss → theme.css)
python manage.py compile_scss --style compressed
python manage.py collectstatic --noinput
```

**Dependency rebuild edge case**: When deployment detects dependency changes (requirements, Dockerfile), it rebuilds containers. The generic `deploy_update.sh` sets `HAS_STATIC=true` whenever `HAS_DEPENDENCIES=true`, ensuring SCSS compile + collectstatic run after every rebuild. Without this, production can end up with stale or missing compiled CSS because change detection may miss SCSS files (e.g. when git reflog is unavailable on the server).

#### Enhanced Deployment Scripts
**Django-aware deployment script:**
```bash
#!/bin/bash
# scripts/django_deploy.sh
set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT=${1:-production}
REMOTE_HOST=${2:-}
REMOTE_USER=${3:-deploy}
REMOTE_DIR=${4:-/opt/django-app}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Pre-deployment checks
check_django_app() {
    log "Checking Django application..."

    if [ ! -f "manage.py" ]; then
        error "No manage.py found. Are you in a Django project root?"
        exit 1
    fi

    if [ ! -f "requirements.txt" ]; then
        warning "No requirements.txt found. Make sure dependencies are properly managed."
    fi
}

# Django-specific deployment steps
django_pre_deploy() {
    log "Running Django pre-deployment checks..."

    # Check for uncommitted migrations
    UNCOMMITTED_MIGRATIONS=$(find . -name "*.py" -path "*/migrations/*" -newer $(git log --pretty=format:%H -1 --name-only | head -1) 2>/dev/null | wc -l)
    if [ "$UNCOMMITTED_MIGRATIONS" -gt 0 ]; then
        warning "Found uncommitted migration files. Make sure to commit them before deployment."
    fi

    # Check for pending migrations
    PENDING=$(python manage.py showmigrations --list | grep -c "\[ \]")
    if [ "$PENDING" -gt 0 ]; then
        log "Found $PENDING pending migrations. They will be applied during deployment."
    fi
}

django_deploy() {
    log "Deploying Django application..."

    # Compile SCSS/Sass before collectstatic (if using libsass/compile_scss)
    if python manage.py compile_scss --style compressed 2>/dev/null; then
        log "SCSS compiled"
    fi
    # Collect static files
    log "Collecting static files..."
    python manage.py collectstatic --noinput --clear

    # Run database migrations
    log "Running database migrations..."
    python manage.py migrate --verbosity=1

    # Create superuser if needed (optional)
    if [ "$CREATE_SUPERUSER" = "true" ]; then
        log "Creating superuser..."
        echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='$SUPERUSER_USERNAME').exists() or User.objects.create_superuser('$SUPERUSER_USERNAME', '$SUPERUSER_EMAIL', '$SUPERUSER_PASSWORD')" | python manage.py shell
    fi

    # Clear cache
    log "Clearing Django cache..."
    python manage.py clear_cache 2>/dev/null || true

    # Run Django checks
    log "Running Django system checks..."
    python manage.py check --deploy

    # Update search indexes if haystack is used
    if python -c "import haystack; print('haystack')" 2>/dev/null; then
        log "Updating search indexes..."
        python manage.py update_index --verbosity=0
    fi
}

django_post_deploy() {
    log "Running Django post-deployment tasks..."

    # Health check
    log "Running health checks..."
    curl -f -s http://localhost:8000/health/ > /dev/null
    if [ $? -eq 0 ]; then
        log "Health check passed!"
    else
        warning "Health check failed. Please check application logs."
    fi

    # Restart services
    log "Restarting Django services..."
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl restart django-app
        supervisorctl restart celery-worker 2>/dev/null || true
        supervisorctl restart celery-beat 2>/dev/null || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart django-app
        systemctl restart celery-worker 2>/dev/null || true
        systemctl restart celery-beat 2>/dev/null || true
    fi
}

# Remote deployment wrapper
remote_deploy() {
    local host=$1
    local user=$2
    local dir=$3

    log "Deploying to remote server: $user@$host:$dir"

    # Copy deployment script to remote
    scp "$PROJECT_ROOT/scripts/django_deploy.sh" "$user@$host:/tmp/"

    # Execute remote deployment
    ssh "$user@$host" << EOF
        cd "$dir"
        chmod +x /tmp/django_deploy.sh
        /tmp/django_deploy.sh local
        rm /tmp/django_deploy.sh
EOF
}

# Main deployment flow
main() {
    log "Starting Django deployment to $ENVIRONMENT environment"

    check_django_app
    django_pre_deploy

    if [ -n "$REMOTE_HOST" ]; then
        remote_deploy "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_DIR"
    else
        django_deploy
        django_post_deploy
    fi

    log "Django deployment completed successfully!"
}

# Run main function
main "$@"
```

### Multi-Tenant Django Deployment

#### Tenant-Aware Deployment
**Multi-tenant deployment considerations:**
```python
# For django-tenants
# settings/production.py additions
TENANT_MODEL = 'customers.Tenant'
TENANT_DOMAIN_MODEL = 'customers.Domain'

DATABASE_ROUTERS = (
    'django_tenants.routers.TenantSyncRouter',
)

MIDDLEWARE = [
    'django_tenants.middleware.TenantMainMiddleware',  # Must be first
    # ... other middleware
]

# Public schema database
DATABASES = {
    'default': {
        # Public schema configuration
    }
}

DATABASE_ROUTERS = [
    'django_tenants.routers.TenantSyncRouter',
]

# Tenant-specific settings
TENANT_BASE = 'django_tenants.middleware.TenantMainMiddleware'

# Health check for multi-tenant
def check_tenant_schemas():
    """Check tenant schemas health."""
    from django_tenants.utils import get_tenant_model

    try:
        Tenant = get_tenant_model()
        tenants = Tenant.objects.all()

        unhealthy_tenants = []
        for tenant in tenants:
            try:
                # Switch to tenant schema and run checks
                with tenant_context(tenant):
                    # Check tenant-specific migrations
                    call_command('showmigrations', verbosity=0)
            except Exception as e:
                unhealthy_tenants.append({
                    'tenant': tenant.name,
                    'error': str(e)
                })

        if unhealthy_tenants:
            return {
                'status': 'warning',
                'message': f'Unhealthy tenant schemas: {len(unhealthy_tenants)}',
                'details': {'unhealthy_tenants': unhealthy_tenants}
            }

        return {
            'status': 'healthy',
            'message': f'All {tenants.count()} tenant schemas healthy'
        }
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Tenant schema check failed: {str(e)}'
        }
```

### Celery Background Task Deployment

#### Celery Service Configuration
**Production Celery setup with Docker Compose:**
```yaml
# docker-compose.yml - Celery services
version: '3.8'
services:
  celery-worker:
    build: .
    command: celery -A myproject worker --loglevel=info --concurrency=4
    environment:
      - DJANGO_SETTINGS_MODULE=myproject.settings.production
      - CELERY_BROKER_URL=redis://redis:6379/1
      - CELERY_RESULT_BACKEND=redis://redis:6379/2
    volumes:
      - .:/app
      - static_volume:/app/staticfiles
    depends_on:
      - redis
      - db
    networks:
      - app-network
    restart: unless-stopped

  celery-beat:
    build: .
    command: celery -A myproject beat --loglevel=info --scheduler django_celery_beat.schedulers:DatabaseScheduler
    environment:
      - DJANGO_SETTINGS_MODULE=myproject.settings.production
      - CELERY_BROKER_URL=redis://redis:6379/1
    volumes:
      - .:/app
    depends_on:
      - redis
      - db
    networks:
      - app-network
    restart: unless-stopped

  flower:
    image: mher/flower:1.2.0
    command: celery flower --broker=redis://redis:6379/1 --address=0.0.0.0 --port=5555
    environment:
      - CELERY_BROKER_URL=redis://redis:6379/1
    ports:
      - "5555:5555"
    depends_on:
      - redis
    networks:
      - app-network
    restart: unless-stopped
```

#### Celery Health Checks
**Celery worker health monitoring:**
```python
# health_checks.py - Celery health checks
from celery import Celery
from django.http import JsonResponse
from django.views.decorators.http import require_GET

app = Celery('myproject')
app.config_from_object('django.conf:settings', namespace='CELERY')

@require_GET
def celery_health_check(request):
    """Check Celery worker and beat status."""
    try:
        # Check if Celery is reachable
        inspect = app.control.inspect()
        
        # Get active workers
        active_workers = inspect.active()
        if not active_workers:
            return JsonResponse({
                'status': 'error',
                'message': 'No active Celery workers found'
            }, status=503)
        
        # Check worker stats
        stats = inspect.stats()
        if not stats:
            return JsonResponse({
                'status': 'warning',
                'message': 'Unable to get Celery worker stats'
            }, status=200)
        
        # Check scheduled tasks (beat)
        scheduled = inspect.scheduled()
        
        return JsonResponse({
            'status': 'healthy',
            'workers': len(active_workers),
            'scheduled_tasks': len(scheduled) if scheduled else 0,
            'worker_stats': stats
        })
        
    except Exception as e:
        return JsonResponse({
            'status': 'error',
            'message': f'Celery health check failed: {str(e)}'
        }, status=503)
```

#### Celery Deployment Automation
**Celery-aware deployment script updates:**
```bash
# scripts/deploy.sh - Enhanced for Celery
#!/bin/bash

# ... existing deployment logic ...

# After Django deployment
log "Restarting Celery services..."
docker compose restart celery-worker celery-beat

# Wait for Celery to be ready
log "Waiting for Celery workers..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker compose exec -T celery-worker celery -A myproject inspect ping >/dev/null 2>&1; then
        log "Celery workers are ready!"
        break
    fi
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    error "Celery workers failed to start within 60 seconds"
    exit 1
fi

# Verify scheduled tasks
log "Checking Celery Beat scheduled tasks..."
scheduled_count=$(docker compose exec -T celery-beat celery -A myproject beat --print- schedule 2>/dev/null | wc -l)
if [ "$scheduled_count" -gt 0 ]; then
    log "Found $scheduled_count scheduled tasks"
else
    warning "No scheduled tasks found in Celery Beat"
fi
```

### Django Channels WebSocket Deployment

#### Channels ASGI Configuration
**Production Channels setup:**
```python
# asgi.py - Production ASGI configuration
import os
import django
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
from channels.security.websocket import AllowedHostsOriginValidator
from django.core.asgi import get_asgi_application
from django.urls import path
from myapp.consumers import MyConsumer

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'myproject.settings')
django.setup()

django_asgi_app = get_asgi_application()

# WebSocket URL patterns
websocket_urlpatterns = [
    path('ws/chat/<room_id>/', MyConsumer.as_asgi()),
    # Add more WebSocket routes here
]

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AllowedHostsOriginValidator(
        AuthMiddlewareStack(
            URLRouter(websocket_urlpatterns)
        )
    ),
})
```

#### Daphne Production Configuration
**Daphne server setup with Docker Compose:**
```yaml
# docker-compose.yml - Daphne service
version: '3.8'
services:
  daphne:
    build: .
    command: daphne -b 0.0.0.0 -p 8000 --access-log /var/log/daphne/access.log myproject.asgi:application
    environment:
      - DJANGO_SETTINGS_MODULE=myproject.settings.production
    volumes:
      - .:/app
      - static_volume:/app/staticfiles
      - /var/log/daphne:/var/log/daphne
    depends_on:
      - redis
      - db
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  web:
    build: .
    command: gunicorn myproject.wsgi:application --bind 0.0.0.0:8001 --workers 4 --threads 2
    environment:
      - DJANGO_SETTINGS_MODULE=myproject.settings.production
    volumes:
      - .:/app
      - static_volume:/app/staticfiles
    depends_on:
      - db
    networks:
      - app-network
    restart: unless-stopped
```

#### Nginx Configuration for Channels
**nginx.conf for Channels with Daphne:**
```nginx
# nginx.conf
upstream django {
    server web:8001;
}

upstream daphne {
    server daphne:8000;
}

server {
    listen 80;
    server_name example.com;
    
    # Static files
    location /static/ {
        alias /app/staticfiles/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Media files
    location /media/ {
        alias /app/media/;
        expires 30d;
        add_header Cache-Control "public";
    }
    
    # WebSocket connections
    location /ws/ {
        proxy_pass http://daphne;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
    
    # HTTP requests
    location / {
        proxy_pass http://django;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }
    
    # Health check
    location /health/ {
        proxy_pass http://daphne;
        access_log off;
    }
}
```

#### Channels Health Checks
**WebSocket connection health monitoring:**
```python
# health_checks.py - Channels health checks
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from myapp.consumers import MyConsumer
from django.contrib.auth import get_user_model
from asgiref.sync import sync_to_async

@sync_to_async
def check_websocket_health():
    """Check WebSocket connectivity."""
    try:
        User = get_user_model()
        user = User.objects.create_user('test', 'test@example.com', 'test')
        
        # Create test WebSocket connection
        communicator = WebsocketCommunicator(
            MyConsumer.as_asgi(),
            "/ws/test/",
            headers=[(b'cookie', f'sessionid={user.session.session_key}'.encode())]
        )
        
        connected, subprotocol = await communicator.connect()
        if not connected:
            return {
                'status': 'error',
                'message': 'WebSocket connection failed'
            }
        
        # Send test message
        await communicator.send_json_to({'type': 'ping'})
        
        # Receive response
        response = await communicator.receive_json_from()
        
        # Close connection
        await communicator.disconnect()
        
        return {
            'status': 'healthy',
            'message': 'WebSocket connections working',
            'response': response
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'WebSocket health check failed: {str(e)}'
        }
```

### Django CI/CD Integration

#### GitHub Actions for Django
**Django-specific CI/CD pipeline:**
```yaml
# .github/workflows/django-deploy.yml
name: Django Deploy

on:
  push:
    branches: [ deployment ]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'staging'
        type: choice
        options:
        - staging
        - production

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v4
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt

    - name: Run Django migrations
      run: |
        python manage.py migrate
      env:
        DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test

    - name: Run Django tests
      run: |
        python manage.py test --verbosity=2
      env:
        DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test

    - name: Run Django system checks
      run: |
        python manage.py check --deploy

  deploy:
    needs: test
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment || 'staging' }}

    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Setup SSH
      uses: webfactory/ssh-agent@v0.9.0
      with:
        ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

    - name: Check for Django migrations
      id: migrations
      run: |
        # Check if there are new migration files
        if git diff --name-only ${{ github.event.before }} ${{ github.sha }} | grep -q "migrations/"; then
          echo "has_migrations=true" >> $GITHUB_OUTPUT
        fi

    - name: Deploy Django application
      run: |
        # Copy deployment script
        scp scripts/django_deploy.sh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }}:/tmp/

        # Execute deployment
        ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} << 'EOF'
          cd ${{ secrets.DEPLOY_DIR }}
          chmod +x /tmp/django_deploy.sh
          /tmp/django_deploy.sh ${{ inputs.environment || 'staging' }}
          rm /tmp/django_deploy.sh
        EOF

    - name: Run post-deployment health checks
      run: |
        # Wait for deployment to complete
        sleep 30

        # Health check
        curl -f --max-time 30 ${{ secrets.HEALTH_CHECK_URL }}

        # Database migration check
        ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} \
          "cd ${{ secrets.DEPLOY_DIR }} && python manage.py showmigrations | grep -q '\[X\]' || exit 1"
```

### Django Performance Monitoring

#### Django-Specific Metrics
**Django application metrics:**
```python
# monitoring/metrics.py
from prometheus_client import Counter, Histogram, Gauge, Summary
import time
from django.db import connection
from django.core.signals import request_started, request_finished
from django.db.backends.signals import connection_created

# Request metrics
DJANGO_REQUEST_COUNT = Counter(
    'django_requests_total',
    'Total Django requests',
    ['method', 'endpoint', 'status_code']
)

DJANGO_REQUEST_LATENCY = Histogram(
    'django_request_duration_seconds',
    'Django request latency',
    ['method', 'endpoint']
)

# Database metrics
DJANGO_DB_CONNECTIONS = Gauge(
    'django_db_connections_active',
    'Active Django database connections'
)

DJANGO_DB_QUERIES = Counter(
    'django_db_queries_total',
    'Total Django database queries',
    ['table']
)

DJANGO_DB_QUERY_DURATION = Histogram(
    'django_db_query_duration_seconds',
    'Django database query duration'
)

# Cache metrics
DJANGO_CACHE_HITS = Counter(
    'django_cache_hits_total',
    'Django cache hits'
)

DJANGO_CACHE_MISSES = Counter(
    'django_cache_misses_total',
    'Django cache misses'
)

# Model metrics
DJANGO_MODEL_CREATED = Counter(
    'django_model_created_total',
    'Django model instances created',
    ['model']
)

DJANGO_MODEL_UPDATED = Counter(
    'django_model_updated_total',
    'Django model instances updated',
    ['model']
)

DJANGO_MODEL_DELETED = Counter(
    'django_model_deleted_total',
    'Django model instances deleted',
    ['model']
)

class DjangoMetricsMiddleware:
    """Middleware to collect Django-specific metrics."""

    def __init__(self, get_response):
        self.get_response = get_response

        # Connect signals
        request_started.connect(self.on_request_started)
        request_finished.connect(self.on_request_finished)
        connection_created.connect(self.on_connection_created)

    def __call__(self, request):
        start_time = time.time()

        # Track active connections
        initial_queries = len(connection.queries)

        response = self.get_response(request)

        # Record request metrics
        duration = time.time() - start_time
        DJANGO_REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.path,
            status_code=response.status_code
        ).inc()

        DJANGO_REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=request.path
        ).observe(duration)

        # Record database query metrics
        final_queries = len(connection.queries)
        queries_executed = final_queries - initial_queries

        if queries_executed > 0:
            # Get table names from queries (simplified)
            for query in connection.queries[initial_queries:]:
                # This is a simplified example - in practice you'd parse the SQL
                DJANGO_DB_QUERIES.labels(table='unknown').inc()
                DJANGO_DB_QUERY_DURATION.observe(float(query.get('time', 0)))

        return response

    def on_request_started(self, sender, **kwargs):
        DJANGO_DB_CONNECTIONS.inc()

    def on_request_finished(self, sender, **kwargs):
        DJANGO_DB_CONNECTIONS.dec()

    def on_connection_created(self, sender, connection, **kwargs):
        # Track connection pool metrics
        pass

# Model signal handlers for instance tracking
from django.db.models.signals import post_save, post_delete

def track_model_creation(sender, instance, created, **kwargs):
    if created:
        DJANGO_MODEL_CREATED.labels(model=sender._meta.label).inc()
    else:
        DJANGO_MODEL_UPDATED.labels(model=sender._meta.label).inc()

def track_model_deletion(sender, instance, **kwargs):
    DJANGO_MODEL_DELETED.labels(model=sender._meta.label).inc()

# Connect to all models
from django.apps import apps
for model in apps.get_models():
    post_save.connect(track_model_creation, sender=model)
    post_delete.connect(track_model_deletion, sender=model)
```

### Django Logging Configuration

#### Structured Django Logging
**Enhanced Django logging for production:**
```python
# settings/logging.py
import os
from django.conf import settings

# Custom log formatter for Django
class DjangoRequestFormatter(logging.Formatter):
    """Custom formatter that adds Django request context."""

    def format(self, record):
        # Add request information if available
        if hasattr(record, 'request'):
            request = record.request
            record.request_id = getattr(request, 'request_id', 'unknown')
            record.user_id = getattr(request.user, 'id', 'anonymous') if hasattr(request, 'user') else 'anonymous'
            record.method = request.method
            record.path = request.path
            record.ip = self.get_client_ip(request)

        return super().format(record)

    def get_client_ip(self, request):
        """Get client IP address."""
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            ip = x_forwarded_for.split(',')[0]
        else:
            ip = request.META.get('REMOTE_ADDR')
        return ip

# Production logging configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'django': {
            '()': 'settings.logging.DjangoRequestFormatter',
            'format': '{asctime} {levelname} {name} {request_id} {user_id} {method} {path} {ip} {message}',
            'style': '{',
        },
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(asctime)s %(name)s %(levelname)s %(request_id)s %(user_id)s %(method)s %(path)s %(ip)s %(message)s',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'django',
            'stream': sys.stdout,
        },
        'file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/django/app.log',
            'maxBytes': 100*1024*1024,  # 100MB
            'backupCount': 10,
            'formatter': 'json',
        },
        'django_file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/django/django.log',
            'maxBytes': 50*1024*1024,  # 50MB
            'backupCount': 5,
            'formatter': 'json',
        },
        'error_file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/django/error.log',
            'maxBytes': 20*1024*1024,  # 20MB
            'backupCount': 5,
            'formatter': 'json',
            'level': 'ERROR',
        },
    },
    'root': {
        'handlers': ['console', 'file'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['django_file', 'error_file'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.request': {
            'handlers': ['error_file'],
            'level': 'ERROR',
            'propagate': False,
        },
        'django.security': {
            'handlers': ['error_file'],
            'level': 'ERROR',
            'propagate': False,
        },
        'myapp': {
            'handlers': ['file', 'error_file'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

# Add request ID middleware
class RequestIDMiddleware:
    """Middleware to add unique request ID to each request."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        import uuid
        request.request_id = str(uuid.uuid4())[:8]

        # Add request ID to logging context
        logger = logging.getLogger()
        for handler in logger.handlers:
            if hasattr(handler, 'setFormatter'):
                # Add request to logging record
                pass

        response = self.get_response(request)
        response['X-Request-ID'] = request.request_id
        return response
```

## Why It's Generic
These Django deployment patterns build on the generic deployment skill but add Django-specific optimizations:

- **Migration Safety**: Automatic detection and handling of Django migrations
- **Static File Management**: Django-specific static file collection and serving
- **Settings Management**: Environment-specific Django configuration patterns
- **ORM Integration**: Database connection pooling and query optimization
- **Django Ecosystem**: Integration with Celery, Channels, and other Django tools
- **Multi-Tenant Support**: Schema-per-tenant deployment considerations

## Example Use Cases
**Standard Django Application:**
- Single-tenant Django app with PostgreSQL, Redis, and Celery
- Static file serving through nginx with Django admin
- Automated deployment with health checks and rollback

**Multi-Tenant Django SaaS:**
- django-tenants based multi-tenant application
- Schema isolation with tenant-aware health checks
- Per-tenant resource monitoring and alerting

**Real-Time Django Application:**
- Django Channels for WebSocket support
- Daphne/ASGI server configuration
- Background task processing with Celery

**High-Traffic Django Application:**
- Multiple application servers with load balancing
- Database connection pooling and query optimization
- Comprehensive monitoring and alerting setup

## References
- [Generic Deployment Patterns](../deployment/SKILL.md) - Core deployment principles
- [Django Deployment Checklist](https://docs.djangoproject.com/en/stable/howto/deployment/checklist/) - Django official deployment guide
- [Django Settings](https://docs.djangoproject.com/en/stable/topics/settings/) - Django configuration
- [Django Logging](https://docs.djangoproject.com/en/stable/topics/logging/) - Django logging configuration
- [Django Tenants](https://django-tenants.readthedocs.io/) - Multi-tenant Django applications