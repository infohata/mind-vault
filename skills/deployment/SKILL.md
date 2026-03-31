---
name: deployment
description: |
  Comprehensive deployment patterns for production web applications using Docker Compose,
  focusing on automated deployment scripts, change detection, backup strategies, and zero-downtime updates.
  Emphasizes safety through automated backups, rollback procedures, and comprehensive verification.
license: MIT
compatibility: opencode
metadata:
  author: mind-vault
  version: "1.0"
  replaces:
     - [none]
---

## Overview

Core deployment patterns for production web applications using Docker Compose, focusing on automated deployment scripts, change detection, backup strategies, and zero-downtime updates. Emphasizes safety through automated backups, rollback procedures, and comprehensive verification.

**This skill covers**:
 - Branch strategy and release management
 - Service architecture with Docker Compose
 - Change detection and intelligent deployments
 - Database safety (backups, migrations, rollbacks)
 - Remote deployment with SSH and safety confirmation
 - Screen sessions for remote deployments (mandatory)
 - SSL certificate management with Let's Encrypt
 - Health checks and deployment verification
 - Environment management and configuration
 - Makefile targets for common operations
 - CI/CD integration (GitHub Actions, GitLab CI)

**Optional Extensions** (load on-demand):
 - [Monitoring Integration](references/MONITORING.md) - Production monitoring with Prometheus, Grafana, ELK
 - [Django Deployment](references/DJANGO_DEPLOYMENT.md) - Django-specific deployment patterns and optimizations
 - [Server Hardening](references/HARDENING.md) - SSH, firewall, fail2ban, and automatic security updates before deployment

## When to Use
Any web application deployed using Docker Compose that requires:
- Production deployment automation
- Safe database schema updates
- Environment-specific configuration
- SSL certificate management
- Multi-service coordination (web app, proxy, database, cache)

## Pattern

### Branch Strategy
**Separate production branch from development:**
- Use `deployment` (or `production`) branch for releases
- Manual merge of stable commits from `main`/`develop`
- Clear commit history for rollbacks
- Branch protection prevents accidental changes

**Workflow:**
```bash
# Merge stable commits to deployment
git checkout deployment
git merge <stable-commit-hash>
git push origin deployment

# Deploy from deployment branch
git pull origin deployment
./deploy.sh
```

### Deployment documentation tracking
**Do not skip**: When running or assisting with a deployment, ensure the project tracks it.
- **Where**: Session logs and state live in the repo under a deployment subdir (e.g. `docs/execution/deployment/`).
- **Session filename**: `{host}_yyyymmdd-hhmm.md` (e.g. `teisutis_com_20260203-1415.md`). One file per deployment run; include screen session name, log path, checklist, rollback plan.
- **Template**: Copy from a state template in that directory when preparing a deployment (risk, verification, rollback).
- **Reference**: If the project has a deployment guide, it should point to this directory and convention so agents and humans don't forget to create/update session files.

### Service Architecture
**Multi-service Docker Compose with:**
- Web application container (Django/Flask/etc.)
- Reverse proxy (nginx/caddy)
- Database (PostgreSQL/MySQL)
- Cache (Redis/Memcached)
- File storage (MinIO/S3)
- Background workers (Celery)
- SSL certificate management (certbot)

**Key principles:**
- Services communicate via internal network
- Volumes for persistent data
- Environment variable configuration
- Health checks and dependencies

### Deployment Scripts
**Auto-detecting wrapper script:**
```bash
#!/bin/bash
# scripts/deploy.sh - Auto-detect first-time vs update
# Non-interactive: DEPLOY_NON_INTERACTIVE=1 ./deploy.sh  or  ./deploy.sh --yes

SERVICES_RUNNING=$(docker compose ps | grep -q "Up\|running" && echo "true" || echo "false")

if [ "$SERVICES_RUNNING" = "true" ]; then
    exec ./scripts/deploy_update.sh "$@"
else
    exec ./scripts/deploy_first_time.sh "$@"
fi
```

**Non-interactive mode** (for screen sessions, CI, automated runs):

Deploy scripts may prompt for `.env` changes and confirmations. Use non-interactive mode to skip all prompts (safe defaults: no .env changes, auto-detect from git):

```bash
# Option 1: Environment variable
DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh

# Option 2: --yes flag
./tools/deploy.sh --yes

# Remote in screen (recommended):
screen -dmS myapp-deploy-$(date -u +%Y%m%d-%H%M%S) bash -c \
  'cd /opt/myapp && DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee deploy-$(date -u +%Y%m%d-%H%M%S).log'
```

**Why**: Screen allocates a TTY, so `[ -t 0 ]` is true and scripts wait for input. Explicit `DEPLOY_NON_INTERACTIVE=1` or `--yes` forces non-interactive regardless of TTY.

**Update script with smart change detection and backups:**
```bash
#!/bin/bash
# scripts/deploy_update.sh - Intelligent updates
git pull origin deployment

# Auto-detect changes
HAS_MIGRATIONS=$(git diff HEAD@{1} HEAD --name-only | grep -q "migrations/" && echo "true" || echo "false")

if [ "$HAS_MIGRATIONS" = "true" ]; then
    ./scripts/backup_db.sh  # Backup before migrations
fi

# Apply changes based on detection
# ... (rebuilds, restarts, migrations)
```

**Dependency rebuild + SCSS**: When dependencies change (requirements, Dockerfile), the script rebuilds containers. Always run SCSS compile + collectstatic after a rebuild — new code may have SCSS changes even if change detection misses them. The generic scripts set `HAS_STATIC=true` when `HAS_DEPENDENCIES=true`.

**Complete generic scripts are available in the `scripts/` directory with:**
- `deploy.sh` - Auto-detecting wrapper
- `deploy_first_time.sh` - Initial deployment setup  
- `deploy_update.sh` - Smart update with change detection
- `backup_db.sh` - Multi-database backup support
- `verify_deployment.sh` - Comprehensive health checks

**Project Root Detection (Global Skill Support):**
```bash
# Scripts automatically detect project root:
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"  # Explicit override
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"  # Git repo root
else
    echo "Warning: Using current directory"  # Fallback
fi
```

**Remote Deployment Support:**
```bash
# Deploy to remote server with SSH
./scripts/deploy.sh --remote user@production.com --dir /opt/myapp

# Scripts handle:
# - SSH key authentication (assumes keys configured)
# - Explicit user confirmation for remote operations
# - Safe script execution from /tmp (no repo contamination)
# - Automatic cleanup of temporary scripts
# - Git-based project directory detection
```

### Remote Deployment Example
**Production deployment workflow:**
```bash
# Local development and testing
./scripts/deploy.sh  # Test locally first

# Remote deployments MUST use screen sessions (see Screen Sessions section below)
# Never run remote deployments directly - use screen to prevent connection loss

# Remote staging deployment with screen
ssh deploy@staging.example.com << 'EOF'
cd /opt/myapp
screen -dmS myapp-deploy-$(date +%Y%m%d-%H%M%S) bash -c "DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee deploy-$(date +%Y%m%d-%H%M%S).log"
EOF

# Remote production deployment with screen
ssh deploy@production.example.com << 'EOF'
cd /opt/myapp
screen -dmS myapp-deploy-$(date +%Y%m%d-%H%M%S) bash -c "DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee deploy-$(date +%Y%m%d-%H%M%S).log"
EOF
```

**What happens during remote deployment:**
1. **Connection**: SSH to remote server using configured keys
2. **Confirmation**: User explicitly confirms remote operations
3. **Script Transfer**: Copies deployment scripts to remote server
4. **Execution**: Runs deployment on remote server
5. **Verification**: Returns results and status

### Screen Sessions for Remote Deployments

**⚠️ CRITICAL: Always use screen for remote deployments**

Remote deployments MUST use screen sessions to prevent data loss from:
- SSH connection timeouts
- Network interruptions
- API errors
- Client disconnections
- Terminal closures

**Policy for AI agents:**
- **Remote deployment** → ALWAYS use screen (mandatory)
- **Local deployment** → Optional (user convenience only)

**Session naming convention:**
```bash
{project}-deploy-{YYYYMMDD-HHMMSS}
Example: teisutis-deploy-20260130-012343
```

**Standard remote deployment with screen:**
```bash
# SSH and start screen session with timestamped log
# Use DEPLOY_NON_INTERACTIVE=1 so scripts skip prompts (screen has TTY but no stdin)
ssh user@production.com << 'EOF'
cd /opt/myapp
SESSION_NAME="myapp-deploy-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"

screen -dmS "$SESSION_NAME" bash -c "DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee $LOG_FILE"

echo "✅ Screen session started: $SESSION_NAME"
echo "📋 Log file: $LOG_FILE"
echo ""
echo "🔍 Monitor deployment:"
echo "   tail -f $LOG_FILE"
echo "   screen -r $SESSION_NAME"
echo ""
echo "📋 First 30 seconds of output:"
sleep 3 && tail -n 50 "$LOG_FILE"
EOF
```

**Monitoring deployment progress:**
```bash
# View log file (recommended - persists after screen exits)
ssh user@production.com 'tail -f /opt/myapp/deploy-20260130-012343.log'

# Attach to screen session (interactive, see live output)
ssh -t user@production.com 'screen -r myapp-deploy-20260130-012343'

# Detach from screen (inside session): Ctrl+A, then D

# List all screen sessions
ssh user@production.com 'screen -ls'

# Attach to most recent deployment session
ssh -t user@production.com 'screen -r $(screen -ls | grep deploy | head -1 | cut -d. -f1)'
```

**One-liner for quick remote deployment:**
```bash
ssh user@production.com "cd /opt/myapp && screen -dmS myapp-deploy-\$(date +%Y%m%d-%H%M%S) bash -c 'DEPLOY_NON_INTERACTIVE=1 ./tools/deploy.sh 2>&1 | tee deploy-\$(date +%Y%m%d-%H%M%S).log' && sleep 3 && screen -ls | grep deploy && tail -n 50 deploy-*.log"
```

**Session cleanup after successful deployment:**
```bash
# List deployment sessions
ssh user@production.com 'screen -ls | grep deploy'

# Kill specific session (after verifying deployment success)
ssh user@production.com 'screen -X -S myapp-deploy-20260130-012343 quit'

# Clean up all detached deployment sessions (use with caution)
ssh user@production.com 'screen -ls | grep Detached | grep deploy | cut -d. -f1 | xargs -I{} screen -X -S {} quit'
```

**Best practices:**
- ✅ **Always use screen for remote** - No exceptions for production deployments
- ✅ **Timestamped logs** - Screen sessions terminate, logs persist
- ✅ **Timestamped session names** - Prevents collision with concurrent deployments
- ✅ **Show initial output** - Confirm deployment started correctly
- ✅ **Provide monitoring commands** - User needs to know how to check progress
- ✅ **Keep logs for analysis** - Add `deploy-*.log` to .gitignore
- ❌ **Never skip screen on remote** - Even "quick" deployments can fail unexpectedly
- ❌ **Don't reuse session names** - Use timestamps to ensure uniqueness

**Typical remote deployment workflow:**
```bash
# 1. Start screen deployment
ssh user@production.com << 'EOF'
cd /opt/myapp
SESSION="myapp-deploy-$(date +%Y%m%d-%H%M%S)"
LOG="deploy-$(date +%Y%m%d-%H%M%S).log"
screen -dmS "$SESSION" bash -c "./tools/deploy.sh 2>&1 | tee $LOG"
echo "Session: $SESSION | Log: $LOG"
sleep 3 && tail -n 50 "$LOG"
EOF

# 2. Monitor progress (from local machine)
ssh user@production.com 'tail -f /opt/myapp/deploy-*.log'

# 3. Or attach to see interactive output
ssh -t user@production.com 'screen -r $(screen -ls | grep deploy | head -1 | cut -d. -f1)'

# 4. After completion, verify and clean up
ssh user@production.com 'docker compose ps && screen -ls'
ssh user@production.com 'screen -X -S myapp-deploy-20260130-012343 quit'
```

**Handling long rebuilds (20-30+ minutes):**
```bash
# Screen protects against timeout - deployment continues even if you disconnect
# You can safely:
# - Close terminal
# - Disconnect VPN
# - Switch networks
# - Log out

# Reconnect anytime to check progress
ssh user@production.com 'tail -f /opt/myapp/deploy-*.log'
ssh -t user@production.com 'screen -r myapp-deploy'
```

**Troubleshooting:**

*Screen not installed on server:*
```bash
ssh user@production.com 'command -v screen || echo "Not installed"'

# Install (Debian/Ubuntu)
ssh user@production.com 'sudo apt-get install screen'

# Install (RHEL/CentOS)
ssh user@production.com 'sudo yum install screen'
```

*Can't find deployment session:*
```bash
# List all sessions
ssh user@production.com 'screen -ls'

# Check log files
ssh user@production.com 'ls -lt /opt/myapp/deploy-*.log | head -5'

# Attach to most recent deployment
ssh -t user@production.com 'screen -r $(screen -ls | grep deploy | head -1 | cut -d. -f1)'
```

*Deployment finished but screen still active:*
```bash
# Normal behavior - screen persists after command completion
# Safe to kill after verifying deployment success
ssh user@production.com 'screen -X -S session-name quit'
```

*Multiple deployments running:*
```bash
# List all deployment sessions with timestamps
ssh user@production.com 'screen -ls | grep deploy'

# Attach to specific session by full name
ssh -t user@production.com 'screen -r myapp-deploy-20260130-012343'
```

### Change Detection
**Automatic change type detection:**
```bash
# Get previous commit for comparison
PREVIOUS_COMMIT=$(git rev-parse HEAD@{1} 2>/dev/null || echo "")

if [ -n "$PREVIOUS_COMMIT" ]; then
    HAS_MIGRATIONS=$(git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -q "migrations/" && echo "true" || echo "false")
    HAS_DEPENDENCIES=$(git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "(requirements.*\.txt|Dockerfile)" && echo "true" || echo "false")
    HAS_STATIC=$(git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "\.(css|js|png|jpg)" && echo "true" || echo "false")
fi
```

### Backup Strategy
**Database backups before schema changes:**
```bash
# Before migrations
if [ "$HAS_MIGRATIONS" = "true" ]; then
    ./backup_db.sh  # Creates timestamped backup
fi

# Run migrations
docker compose exec web python manage.py migrate

# After successful migrations
./backup_db.sh  # Backup new state
```

**Backup naming convention:**
```
data/db_backup_YYYYMMDD_HHMMSS_<commit-hash>.sql.tar.gz
```

### Environment Management
**Environment variables for all configuration:**
- Database credentials
- Secret keys
- Domain configuration
- Feature flags
- External service credentials

**Environment file handling:**
```bash
# Load environment
set -a
source .env
set +a

# Recreate containers when .env changes
docker compose up -d --force-recreate web worker
```

### SSL Certificate Management
**Automated Let's Encrypt certificates:**
```yaml
# docker-compose.yml
certbot:
  image: certbot/certbot
  command: |
    certbot certonly --webroot --webroot-path=/var/www/certbot \
      --email $$CERTBOT_EMAIL --agree-tos --no-eff-email -d $$DOMAIN
  volumes:
    - certbot-etc:/etc/letsencrypt
    - certbot-var:/var/lib/letsencrypt
    - ./nginx/www:/var/www/certbot
```

**Nginx configuration with SSL:**
```nginx
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    # ... proxy configuration
}
```

### Health Checks and Verification
**Post-deployment verification:**
```bash
# Service status
docker compose ps

# Web application health
curl -I https://${DOMAIN}

# API endpoints
curl https://${DOMAIN}/api/health

# Database connectivity
docker compose exec web python manage.py dbshell -c "SELECT 1"
```

### Rollback Procedures
**Rollback to previous deployment:**
```bash
# Reset deployment branch
git checkout deployment
git reset --hard <last-good-commit>
git push origin deployment --force

# Redeploy
git pull origin deployment
./deploy.sh
```

**Database rollback:**
```bash
# Restore from backup
./restore_db.sh data/db_backup_YYYYMMDD_HHMMSS_<commit>.sql.tar.gz

# Revert code
git reset --hard <previous-commit>
docker compose restart web worker
```

### Makefile Targets
**Comprehensive management commands:**
```makefile
.PHONY: deploy deploy-first deploy-update backup-db restore-db
.PHONY: start stop restart logs health-check

deploy: ## Auto-detect and run appropriate deployment
	./tools/deploy.sh

deploy-first: ## First-time deployment
	./tools/deploy_first_time.sh

deploy-update: ## Update existing deployment
	./tools/deploy_update.sh

backup-db: ## Create database backup
	./tools/backup_db.sh

restore-db: ## Restore database from backup
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore-db FILE=backup_file.tar.gz"; \
		exit 1; \
	fi
	./tools/restore_db.sh "$(FILE)"

start: ## Start all services
	docker compose up -d

stop: ## Stop all services
	docker compose down

restart: ## Restart all services
	docker compose restart

logs: ## View logs
	docker compose logs -f

health-check: ## Run health checks
	./tools/verify_deployment.sh
```

### CI/CD Integration
**Automated deployment pipelines for production safety:**

#### GitHub Actions Example
**`.github/workflows/deploy.yml`:**
```yaml
name: Deploy to Production

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
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment || 'staging' }}
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        fetch-depth: 0  # Full history for change detection

    - name: Setup SSH
      uses: webfactory/ssh-agent@v0.9.0
      with:
        ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

    - name: Deploy to server
      run: |
        # Copy deployment scripts to server
        scp -o StrictHostKeyChecking=no ./scripts/deploy.sh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }}:/tmp/
        
        # Execute deployment remotely
        ssh -o StrictHostKeyChecking=no ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} << 'EOF'
          cd ${{ secrets.DEPLOY_DIR }}
          chmod +x /tmp/deploy.sh
          /tmp/deploy.sh
        EOF
```

#### GitLab CI Example
**`.gitlab-ci.yml`:**
```yaml
stages:
  - test
  - deploy

deploy_staging:
  stage: deploy
  script:
    - chmod +x ./scripts/deploy.sh
    - ./scripts/deploy.sh --remote $STAGING_USER@$STAGING_HOST --dir $STAGING_DIR
  environment:
    name: staging
    url: https://staging.example.com
  only:
    - develop

deploy_production:
  stage: deploy
  script:
    - chmod +x ./scripts/deploy.sh
    - ./scripts/deploy.sh --remote $PRODUCTION_USER@$PRODUCTION_HOST --dir $PRODUCTION_DIR
  environment:
    name: production
    url: https://example.com
  when: manual
  only:
    - main
```

#### Automated Change Detection in CI
**Pre-deployment validation:**
```yaml
# GitHub Actions - Check for breaking changes
- name: Check for migrations
  id: migrations
  run: |
    if git diff --name-only ${{ github.event.before }} ${{ github.sha }} | grep -q "migrations/"; then
      echo "has_migrations=true" >> $GITHUB_OUTPUT
    fi

- name: Backup database (if migrations detected)
  if: steps.migrations.outputs.has_migrations == 'true'
  run: |
    ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} \
      "cd ${{ secrets.DEPLOY_DIR }} && ./scripts/backup_db.sh"

- name: Deploy with change awareness
  run: |
    ssh ${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }} \
      "cd ${{ secrets.DEPLOY_DIR }} && ./scripts/deploy.sh"
```

#### Environment-Specific Secrets
**GitHub Secrets setup:**
```
SSH_PRIVATE_KEY          # Private SSH key for server access
DEPLOY_USER              # SSH username
DEPLOY_HOST              # Server hostname/IP
DEPLOY_DIR               # Deployment directory path
CERTBOT_EMAIL            # Email for SSL certificates
DOMAIN                   # Domain name for SSL
```

**GitLab CI Variables:**
```
STAGING_USER             # Staging server credentials
STAGING_HOST
STAGING_DIR
PRODUCTION_USER          # Production server credentials  
PRODUCTION_HOST
PRODUCTION_DIR
```

#### Security Considerations
**CI/CD security best practices:**
- **SSH Key Management**: Use dedicated deployment keys with minimal permissions
- **Secret Rotation**: Regularly rotate SSH keys and tokens
- **Branch Protection**: Require reviews for deployment branch merges
- **Environment Isolation**: Separate staging/production secrets
- **Audit Logging**: Log all deployment activities
- **Rollback Automation**: Include automated rollback in pipeline failure

#### Deployment Approval Gates
**Manual approval for production:**
```yaml
# GitHub Actions - Require approval for production
deploy_production:
  runs-on: ubuntu-latest
  environment: 
    name: production
    url: https://example.com
  steps:
    # ... deployment steps
    
# GitLab CI - Manual trigger for production
deploy_production:
  when: manual
  only:
    refs:
      - main
    changes:
      - docker-compose.yml
      - requirements.txt
```

#### Notification Integration
**Deployment status notifications:**
```yaml
# Slack notification on deployment
- name: Notify Slack
  uses: 8398a7/action-slack@v3
  if: always()
  with:
    status: ${{ job.status }}
    text: "Deployment to ${{ inputs.environment }} ${{ job.status }}"
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## Troubleshooting Common Issues

### Database Connection Failures
**Symptoms**: Container fails to start with database connection errors
**Solutions**:
- Check database service is running: `docker compose ps db`
- Verify connection string in environment variables
- Ensure database is accepting connections from container network
- Check database logs: `docker compose logs db`

### Migration Failures
**Symptoms**: Deployment fails during migration step
**Check**:
- Review migration files for syntax errors
- Ensure previous migrations ran successfully
- Check database permissions for migration user
- Verify migration dependencies are met

### SSL Certificate Issues
**Symptoms**: HTTPS not working, certificate errors
**Solutions**:
- Check Certbot logs: `docker compose logs certbot`
- Verify domain DNS points to server
- Ensure ports 80/443 are open and not blocked by firewall
- Check certificate renewal: `certbot certificates`

### Permission Errors
**Symptoms**: File permission errors during deployment
**Solutions**:
- Ensure user running deployment has write access to deployment directory
- Check file ownership: `ls -la /opt/django-app`
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa`

### Service Health Check Failures
**Symptoms**: Deployment succeeds but services fail health checks
**Debug**:
- Check service logs: `docker compose logs <service-name>`
- Verify health check endpoints are accessible
- Test services manually: `docker compose exec <service> curl localhost:8000/health/`
- Check resource constraints (memory, CPU)

### Rollback Procedures
**When deployment fails**:
1. Stop failing services: `docker compose stop`
2. Restore backup: `./scripts/backup_db.sh restore`
3. Revert to previous working state: `git checkout <previous-commit>`
4. Restart services: `docker compose up -d`

## Why It's Generic
These patterns apply to any Docker Compose-based web application regardless of framework (Django, Rails, Express, etc.) because they focus on:
- Container orchestration best practices
- Database safety during schema changes
- Infrastructure automation
- Zero-downtime deployment strategies
- Environment-specific configuration management

The patterns scale from single-service applications to complex multi-tenant systems with background workers, file storage, and real-time features.

## Example Use Cases
**Django Application Deployment (like Teisutis):**
- Multi-tenant schema management with django-tenants
- WebSocket support through Daphne proxy
- MinIO integration for file storage
- Celery background task processing
- Elasticsearch for search functionality

**Rails Application Deployment:**
- Puma web server with nginx proxy
- PostgreSQL with schema migrations
- Redis for caching and background jobs
- Sidekiq worker processes
- Active Storage with S3-compatible storage

**Node.js Application Deployment:**
- Express/Next.js application container
- nginx for static file serving and SSL termination
- MongoDB/PostgreSQL database
- Redis for session storage and caching
- PM2 for process management within container

## References
- [Deployment Scripts](./scripts/) - Complete generic deployment scripts with customization guide
- [Scripts README](./scripts/README.md) - Detailed usage instructions and framework-specific examples
- [Deployment Pattern Analysis](../../docs/artefacts/by-agent/researcher/research/DEPLOYMENT_PATTERN_ANALYSIS.md) - Research and pattern extraction
- [Deployment Architecture Design](../../docs/artefacts/by-agent/architect/analyses/DEPLOYMENT_ARCHITECTURE_DESIGN.md) - Design decisions and trade-offs
- [Monitoring Architecture Design](../../docs/artefacts/by-agent/architect/analyses/MONITORING_ARCHITECTURE_DESIGN.md) - Observability framework design
- [Deployment Approach Validation](../../docs/artefacts/by-agent/test-engineer/validations/DEPLOYMENT_APPROACH_VALIDATION.md) - Cross-framework validation (98% success rate)
- [Docker Compose Documentation](https://docs.docker.com/compose/) - Container orchestration
- [Let's Encrypt with Docker](https://letsencrypt.org/docs/certificates-for-localhost/) - SSL automation