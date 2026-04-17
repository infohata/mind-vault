# Deployment Scripts

This directory contains generic deployment scripts that can be customized for any Docker Compose-based web application. These scripts implement the patterns described in the main [SKILL.md](../SKILL.md).

## Project Root Detection

Since these scripts are part of a global skill that can be used across different coding environments (OpenCode, Cursor, Claude Code, etc.), they use intelligent project root detection:

1. **Environment Variable Override**: If `PROJECT_ROOT` is set, use that path
2. **Git Repository Detection**: Use `git rev-parse --show-toplevel` to find the repository root
3. **Fallback**: Use current working directory with a warning

**Examples:**

```bash
# Override project root explicitly
PROJECT_ROOT=/path/to/my/project ./scripts/deploy.sh

# Let script auto-detect (recommended)
./scripts/deploy.sh
```

## Remote Deployment

**⚠️ CRITICAL: All remote deployments MUST use screen sessions**

Remote deployments require screen sessions to protect against connection loss from SSH timeouts, network interruptions, or client disconnections. See the [Screen Sessions section](../SKILL.md#screen-sessions-for-remote-deployments) in the main SKILL.md for complete documentation.

**Standard remote deployment pattern:**

```bash
# Always use screen for remote deployments
ssh user@production.com << 'EOF'
cd /opt/myapp
SESSION="myapp-deploy-$(date +%Y%m%d-%H%M%S)"
LOG="deploy-$(date +%Y%m%d-%H%M%S).log"
screen -dmS "$SESSION" bash -c "./tools/deploy.sh 2>&1 | tee $LOG"
echo "Session: $SESSION | Log: $LOG"
sleep 3 && tail -n 50 "$LOG"
EOF

# Monitor from local machine
ssh user@production.com 'tail -f /opt/myapp/deploy-*.log'

# Or attach to screen session
ssh -t user@production.com 'screen -r myapp-deploy'
```

**Legacy direct execution (NOT RECOMMENDED):**

```bash
# These patterns are unsafe for remote deployments:
./scripts/deploy.sh --remote user@production.com --dir /opt/myapp  # No screen protection
./scripts/deploy_update.sh --remote user@host --dir /path          # No screen protection

# Only use direct execution for:
# - Local deployments
# - Testing/development
# - Very quick operations (<1 minute)
```

**Repository Safety**: Deployment scripts are executed from `/tmp` and automatically cleaned up, ensuring they never contaminate your project git repository or interfere with git operations.

## Usage Examples

### Local Deployment

```bash
# Auto-detect first-time vs update
./scripts/deploy.sh

# Force first-time deployment
./scripts/deploy_first_time.sh

# Force update deployment
./scripts/deploy_update.sh

# Create database backup
./scripts/backup_db.sh

# Verify deployment health
./scripts/verify_deployment.sh
```

### Remote Deployment Examples

```bash
# RECOMMENDED: Deploy to remote with screen session
ssh user@production.com << 'EOF'
cd /opt/myapp
SESSION="myapp-deploy-$(date +%Y%m%d-%H%M%S)"
LOG="deploy-$(date +%Y%m%d-%H%M%S).log"
screen -dmS "$SESSION" bash -c "./tools/deploy.sh 2>&1 | tee $LOG"
echo "✅ Session: $SESSION"
echo "📋 Log: $LOG"
sleep 3 && tail -n 50 "$LOG"
EOF

# Monitor deployment progress
ssh user@production.com 'tail -f /opt/myapp/deploy-*.log'

# Attach to screen session
ssh -t user@production.com 'screen -r $(screen -ls | grep deploy | head -1 | cut -d. -f1)'

# Cleanup after successful deployment
ssh user@production.com 'screen -X -S myapp-deploy-20260130-012343 quit'
```

### `deploy.sh`

**Purpose**: Auto-detecting deployment wrapper script

**Usage**:

```bash
./scripts/deploy.sh
```

**What it does**:

- Detects if services are already running
- Automatically calls `deploy_first_time.sh` or `deploy_update.sh`
- Provides clear feedback about which path is taken

### `deploy_first_time.sh`

**Purpose**: Initial deployment setup

**Usage**:

```bash
./scripts/deploy_first_time.sh
```

**What it does**:

- Builds Docker images with `--no-cache`
- Starts all services
- Runs initial database migrations
- Compiles SCSS/Sass (if present: `make build-scss` or Django `compile_scss`) then collects static files
- Initializes external services (customize as needed)

**Customization required**:

- `REQUIRED_VARS` array: Add your required environment variables
- Database migration commands: Replace Django commands with your framework's
- Static files collection: Replace with your framework's commands
- External service initialization: Add MinIO setup, admin user creation, etc.

### `deploy_update.sh`

**Purpose**: Update existing deployment with new changes

**Usage**:

```bash
./scripts/deploy_update.sh
```

**What it does**:

- Pulls latest code from deployment branch
- Auto-detects change types: migrations, static files, dependencies, nginx config, translations
- Creates database backups **before and after** migrations (pairs with commit sha for clean rollback)
- Rebuilds containers if dependencies changed (implies static + migrations too — new packages may ship their own migrations)
- Recreates containers if environment variables changed (force via `DEPLOY_RECREATE_ENV=1`)
- Compiles `.po` translation messages when they change, then restarts to reload the catalogue
- Rebuilds nginx when nginx config or certbot entrypoint scripts change
- Runs migrations and collects static files as needed
- Restarts services for code changes
- Writes `.deploy_commit_state` after success — so a crashed rerun compares against the last good deploy instead of a broken HEAD@{1}

**Change detection patterns** (customize these regex patterns; aligned with Teisutis `tools/deploy_update.sh`):

- Migrations: `migrations/|db/migrate`
- Static files: `\.(css|js|png|jpg|jpeg|gif|svg|ico|scss|sass)$` or paths containing `/scss/` or `/sass/`. When static changed, script runs theme build (host: `make build-scss` if present; container: Django `compile_scss` if present) then collectstatic.
- Dependencies: `requirements.*\.txt|package\.json|Gemfile|Dockerfile`

**Important**: When dependencies change (rebuild), the script **always** runs SCSS compile + collectstatic. This avoids a common bug: dependency-only changes trigger a full rebuild, but change detection may miss SCSS files (e.g. when git reflog is unavailable). Without this, production can end up with stale or missing compiled CSS.

### `backup_db.sh`

**Purpose**: Create compressed database backups

**Usage**:

```bash
./scripts/backup_db.sh
```

**Features**:

- Supports PostgreSQL, MySQL, and SQLite
- Creates timestamped backups with commit hash
- Compresses backups with tar.gz
- Stores in `data/` directory

**Environment variables** (set in `.env`):

- `DB_TYPE`: `postgresql`, `mysql`, or `sqlite`
- `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`

### `restore_db.sh`

**Purpose**: Restore the database from a backup file created by `backup_db.sh`

**Usage**:

```bash
./scripts/restore_db.sh data/db_backup_YYYYMMDD_HHMMSS_<sha>.sql.tar.gz
./scripts/restore_db.sh data/db_backup_*.tar.gz --yes   # non-interactive
```

**Features**:

- Interactive confirmation before destructive replace (skip with `--yes` or `DEPLOY_NON_INTERACTIVE=1`)
- Drops and recreates the target database
- Handles both `tar.gz` (preferred) and plain `.gz` backup formats
- Lists the 10 most-recent backups when invoked without arguments

**⚠️ Human-operated only**: destructive (drops the DB). Per [RULE_git-safety](../../../rules/RULE_git-safety.md), AI agents should not execute this without explicit user approval.

### `verify_deployment.sh`

**Purpose**: Health checks and deployment verification

**Usage**:

```bash
./scripts/verify_deployment.sh
```

**Checks performed**:

- Service status (running/stopped)
- Database connectivity
- HTTP/HTTPS endpoints
- API health check
- SSL certificates (in production mode)

**Customization required**:

- `SERVICES` array: List your Docker Compose services
- Endpoint URLs: Update for your application's URLs
- API health check path: Change `/api/health` to your health endpoint

### `setup_server.sh`

**Purpose**: Initial server setup with development tools

**Usage**:

```bash
./scripts/setup_server.sh
```

**What it does**:

- Installs pyenv and latest Python 3.13.x
- Installs Docker Engine with Compose plugin
- Installs Node.js 25.x from NodeSource
- Configures user for docker group access

**Requirements**:

- Ubuntu 24.04 LTS (tested)
- sudo access
- Internet connection

**Post-installation**:

- Log out and back in for docker group to take effect
- Python available via `pyenv global`

### `harden_server.sh`

**Purpose**: Server hardening (SSH key-only, UFW, fail2ban, automatic security updates)

**Usage**:

```bash
# On remote server: pass hostname so script shows correct ssh/test hints
sudo ./scripts/harden_server.sh your-server.com

# On same machine (e.g. local VM): hostname defaults to localhost
sudo ./scripts/harden_server.sh
```

**What it does**:

- Disables root login and password authentication (SSH keys only)
- Hardens SSH (strong ciphers, limited auth attempts)
- Installs and enables fail2ban
- Enables UFW firewall (SSH, HTTP, HTTPS)
- Configures unattended security updates
- Backs up SSH config before changes; prompts before restart

**Pre-requisites**: SSH key authentication must be working before running. Script checks for `~/.ssh/authorized_keys` and warns if missing.

**Full guide**: See [references/HARDENING.md](../references/HARDENING.md) for verification, rollback, troubleshooting, and optional hardening steps.

## Setup Instructions

1. **Copy scripts to your project**:

   ```bash
   mkdir -p scripts
   cp skills/deployment/scripts/* scripts/
   chmod +x scripts/*.sh
   ```

2. **Configure environment variables** in `.env`:

   ```bash
   DOMAIN=yourdomain.com
   SECRET_KEY=your-secret-key
   DB_TYPE=postgresql
   DB_NAME=your_db
   DB_USER=your_user
   DB_PASSWORD=your_password
   DEPLOYMENT_MODE=production  # or 'local'
   ```

3. **Customize scripts for your framework**:

   - Update database commands for Django/Rails/Node.js
   - Modify service names in Docker Compose checks
   - Adjust file paths and commands

4. **Update docker-compose.yml** if needed:

   - Ensure service names match what's checked in scripts
   - Add health checks to services
   - Configure proper restart policies

5. **Test in development**:

   ```bash
   # Test first-time deployment
   ./scripts/deploy_first_time.sh

   # Test verification
   ./scripts/verify_deployment.sh

   # Test backup
   ./scripts/backup_db.sh
   ```

## Integration with CI/CD

These scripts work well with GitHub Actions, GitLab CI, or other CI systems:

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [ deployment ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy
        run: ./scripts/deploy.sh
      - name: Verify
        run: ./scripts/verify_deployment.sh
```

## Makefile Integration

Add these targets to your `Makefile`:

```makefile
.PHONY: deploy deploy-first deploy-update backup-db restore-db verify

deploy:
	./scripts/deploy.sh

deploy-first:
	./scripts/deploy_first_time.sh

deploy-update:
	./scripts/deploy_update.sh

backup-db:
	./scripts/backup_db.sh

restore-db:       ## Usage: make restore-db FILE=data/db_backup_*.tar.gz
	@test -n "$(FILE)" || { echo "Usage: make restore-db FILE=backup.tar.gz"; exit 1; }
	./scripts/restore_db.sh "$(FILE)"

verify:
	./scripts/verify_deployment.sh
```

## Troubleshooting

### Scripts fail with "command not found"

- Ensure scripts are executable: `chmod +x scripts/*.sh`
- Check that Docker and Docker Compose are installed

### Database backup fails

- Verify database environment variables in `.env`
- Check that database container is running
- Ensure database user has backup permissions

### Change detection doesn't work

- Scripts fall back to interactive prompts if git history is unavailable
- Check that you're on the correct branch with recent commits

### Services don't start

- Check Docker Compose configuration
- Verify environment variables are loaded
- Review service logs: `docker compose logs`

### SCSS/CSS not compiled in production

- **Cause**: Dependency rebuild ran but static block was skipped (e.g. change detection missed SCSS files).
- **Fix**: Run manually: `docker compose exec -T web python manage.py compile_scss --style compressed && docker compose exec -T web python manage.py collectstatic --noinput`
- **Prevention**: Ensure your deploy script sets `HAS_STATIC=true` when `HAS_DEPENDENCIES=true` (generic scripts do this).

## Examples by Framework

### Django

```bash
# In deploy_update.sh, replace migration commands:
$DOCKER_COMPOSE exec -T web python manage.py migrate

# Static files:
$DOCKER_COMPOSE exec -T web python manage.py collectstatic --noinput
```

### Rails

```bash
# Migrations:
$DOCKER_COMPOSE exec -T web rails db:migrate

# Assets:
$DOCKER_COMPOSE exec -T web rails assets:precompile
```

### Node.js (Express)

```bash
# If using migrations:
$DOCKER_COMPOSE exec -T web npm run migrate

# Static files (if applicable):
$DOCKER_COMPOSE exec -T web npm run build
```
