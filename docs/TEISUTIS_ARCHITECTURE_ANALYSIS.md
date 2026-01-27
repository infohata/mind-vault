# Teisutis Django Architecture - Comprehensive Analysis

**Purpose**: Complete architectural analysis of Teisutis Django project for pattern extraction  
**Date**: 2026-01-26  
**Status**: In Progress  
**Applies To**: mind-vault (pattern extraction)

---

## Executive Summary

Teisutis is a **multi-tenant, async-first Django application** with Celery background jobs, WebSocket real-time features (via Django Channels), and AI integration. The architecture reveals patterns across 9 major areas:

1. **Core Django structure** - Project layout, ASGI, settings organization
2. **Model patterns** - BaseModel abstractions, tenant isolation
3. **DRF patterns** - Serializers, viewsets, permissions
4. **Async/WebSocket** - Channels consumers, async context management
5. **Multi-tenancy** - Schema-per-tenant isolation, context propagation
6. **Celery integration** - Task definitions, async patterns
7. **Database patterns** - Query optimization, N+1 prevention, Elasticsearch
8. **Middleware/Context** - Tenant resolution, request context
9. **Abstractions & DRY** - Mixins, base classes, utilities

---

## 1. CORE DJANGO STRUCTURE

### Project Layout
```
web/
├── teisutis/                 # Project package (django config)
│   ├── settings.py          # Django settings with env configuration
│   ├── urls.py              # Root URL dispatcher
│   ├── asgi.py              # ASGI entry point (Daphne/Channels)
│   ├── wsgi.py              # WSGI entry point (legacy HTTP)
│   ├── celery.py            # Celery configuration
│   └── routing.py           # Channels routing (WebSocket endpoints)
├── teisutis_auth/           # Authentication app
│   ├── models.py            # User, Tenant, Permission models
│   ├── middleware.py        # Tenant context middleware
│   ├── permissions.py       # DRF permission classes
│   ├── serializers.py       # DRF serializers for auth
│   └── urls.py
├── teisutis_core/           # Core business logic
│   ├── models.py            # BaseModel abstractions
│   ├── views.py             # DRF viewsets
│   └── serializers.py
├── teisutis_kb/             # Knowledge base app
│   ├── models.py            # Article, Category models
│   └── serializers.py
├── teisutis_ai/             # AI/ML features
│   ├── consumers.py         # WebSocket consumers (async)
│   ├── tasks.py             # Celery tasks
│   ├── ai_service.py        # AI service abstraction
│   └── semantic_search.py   # Elasticsearch integration
├── manage.py                # Django management command entry
└── tests/                   # Test suite
```

### ASGI Configuration (Async-First)
```python
# teisutis/asgi.py - Daphne handles both HTTP and WebSocket
from daphne.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'teisutis.settings')
django.setup()

application = ProtocolTypeRouter({
    'http': django_asgi_app,  # HTTP via Django
    'websocket': AllowedHostsOriginValidator(
        AuthMiddlewareStack(
            URLRouter([...])  # WebSocket routing via Channels
        )
    ),
})
```

**Pattern**: Daphne handles BOTH HTTP and WebSocket (pragmatic choice vs. Gunicorn+Daphne split)

### Settings Organization
```python
# teisutis/settings.py structure
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Core Django settings
INSTALLED_APPS = [
    'daphne',                    # Async ASGI server (must be first)
    'channels',                  # WebSocket support
    'django_tenants',            # Multi-tenancy
    'rest_framework',            # DRF
    'teisutis_auth',
    'teisutis_core',
    'teisutis_kb',
    'teisutis_ai',
]

MIDDLEWARE = [
    'django_tenants.middleware.TenantMiddleware',  # CRITICAL: Must be early
    'django.middleware.security.SecurityMiddleware',
    'teisutis_auth.middleware.TenantContextMiddleware',  # Custom tenant context
]

# Environment-driven configuration
DATABASES = {
    'default': {
        'ENGINE': 'django_tenants.postgresql_backend',
        'NAME': os.getenv('DB_NAME', 'teisutis'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD'),
        'HOST': os.getenv('DB_HOST', 'db'),
        'PORT': os.getenv('DB_PORT', '5432'),
    }
}

# Feature gates via environment
ENABLE_SEMANTIC_SEARCH = os.getenv('ENABLE_SEMANTIC_SEARCH', 'true').lower() == 'true'
MAX_PROMPT_LENGTH = int(os.getenv('MAX_PROMPT_LENGTH', '50000'))
API_TIMEOUT = int(os.getenv('API_TIMEOUT', '30'))

# Channels/async configuration
ASGI_APPLICATION = 'teisutis.asgi.application'
CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [os.getenv('REDIS_URL', 'redis://redis:6379')],
        },
    },
}

# Celery configuration
CELERY_BROKER_URL = os.getenv('CELERY_BROKER_URL', 'redis://redis:6379')
CELERY_RESULT_BACKEND = os.getenv('CELERY_RESULT_BACKEND', 'redis://redis:6379')
CELERY_TASK_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']
```

**Pattern**: Environment variables with sensible defaults, feature gates for optional functionality

---

## 2. MODEL PATTERNS

### Base Model Abstraction (DRY)
```python
# teisutis_core/models.py
from django.db import models
from django_tenants.models import TenantModel

class BaseModel(models.Model):
    """Abstract base for all Teisutis models"""
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_deleted = models.BooleanField(default=False)
    
    class Meta:
        abstract = True
    
    def soft_delete(self):
        """Soft delete pattern for audit trail"""
        self.is_deleted = True
        self.save()

class TenantBaseModel(TenantModel, BaseModel):
    """Multi-tenant aware base model"""
    class Meta:
        abstract = True
```

**MULTI-TENANT INJECTION**: TenantModel from django-tenants automatically adds `tenant` FK

### Multi-Tenant Model Examples
```python
# teisutis_auth/models.py - TENANT-SCOPED MODELS
from django_tenants.models import TenantModel

class Tenant(TenantModel):
    """Represents a tenant (customer organization)"""
    name = models.CharField(max_length=255)
    schema_name = models.CharField(max_length=63, unique=True)
    domain_url = models.CharField(max_length=255, unique=True)
    is_active = models.BooleanField(default=True)

class User(TenantBaseModel):
    """User model - scoped to tenant schema"""
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE)
    username = models.CharField(max_length=255)
    email = models.EmailField()

# teisutis_kb/models.py - Knowledge Base TENANT-SCOPED
class Article(TenantBaseModel):
    """KB article - isolated per tenant"""
    title = models.CharField(max_length=500)
    content = models.TextField()
    author = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    category = models.ForeignKey('Category', on_delete=models.PROTECT)

# teisutis_ai/models.py - AI Features TENANT-SCOPED
class AIConversation(TenantBaseModel):
    """Multi-turn conversation with AI - tenant isolated"""
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    title = models.CharField(max_length=500)
    started_at = models.DateTimeField(auto_now_add=True)
```

**MULTI-TENANT INJECTION POINTS**:
- Every model using TenantBaseModel is automatically scoped to tenant schema
- Foreign keys between models work within schema (no cross-tenant access)
- Queries automatically filtered to current tenant context

---

## 3. VIEWS & SERIALIZERS (DRF)

### DRF Permissions (Multi-Tenant)
```python
# teisutis_kb/permissions.py
from rest_framework import permissions

class IsTenantUser(permissions.BasePermission):
    """MULTI-TENANT: User must belong to the tenant's schema"""
    def has_permission(self, request, view):
        return request.user.is_authenticated and \
               request.user.tenant_id == request.tenant.id
    
    def has_object_permission(self, request, view, obj):
        return obj.tenant_id == request.tenant.id

class IsArticleAuthor(permissions.BasePermission):
    """Permission to edit article only if author"""
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user

class IsKBEditor(permissions.BasePermission):
    """RBAC: User has editor role in this tenant"""
    def has_permission(self, request, view):
        return hasattr(request.user, 'userprofile') and \
               request.user.userprofile.role in ['admin', 'editor']
```

### DRF Serializers
```python
# teisutis_kb/serializers.py
from rest_framework import serializers
from teisutis_kb.models import Article, Category

class ArticleDetailSerializer(serializers.ModelSerializer):
    """Detail view - full content"""
    author_name = serializers.CharField(
        source='author.userprofile.full_name', 
        read_only=True
    )
    can_edit = serializers.SerializerMethodField()
    
    def get_can_edit(self, obj):
        # MULTI-TENANT: Check request tenant context
        request = self.context.get('request')
        return obj.author == request.user and \
               request.tenant_id == obj.tenant_id
    
    class Meta:
        model = Article
        fields = ['id', 'title', 'content', 'author_name', 'can_edit', 'created_at']
    
    def create(self, validated_data):
        # MULTI-TENANT INJECTION: Auto-set tenant and author
        request = self.context['request']
        validated_data['tenant'] = request.tenant
        validated_data['author'] = request.user
        return super().create(validated_data)
```

### ViewSets (Multi-Tenant + Permissions)
```python
# teisutis_kb/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from teisutis_kb.models import Article
from teisutis_kb.serializers import ArticleListSerializer, ArticleDetailSerializer
from teisutis_kb.permissions import IsTenantUser, IsArticleAuthor, IsKBEditor

class ArticleViewSet(viewsets.ModelViewSet):
    """CRUD operations on articles with multi-tenant isolation"""
    permission_classes = [IsAuthenticated, IsTenantUser]
    
    def get_queryset(self):
        # MULTI-TENANT INJECTION: Queries automatically scoped by django-tenants
        return Article.objects.filter(
            is_deleted=False
        ).select_related('author', 'category')
    
    def get_serializer_class(self):
        if self.action == 'retrieve':
            return ArticleDetailSerializer
        return ArticleListSerializer
    
    def get_permissions(self):
        if self.action in ['create']:
            return [IsAuthenticated(), IsTenantUser(), IsKBEditor()]
        if self.action in ['update', 'partial_update', 'destroy']:
            return [IsAuthenticated(), IsTenantUser(), IsArticleAuthor()]
        return super().get_permissions()
    
    def perform_create(self, serializer):
        # Signals will fire here
        # CELERY INJECTION: Signal triggers elasticsearch indexing task
        serializer.save()
```

---

## 4. MIDDLEWARE & CONTEXT (Multi-Tenant Critical)

### Tenant Resolution Middleware
```python
# teisutis_auth/middleware.py - CRITICAL FOR MULTI-TENANCY
from django_tenants.middleware import TenantMiddleware
from django.http import JsonResponse
from teisutis_auth.models import Tenant

class TenantContextMiddleware(TenantMiddleware):
    """
    MULTI-TENANT: Resolve tenant from request and set in scope
    Must run BEFORE any permission checks
    """
    
    def get_tenant(self, request, exception):
        """
        Resolve tenant from:
        1. X-Tenant-ID header (API requests)
        2. Domain (tenant.domain_url) 
        3. Subdomain (tenant.schema_name)
        """
        # Try from header first (API clients)
        tenant_id = request.META.get('HTTP_X_TENANT_ID')
        if tenant_id:
            try:
                return Tenant.objects.get(id=tenant_id, is_active=True)
            except Tenant.DoesNotExist:
                pass
        
        # Try from domain (web requests)
        host = request.get_host().split(':')[0]
        try:
            tenant = Tenant.objects.get(domain_url=host, is_active=True)
            return tenant
        except Tenant.DoesNotExist:
            pass
        
        return None
    
    def __call__(self, request):
        tenant = self.get_tenant(request, None)
        
        if not tenant:
            return JsonResponse({'error': 'Tenant not found'}, status=404)
        
        # MULTI-TENANT INJECTION: Store in request scope
        request.tenant = tenant
        request.tenant_id = tenant.id
        
        response = self.get_response(request)
        return response
```

**MULTI-TENANT CRITICAL**: This middleware:
- Resolves tenant from domain or header
- Switches database schema for all ORM queries
- Sets request.tenant for downstream code
- Prevents cross-tenant data leakage

---

## 5. CELERY INTEGRATION: ALL INJECTION POINTS

### Celery Configuration
```python
# teisutis/celery.py
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'teisutis.settings')

app = Celery('teisutis')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

# In settings.py:
CELERY_BROKER_URL = 'redis://redis:6379'
CELERY_RESULT_BACKEND = 'redis://redis:6379'
CELERY_TASK_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_TIME_LIMIT = 30 * 60  # 30 minutes
```

### Task Definition Pattern
```python
# teisutis_ai/tasks.py - CELERY INJECTION POINTS
from celery import shared_task
from django_tenants.utils import tenant_context
from teisutis_auth.models import Tenant
from teisutis_ai.semantic_search import index_article

@shared_task(bind=True)
def index_article_in_elasticsearch(self, article_id, tenant_id):
    """
    CELERY INJECTION: Async task for indexing article
    MULTI-TENANT INJECTION: Must receive tenant_id, set context
    """
    try:
        # CRITICAL: Set tenant context in async task
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            article = Article.objects.get(id=article_id)
            index_article(article)
    
    except Article.DoesNotExist:
        self.logger.warning(f"Article {article_id} not found")
    except Exception as exc:
        self.retry(exc=exc, countdown=60)

@shared_task
def generate_ai_response(conversation_id, message_content):
    """
    CELERY INJECTION: Long-running AI generation
    MULTI-TENANT: Gets tenant from conversation model
    """
    from teisutis_ai.models import AIConversation, Message
    
    conversation = AIConversation.objects.get(id=conversation_id)
    tenant = conversation.tenant
    
    with tenant_context(tenant):
        # AI service call
        response = generate_response(conversation, message_content)
        
        # Save response message
        Message.objects.create(
            conversation=conversation,
            role='assistant',
            content=response
        )
        
        # Send to WebSocket (via Channels group)
        from channels.layers import get_channel_layer
        import asyncio
        
        channel_layer = get_channel_layer()
        asyncio.run(
            channel_layer.group_send(
                f'conversation_{conversation_id}',
                {
                    'type': 'ai_response',
                    'content': response,
                    'timestamp': timezone.now().isoformat()
                }
            )
        )
```

### Signal-Based Celery Calls
```python
# teisutis_kb/signals.py - Triggers Celery tasks
from django.db.models.signals import post_save
from django.dispatch import receiver
from teisutis_kb.models import Article
from teisutis_ai.tasks import index_article_in_elasticsearch

@receiver(post_save, sender=Article)
def on_article_saved(sender, instance, created, **kwargs):
    """
    CELERY INJECTION: Async indexing when article saved
    MULTI-TENANT INJECTION: Pass tenant_id to task
    """
    index_article_in_elasticsearch.delay(
        article_id=instance.id,
        tenant_id=instance.tenant_id  # CRITICAL: Explicit tenant
    )
```

**CELERY CRITICAL**: Every task must:
1. Accept tenant_id parameter (or get from model)
2. Call `with tenant_context(tenant):` before queries
3. Never assume request context exists

---

## 6. ASYNC/WEBSOCKET: CRITICAL PATTERNS

### WebSocket Consumers (Channels)
```python
# teisutis_ai/consumers.py - ASYNC + MULTI-TENANT
from channels.generic.websocket import AsyncWebsocketConsumer
from django_tenants.utils import tenant_context
from database_sync_to_async import database_sync_to_async

class ChatConsumer(AsyncWebsocketConsumer):
    """
    MULTI-TENANT INJECTION: Get tenant from scope
    ASYNC INJECTION: Mix sync DB with async WebSocket
    CELERY INJECTION: Trigger background tasks
    """
    
    async def connect(self):
        # Get tenant from WebSocket scope
        self.tenant_id = self.scope.get('tenant_id')
        self.tenant = None
        
        if not self.tenant_id:
            await self.close(code=4003)  # Forbidden
            return
        
        # Get tenant from DB
        self.tenant = await self.get_tenant()
        
        if not self.tenant:
            await self.close(code=4004)  # Not found
            return
        
        # Get user
        self.user = self.scope.get('user')
        if not self.user or not self.user.is_authenticated:
            await self.close(code=4001)  # Unauthorized
            return
        
        # Get conversation from URL
        self.conversation_id = self.scope['url_route']['kwargs'].get('conversation_id')
        self.conversation = await self.get_conversation()
        
        if not self.conversation:
            await self.close(code=4004)
            return
        
        # Join group for broadcasting
        self.group_name = f"conversation_{self.conversation_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        
        await self.accept()
        await self.send_json({'status': 'connected'})
    
    @database_sync_to_async
    def get_tenant(self):
        """ASYNC INJECTION: Fetch tenant in async context"""
        from teisutis_auth.models import Tenant
        try:
            return Tenant.objects.get(id=self.tenant_id, is_active=True)
        except Tenant.DoesNotExist:
            return None
    
    @database_sync_to_async
    def get_conversation(self):
        """ASYNC + MULTI-TENANT INJECTION"""
        from teisutis_ai.models import AIConversation
        try:
            with tenant_context(self.tenant):
                return AIConversation.objects.get(
                    id=self.conversation_id,
                    user=self.user
                )
        except AIConversation.DoesNotExist:
            return None
    
    async def receive(self, text_data):
        """Receive message from WebSocket"""
        try:
            data = json.loads(text_data)
            message_content = data.get('message', '')
            
            if not message_content:
                await self.send_json({'error': 'Empty message'})
                return
            
            # Save user message
            await self.save_message(message_content, role='user')
            
            # Trigger async AI response (Celery)
            # CELERY INJECTION: Queue task without blocking
            from teisutis_ai.tasks import generate_ai_response
            generate_ai_response.delay(
                conversation_id=self.conversation_id,
                message_content=message_content
            )
            
            await self.send_json({'status': 'message_queued'})
        
        except json.JSONDecodeError:
            await self.send_json({'error': 'Invalid JSON'})
        except (KeyError, AttributeError, TypeError) as e:
            # Programming error - fail fast
            logger.error(f"Programming error: {type(e).__name__}: {e}", exc_info=True)
            await self.close(code=4000)
        except Exception as e:
            logger.error(f"Unexpected error: {type(e).__name__}: {e}", exc_info=True)
            await self.send_json({'error': 'Internal server error'})
    
    @database_sync_to_async
    def save_message(self, content, role):
        """ASYNC INJECTION: DB call in async context"""
        from teisutis_ai.models import Message
        with tenant_context(self.tenant):
            return Message.objects.create(
                conversation=self.conversation,
                role=role,
                content=content
            )
    
    async def ai_response(self, event):
        """Receive message from group (sent by Celery task)"""
        await self.send_json({
            'type': 'ai_response',
            'content': event['content'],
            'timestamp': event['timestamp']
        })
    
    async def disconnect(self, code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)
```

### Routing (WebSocket Endpoints)
```python
# teisutis/routing.py - WebSocket URL routing
from django.urls import re_path
from teisutis_ai.consumers import ChatConsumer, STTConsumer

websocket_urlpatterns = [
    re_path(
        r'ws/chat/conversations/(?P<conversation_id>\d+)/$',
        ChatConsumer.as_asgi()
    ),
    re_path(r'ws/stt/$', STTConsumer.as_asgi()),
]
```

---

## 7. DATABASE PATTERNS

### Query Optimization
```python
# PREVENT N+1 QUERIES

# GOOD - Prefetch related objects
articles = Article.objects.prefetch_related(
    'author',
    'author__userprofile',
    'category'
).filter(is_deleted=False)

# GOOD - Select specific fields
articles = Article.objects.only(
    'id', 'title', 'created_at'
).filter(is_deleted=False)

# GOOD - Select from related tables
articles = Article.objects.select_related(
    'author',
    'category'
).filter(is_deleted=False)
```

### Elasticsearch Integration (Semantic Search)
```python
# teisutis_ai/semantic_search.py - MULTI-TENANT AWARE
from elasticsearch import Elasticsearch
from django.conf import settings

es = Elasticsearch([settings.ELASTICSEARCH_HOST])

def index_article(article, tenant_id=None):
    """
    MULTI-TENANT: Each tenant has separate ES index
    PERFORMANCE: Bulk indexing for efficiency
    """
    if tenant_id is None:
        tenant_id = article.tenant_id
    
    index_name = f"articles-{tenant_id}"  # Per-tenant index
    
    doc = {
        'id': article.id,
        'title': article.title,
        'content': article.content,
        'author': article.author.userprofile.full_name,
        'created_at': article.created_at.isoformat(),
    }
    
    es.index(index=index_name, id=article.id, document=doc)

def search_articles(query, tenant_id):
    """
    MULTI-TENANT: Query only tenant's index
    PERFORMANCE: ~3 second timeout warning
    """
    index_name = f"articles-{tenant_id}"
    
    try:
        results = es.search(
            index=index_name,
            timeout="3s",
            body={
                'query': {
                    'multi_match': {
                        'query': query,
                        'fields': ['title^2', 'content', 'author']
                    }
                }
            }
        )
        
        return [hit['_source'] for hit in results['hits']['hits']]
    
    except Exception as e:
        logger.warning(f"Elasticsearch failed: {e}, falling back to DB")
        # Fallback to database full-text search
        return Article.objects.filter(
            Q(title__icontains=query) | Q(content__icontains=query)
        ).values('id', 'title', 'content')
```

---

## 8. ABSTRACTIONS & DRY PATTERNS

### Base Mixins
```python
# teisutis_auth/mixins.py - Reusable functionality

class TenantFilterMixin:
    """Auto-filter queryset to current tenant"""
    def get_queryset(self):
        qs = super().get_queryset()
        return qs

class TenantCreateMixin:
    """Auto-set tenant on create"""
    def perform_create(self, serializer):
        serializer.save(tenant=self.request.tenant)

class SoftDeleteMixin:
    """Override destroy to soft delete instead of hard delete"""
    def perform_destroy(self, instance):
        instance.soft_delete()

class AuditMixin:
    """Track who created/updated models"""
    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)
    
    def perform_update(self, serializer):
        serializer.save(updated_by=self.request.user)
```

### Base ViewSets
```python
# teisutis_core/views.py - DRY view patterns
from rest_framework.viewsets import ModelViewSet
from rest_framework.permissions import IsAuthenticated
from teisutis_auth.permissions import IsTenantUser

class TenantModelViewSet(
    TenantFilterMixin, TenantCreateMixin, SoftDeleteMixin, ModelViewSet
):
    """
    Base viewset for multi-tenant models
    Automatically:
    - Filters queryset by tenant
    - Sets tenant on create
    - Soft deletes on destroy
    """
    permission_classes = [IsAuthenticated, IsTenantUser]
    
    def get_queryset(self):
        qs = super().get_queryset()
        return qs.filter(is_deleted=False)
```

### Performance Monitoring
```python
# teisutis_ai/performance_metrics.py - PERFORMANCE INJECTION

import logging
import time
from functools import wraps

logger = logging.getLogger(__name__)

class PerformanceMonitor:
    """PERFORMANCE INJECTION: Track slow operations"""
    
    THRESHOLDS = {
        'elasticsearch_search': 3,
        'elasticsearch_index': 5,
        'api_call': 10,
        'db_query': 1,
    }
    
    @staticmethod
    def log_operation(operation_name, duration, **metadata):
        """Log operation timing"""
        threshold = PerformanceMonitor.THRESHOLDS.get(operation_name, 10)
        
        if duration > threshold:
            logger.warning(
                f"Slow operation: {operation_name} took {duration:.2f}s",
                extra={'operation': operation_name, 'duration': duration, **metadata}
            )

def monitor_performance(operation_name):
    """Decorator for monitoring function performance"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start = time.time()
            try:
                result = func(*args, **kwargs)
                return result
            finally:
                duration = time.time() - start
                PerformanceMonitor.log_operation(operation_name, duration)
        return wrapper
    return decorator
```

---

## SUMMARY TABLE: ALL INJECTION POINTS

| Category | Location | Type | Details |
|----------|----------|------|---------|
| **Multi-Tenant** | models.py | TenantModel | Every model inherits - schema scoped |
| | middleware.py | TenantContextMiddleware | Resolves tenant from domain/header |
| | permissions.py | IsTenantUser | Checks request.tenant matches object.tenant |
| | serializers.py | create() | Auto-sets tenant_id |
| | views.py | get_queryset() | Auto-filters to tenant schema |
| | consumers.py | WebSocket scope | Gets tenant_id from scope |
| | tasks.py | Celery | Receives tenant_id parameter |
| **Celery** | signals.py | post_save | Triggers indexing task |
| | tasks.py | @shared_task | Defines async jobs |
| | settings.py | CELERY_BEAT_SCHEDULE | Scheduled tasks |
| | consumers.py | receive() | Queues generate_ai_response task |
| | tasks.py | generate_ai_response | Publishes to Channels group |
| **Async** | asgi.py | ProtocolTypeRouter | HTTP + WebSocket handling |
| | consumers.py | AsyncWebsocketConsumer | WebSocket connection handling |
| | consumers.py | @database_sync_to_async | DB calls in async context |
| | routing.py | websocket_urlpatterns | WebSocket URL routing |
| | consumers.py | channel_layer.group_send | Channels group messaging |
| **Performance** | semantic_search.py | Elasticsearch | Timeout handling, fallback |
| | performance_metrics.py | PerformanceMonitor | Slow operation logging |
| | models.py | prefetch_related | N+1 prevention |
| **DRY** | mixins.py | TenantFilterMixin | Auto-filter queryset |
| | mixins.py | TenantCreateMixin | Auto-set tenant on create |
| | views.py | TenantModelViewSet | Combines all mixins |

---

## CRITICAL WARNINGS

1. **Tenant Context MUST be set in async tasks**
   ```python
   # WRONG - Goes to public schema!
   articles = Article.objects.all()
   
   # RIGHT - Tenant schema
   with tenant_context(tenant):
       articles = Article.objects.all()
   ```

2. **Never assume request context in Celery**
   - Pass tenant_id explicitly to tasks
   - Set context inside task function

3. **WebSocket connections need tenant auth**
   - Verify tenant_id in scope
   - Check user belongs to tenant
   - Close with appropriate code on auth failure

4. **Elasticsearch indexes are per-tenant**
   - Use tenant_id in index name
   - Implement timeout + fallback for reliability

5. **Soft deletes affect queries**
   - Always filter: `.filter(is_deleted=False)`
   - Consider queryset managers for DRY

---

## CONFIGURATION APPROACH

### Environment Variables
```bash
# Core Django
DEBUG=False
SECRET_KEY=...
ALLOWED_HOSTS=teisutis.com

# Database
DB_ENGINE=django_tenants.postgresql_backend
DB_NAME=teisutis
DB_USER=postgres
DB_PASSWORD=...
DB_HOST=db

# Redis (Channels + Celery)
REDIS_URL=redis://redis:6379

# Celery
CELERY_BROKER_URL=redis://redis:6379
CELERY_RESULT_BACKEND=redis://redis:6379

# AI Services
OPENAI_API_KEY=...
ELASTICSEARCH_HOST=http://elasticsearch:9200

# Feature Flags
ENABLE_SEMANTIC_SEARCH=true
MAX_PROMPT_LENGTH=50000
API_TIMEOUT=30
```

---

**Last Updated**: 2026-01-26  
**Analysis Status**: Complete architecture map with all injection points identified  
**Next Phase**: Extract generic SKILL.md files from this analysis

