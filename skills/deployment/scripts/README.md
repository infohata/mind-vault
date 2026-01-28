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

All scripts support remote deployment via SSH with explicit user confirmation:

```bash
# Deploy to remote server with confirmation prompts
./scripts/deploy.sh --remote user@production-server.com --dir /opt/myapp

# Use environment variables
REMOTE_HOST=user@staging.example.com REMOTE_DIR=/var/www/app ./scripts/deploy.sh

# Direct script execution on remote
./scripts/deploy_update.sh --remote user@host --dir /path
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
# Deploy to remote server (auto-detects deployment type)
./scripts/deploy.sh --remote user@production.com --dir /opt/myapp

# Update remote deployment
./scripts/deploy_update.sh --remote user@staging.com --dir /var/www/app

# Use environment variables
REMOTE_HOST=deploy@server.com REMOTE_DIR=/opt/project ./scripts/deploy.sh

# Default directory (auto-detected from git repo name)
/opt/your-project-name/
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
- Collects static files
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
- Auto-detects change types (migrations, static files, dependencies)
- Creates database backups before migrations
- Rebuilds containers if dependencies changed
- Recreates containers if environment variables changed
- Runs migrations and collects static files as needed
- Restarts services for code changes

**Change detection patterns** (customize these regex patterns):
- Migrations: `migrations/|db/migrate`
- Static files: `\.(css|js|png|jpg|jpeg|gif|svg|ico)$`
- Dependencies: `requirements.*\.txt|package\.json|Gemfile|Dockerfile`

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
.PHONY: deploy deploy-first deploy-update backup-db verify

deploy:
	./scripts/deploy.sh

deploy-first:
	./scripts/deploy_first_time.sh

deploy-update:
	./scripts/deploy_update.sh

backup-db:
	./scripts/backup_db.sh

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