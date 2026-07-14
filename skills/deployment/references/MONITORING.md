# Monitoring Integration

> **Part of**: [Deployment Skill](../SKILL.md)  
> **Last Updated**: 2026-01-28

## Overview
Comprehensive production monitoring patterns extending the core [deployment skill](../SKILL.md), focusing on health checks, metrics collection, alerting, and observability. Covers application-level monitoring, infrastructure metrics, database performance, and automated alerting with notification integrations.

## When to Use
Any production web application requiring:
- Real-time health monitoring and alerting
- Performance metrics and resource usage tracking
- Automated incident response and notifications
- Historical data analysis and trend identification
- Compliance with uptime and performance SLAs

## Pattern

### Application Health Monitoring

#### Health Check Endpoints
**Framework-agnostic health endpoints:**
```python
# Django - views.py
from django.http import JsonResponse
from django.db import connection
import redis

def health_check(request):
    health_status = {
        'status': 'healthy',
        'checks': {
            'database': check_database(),
            'redis': check_redis(),
            'external_api': check_external_api()
        },
        'timestamp': timezone.now().isoformat()
    }

    # Return 503 if any check fails
    if any(not check['healthy'] for check in health_status['checks'].values()):
        health_status['status'] = 'unhealthy'
        return JsonResponse(health_status, status=503)

    return JsonResponse(health_status)

def check_database():
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return {'healthy': True, 'response_time': 0.1}
    except Exception as e:
        return {'healthy': False, 'error': str(e)}

def check_redis():
    try:
        r = redis.Redis(host='redis', port=6379, db=0)
        r.ping()
        return {'healthy': True, 'response_time': 0.05}
    except Exception as e:
        return {'healthy': False, 'error': str(e)}
```

```javascript
// Express.js - routes/health.js
const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const redis = require('redis');

router.get('/health', async (req, res) => {
  const healthStatus = {
    status: 'healthy',
    checks: {
      database: await checkMongoDB(),
      redis: await checkRedis(),
      external_api: await checkExternalAPI()
    },
    timestamp: new Date().toISOString()
  };

  const isHealthy = Object.values(healthStatus.checks).every(check => check.healthy);
  healthStatus.status = isHealthy ? 'healthy' : 'unhealthy';

  res.status(isHealthy ? 200 : 503).json(healthStatus);
});

async function checkMongoDB() {
  try {
    await mongoose.connection.db.admin().ping();
    return { healthy: true, response_time: 0.1 };
  } catch (error) {
    return { healthy: false, error: error.message };
  }
}

async function checkRedis() {
  return new Promise((resolve) => {
    const client = redis.createClient();
    client.on('error', (err) => resolve({ healthy: false, error: err.message }));
    client.ping((err, result) => {
      client.quit();
      if (err) resolve({ healthy: false, error: err.message });
      else resolve({ healthy: true, response_time: 0.05 });
    });
  });
}
```

#### Nginx Health Check Configuration
```nginx
# nginx.conf
upstream app_backend {
    server web:8000;
    server web:8001 backup;

    # Health checks every 10 seconds
    health_check interval=10 fails=3 passes=2;
}

server {
    listen 80;
    server_name example.com;

    location /health {
        # Proxy to application health endpoint
        proxy_pass http://app_backend/health;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;

        # Return 503 if upstream fails
        health_check;
    }

    location / {
        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Scheduler Liveness and Service-Inventory Checks

#### Schedulers must be first-class services

A background scheduler (Celery beat, a cron-runner sidecar, a queue dispatcher) started **manually inside another service's container** dies silently on the next container recreation — and scheduled jobs then lie dormant for months with zero errors, zero alerts, and a green-looking stack. A production audit found a schedule dead since a routine redeploy ~3 months earlier; nothing surfaced it because no process *owned* the scheduler's liveness.

The fix is structural, not monitoring: run the scheduler as its **own compose service** (own `restart: unless-stopped`, own log stream), so:

- `docker compose ps` answers "is the scheduler alive" directly;
- a recreation of the worker/web service cannot take the scheduler down with it;
- the health-inventory check below covers it for free.

Anti-pattern signature to grep for in runbooks/session notes: "started beat manually inside the celery container", `docker compose exec <svc> <scheduler> &`.

#### Inventory-based stack verification (don't count containers)

Health checks that assert a container *count* (`docker compose ps | wc -l` vs an expected number) break every time profiles or new services change the denominator — and silently pass when one expected service is missing but an optional one is up. Enumerate **by name** instead, using the compose file itself as the profile-aware expected set:

```make
health:
	@ok=1; \
	for svc in $$(docker compose config --services); do \
		st=$$(docker compose ps --format '{{.Status}}' $$svc 2>/dev/null | head -1); \
		if [ -z "$$st" ]; then echo "✗ $$svc: NOT RUNNING"; ok=0; \
		elif echo "$$st" | grep -qiE "unhealthy|restarting|exited|dead|created|paused"; then \
			echo "✗ $$svc: $$st"; ok=0; \
		else echo "✓ $$svc: $$st"; fi; \
	done; \
	if [ $$ok -eq 1 ]; then echo "health: all services OK"; else echo "health: FAILED"; exit 1; fi
```

`docker compose config --services` respects active profiles, so dev/e2e-only services don't false-fail a production stack. Non-zero exit on any missing/unhealthy service makes it CI- and deploy-script-safe. Wire it into the deploy runbook's verify step as the first check, before app-level health URLs.

### Infrastructure Monitoring

#### Docker Container Metrics
**Container resource monitoring:**
```bash
# Monitor container CPU/memory usage
docker stats --no-stream

# Container health status
docker ps --filter "health=healthy"
docker ps --filter "health=unhealthy"

# Container logs monitoring
docker compose logs -f --tail=100 web
docker compose logs -f --tail=100 worker
```

#### System Resource Monitoring
**Server resource monitoring:**
```bash
# CPU usage
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'

# Memory usage
free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }'

# Disk usage
df -h | awk '$NF=="/"{printf "%s", $5}'

# Network I/O
cat /proc/net/dev | grep eth0 | awk '{print "RX: " $2/1024/1024 "MB TX: " $10/1024/1024 "MB"}'
```

### Metrics Collection

#### Prometheus Configuration
**Application metrics with Prometheus client:**
```python
# Django - monitoring/metrics.py
from prometheus_client import Counter, Histogram, Gauge
import time

# Request metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency', ['method', 'endpoint'])
ACTIVE_CONNECTIONS = Gauge('active_connections', 'Number of active connections')

# Database metrics
DB_CONNECTIONS = Gauge('db_connections_active', 'Active database connections')
DB_QUERY_DURATION = Histogram('db_query_duration_seconds', 'Database query duration')

class MetricsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start_time = time.time()

        ACTIVE_CONNECTIONS.inc()

        try:
            response = self.get_response(request)

            REQUEST_COUNT.labels(
                method=request.method,
                endpoint=request.path,
                status=response.status_code
            ).inc()

            REQUEST_LATENCY.labels(
                method=request.method,
                endpoint=request.path
            ).observe(time.time() - start_time)

            return response
        finally:
            ACTIVE_CONNECTIONS.dec()

# Database monitoring
from django.db import connection

def update_db_metrics():
    # Update connection count
    DB_CONNECTIONS.set(len(connection.queries))

# Periodic task to collect DB metrics
from django.core.management.base import BaseCommand
from django_celery_beat.models import PeriodicTask, IntervalSchedule

class Command(BaseCommand):
    def handle(self, *args, **options):
        # Create periodic task for metrics collection
        schedule, created = IntervalSchedule.objects.get_or_create(
            every=30, period=IntervalSchedule.SECONDS
        )

        PeriodicTask.objects.get_or_create(
            interval=schedule,
            name='Update DB Metrics',
            task='monitoring.tasks.update_db_metrics',
        )
```

**Prometheus configuration:**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'web-app'
    static_configs:
      - targets: ['web:8000']
    metrics_path: '/metrics'

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

#### Grafana Dashboards
**Common dashboard panels:**
```json
// CPU Usage Panel
{
  "title": "CPU Usage",
  "type": "graph",
  "targets": [{
    "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
    "legendFormat": "{{instance}}"
  }]
}

// Memory Usage Panel
{
  "title": "Memory Usage",
  "type": "graph",
  "targets": [{
    "expr": "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100",
    "legendFormat": "{{instance}}"
  }]
}

// HTTP Request Rate
{
  "title": "HTTP Request Rate",
  "type": "graph",
  "targets": [{
    "expr": "rate(http_requests_total[5m])",
    "legendFormat": "{{method}} {{endpoint}}"
  }]
}

// Error Rate
{
  "title": "Error Rate",
  "type": "graph",
  "targets": [{
    "expr": "rate(http_requests_total{status=~\"5..\"}[5m]) / rate(http_requests_total[5m]) * 100",
    "legendFormat": "{{endpoint}}"
  }]
}
```

### Alerting and Notifications

#### Alert Manager Configuration
**Prometheus AlertManager setup:**
```yaml
# alertmanager.yml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'your_password'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'team'
  routes:
  - match:
      severity: critical
    receiver: 'critical'
    repeat_interval: 5m

receivers:
- name: 'team'
  email_configs:
  - to: 'team@example.com'
    subject: '{{ .GroupLabels.alertname }}: {{ .Status | title }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Runbook: {{ .Annotations.runbook_url }}
      {{ end }}

- name: 'critical'
  pagerduty_configs:
  - service_key: 'your_pagerduty_key'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
    channel: '#alerts'
    text: |
      :red_circle: *CRITICAL ALERT*
      {{ .GroupLabels.alertname }}
      {{ .CommonAnnotations.summary }}
```

#### Common Alert Rules
**Critical alerts for production:**
```yaml
# alert_rules.yml
groups:
- name: web-app-alerts
  rules:
  - alert: WebAppDown
    expr: up{job="web-app"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Web application is down"
      description: "Web application has been down for more than 5 minutes"
      runbook_url: "https://docs.example.com/runbooks/web-app-down"

  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"[5][0-9][0-9]"}[5m]) / rate(http_requests_total[5m]) > 0.05
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value | printf \"%.2f\" }}%"

  - alert: HighMemoryUsage
    expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage"
      description: "Memory usage is above 90%"

  - alert: DatabaseConnectionIssues
    expr: rate(db_connection_errors_total[5m]) > 5
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Database connection issues"
      description: "High rate of database connection errors"
```

#### Slack Integration
**Slack alerting webhook:**
```python
# Django - monitoring/slack.py
import requests
import json
from django.conf import settings

def send_slack_alert(message, channel='#alerts', color='danger'):
    payload = {
        'channel': channel,
        'username': 'Monitoring Bot',
        'attachments': [{
            'color': color,
            'text': message,
            'ts': time.time()
        }]
    }

    response = requests.post(
        settings.SLACK_WEBHOOK_URL,
        data=json.dumps(payload),
        headers={'Content-Type': 'application/json'}
    )
    return response.status_code == 200

# Usage in monitoring tasks
def alert_on_failure():
    if check_critical_service():
        send_slack_alert(
            f"🚨 CRITICAL: Service is down!\nEnvironment: {settings.ENVIRONMENT}",
            color='danger'
        )
    else:
        send_slack_alert(
            f"✅ Service recovered\nEnvironment: {settings.ENVIRONMENT}",
            color='good'
        )
```

### Log Aggregation and Analysis

#### ELK Stack Configuration
**Elasticsearch, Logstash, Kibana setup:**
```yaml
# docker-compose.monitoring.yml
version: '3.8'
services:
  elasticsearch:
    image: elasticsearch:7.10.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"

  logstash:
    image: logstash:7.10.0
    volumes:
      - ./monitoring/logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    depends_on:
      - elasticsearch

  kibana:
    image: kibana:7.10.0
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
```

**Logstash configuration:**
```conf
# logstash.conf
input {
  file {
    path => "/var/log/app/*.log"
    start_position => "beginning"
  }

  docker {
    docker_logs => true
  }
}

filter {
  json {
    source => "message"
  }

  date {
    match => ["timestamp", "ISO8601"]
  }

  if [level] == "ERROR" {
    mutate {
      add_tag => ["error"]
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "app-logs-%{+YYYY.MM.dd}"
  }
}
```

#### Loki + promtail: four traps that make the pipeline lie rather than fail

Log pipelines fail *silently and plausibly* — they keep shipping, so dashboards look alive while the
data underneath is wrong. All four below shipped past config review and a passing dry-run, and were
only caught by querying live data. Test every one with `promtail -dry-run` against **real log lines
from the target host**, not invented ones.

**1. No `timestamp` stage ⇒ promtail stamps INGESTION time.** On first run promtail reads the whole
existing file, so **days of history are replayed into one window** at install time. Consequences:
every stored timestamp is wrong (which destroys the forensic value the pipeline exists for), any
rate/burst alert fires spuriously on install, Loki's `reject_old_samples_max_age` is inert (everything
looks fresh), and — worst — a **historical** security event replays as a **live critical** (a
month-old `Accepted publickey for root` paging you as if it just happened). Always add the stage:

```yaml
pipeline_stages:
  - regex:
      expression: '^(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.?\d*[+-]\d{2}:\d{2}|[A-Z][a-z]{2}\s+\d{1,2} \d{2}:\d{2}:\d{2})'
  - timestamp:
      source: ts
      format: RFC3339Nano
      fallback_formats: ['Jan _2 15:04:05']   # traditional rsyslog: no year
      location: Europe/Vilnius                # REQUIRED for the year-less form (else UTC ⇒ hours of skew)
```

Journald sources are immune (the journal carries real event times) — this is a **file-source** trap.
**One estate routinely runs BOTH rsyslog formats** (RFC3339 vs `RSYSLOG_TraditionalFileFormat`);
check `/etc/rsyslog.conf` per host, because a format miss is **silent** and falls back to ingest time.

**2. promtail's `replace` substitutes CAPTURE GROUPS — `${1}` backrefs do NOT work.** That is
sed/Go-Expand syntax. `expression: '(KEY)(VALUE)'` + `replace: '${1}<redacted>'` emits the **literal**
text `${1}<redacted>` for *both* groups: the line is mangled **and the secret is not redacted**.
Capture only the value; text outside the group is preserved automatically:

```yaml
- replace:
    expression: '(?i)(?:password|passwd|secret|token|api[-_]?key|authorization|bearer)[=:]\s*(\S+)'
    replace: '<redacted>'
```

**3. A redaction regex that over-matches BLINDS your alert rules — worse than the leak.** Make the
separator **required** (`[=:]`, not `[=:]?`). With it optional, `password` + a space matches ordinary
prose, so `Accepted password for root from 1.2.3.4` is rewritten and no longer contains `for root ` —
the exact substring the root-login alert greps for. You trade a leak for **blindness**. Accept the
residual (a separator-less `Bearer abc123` goes unredacted) and document it: auth logs carry secrets
as `key=value`/`key: value`, and a blinded alert is the worse failure.

**4. LogQL `count by (x) (count_over_time(...))` counts SERIES, not distinct label values.** A series
is the WHOLE label set — including Loki's own **`__stream_shard__`**, plus `filename`,
`detected_level`, `service_name`. One source present in two shards is counted **twice**. To count
distinct values of a parsed label, collapse everything else first:

```logql
count by (host) (                                  # distinct src per host
  sum by (host, src) (                             # ← LOAD-BEARING: collapses shard/filename/etc.
    count_over_time({job="auth"} | regexp `(?P<src>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})` | __error__ = `` [5m])))
```

**Narrow-scraping journald: filter on `__journal__comm`, NOT `__journal_syslog_identifier`.** The
syslog tag is user-settable, so an identifier-based keep lets any user forge a match —
`logger -t sshd "Accepted publickey for root"` becomes a **critical alert**. `comm` is the real
binary name and is spoof-resistant. Consequence to design around: a `logger`-emitted verification
marker has `comm=logger` and is **dropped by your own filter** — so a `logger` smoke-test
false-negatives on journald hosts while the agent is perfectly healthy. Verify those hosts by
asserting the agent is active **and** its stream has a recent line instead.

#### Application Logging Standards
**Structured logging patterns:**
```python
# Django - utils/logging.py
import logging
import json
import sys
from pythonjsonlogger import jsonlogger

class CustomJsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super(CustomJsonFormatter, self).add_fields(log_record, record, message_dict)
        log_record['timestamp'] = record.created
        log_record['level'] = record.levelname
        log_record['logger'] = record.name
        log_record['module'] = record.module
        log_record['function'] = record.funcName
        log_record['line'] = record.lineno

        # Add request context if available
        if hasattr(record, 'request'):
            log_record['request_id'] = getattr(record.request, 'request_id', None)
            log_record['user_id'] = getattr(record.request.user, 'id', None)
            log_record['method'] = record.request.method
            log_record['path'] = record.request.path

# settings.py logging configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'utils.logging.CustomJsonFormatter',
        },
        'simple': {
            'format': '{levelname} {asctime} {module} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'simple',
            'stream': sys.stdout,
        },
        'file': {
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/var/log/app/app.log',
            'maxBytes': 10*1024*1024,  # 10MB
            'backupCount': 5,
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
    },
}

# Usage in views
logger = logging.getLogger(__name__)

def my_view(request):
    logger.info("Processing request", extra={
        'request': request,
        'user_id': request.user.id if request.user.is_authenticated else None,
        'action': 'process_data'
    })

    try:
        # Process request
        result = process_data(request.data)
        logger.info("Request processed successfully", extra={
            'request': request,
            'result_count': len(result)
        })
        return JsonResponse({'status': 'success', 'data': result})
    except Exception as e:
        logger.error("Request processing failed", extra={
            'request': request,
            'error': str(e),
            'error_type': type(e).__name__
        })
        return JsonResponse({'status': 'error', 'message': str(e)}, status=500)
```

### Database Monitoring

#### Database Performance Metrics
**PostgreSQL monitoring:**
```sql
-- Active connections
SELECT count(*) as active_connections
FROM pg_stat_activity
WHERE state = 'active';

-- Slow queries (>100ms)
SELECT query, total_time, calls, mean_time
FROM pg_stat_statements
WHERE mean_time > 100
ORDER BY mean_time DESC
LIMIT 10;

-- Table bloat
SELECT schemaname, tablename,
       n_dead_tup, n_live_tup,
       ROUND(n_dead_tup::float / (n_live_tup + n_dead_tup) * 100, 2) as bloat_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY bloat_ratio DESC;

-- Index usage
SELECT schemaname, tablename, indexname,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

**MySQL monitoring:**
```sql
-- Active connections
SHOW PROCESSLIST;

-- Slow query log analysis
SELECT sql_text, exec_count, avg_timer_wait/1000000000 as avg_time_sec
FROM performance_schema.events_statements_summary_by_digest
WHERE avg_timer_wait > 1000000000
ORDER BY avg_timer_wait DESC;

-- InnoDB buffer pool usage
SELECT
  (Pages_data * 16384)/1024/1024 as data_mb,
  (Pages_free * 16384)/1024/1024 as free_mb,
  (Pages_total * 16384)/1024/1024 as total_mb,
  ROUND((Pages_data / Pages_total) * 100, 2) as usage_pct
FROM information_schema.innodb_buffer_pool_stats;
```

### Docker Compose Monitoring Stack

**Complete monitoring setup:**
```yaml
# docker-compose.monitoring.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"

  alertmanager:
    image: prom/alertmanager
    volumes:
      - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"

  grafana:
    image: grafana/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"

  node-exporter:
    image: prom/node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
    ports:
      - "9100:9100"

  cadvisor:
    image: google/cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
    ports:
      - "8080:8080"
```

## Why It's Generic
These monitoring patterns apply to any web application regardless of framework because they focus on:
- Standard HTTP health check protocols
- Container and system resource metrics
- Database performance monitoring
- Log aggregation and analysis
- Alerting and notification systems
- Time-series metrics collection

The patterns scale from single-service applications to complex microservices architectures with multiple databases, caches, and background workers.

## Example Use Cases
**Django Application Monitoring:**
- Model query performance tracking
- Celery task queue monitoring
- WebSocket connection health
- Multi-tenant schema performance isolation

**Rails Application Monitoring:**
- ActiveRecord query optimization
- Sidekiq job queue monitoring
- Puma worker process health
- Action Cable connection monitoring

**Node.js Application Monitoring:**
- Event loop blocking detection
- Memory leak identification
- Express route performance
- Socket.io connection monitoring

## References
- [Prometheus Documentation](https://prometheus.io/docs/) - Metrics collection and alerting
- [Grafana Documentation](https://grafana.com/docs/) - Visualization and dashboards
- [ELK Stack](https://www.elastic.co/elastic-stack) - Log aggregation and analysis
- [AlertManager](https://prometheus.io/docs/alerting/latest/alertmanager/) - Alert routing and notifications
