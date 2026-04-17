#!/bin/bash

# Generic Update/Rollout Script
# Updates existing deployment with latest code changes
# Usage: ./scripts/deploy_update.sh [--remote user@host] [--dir /path] [--yes|-y]
#
# Non-interactive mode (skips all prompts, uses safe defaults):
#   DEPLOY_NON_INTERACTIVE=1 ./scripts/deploy_update.sh
#   ./scripts/deploy_update.sh --yes
#
# Force recreate services to pick up .env changes (no git diff available for .env):
#   DEPLOY_RECREATE_ENV=1 ./scripts/deploy_update.sh

set -e

# Get script directory (for finding other scripts)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse command line arguments (for direct remote execution)
REMOTE_HOST=""
REMOTE_DIR=""
NON_INTERACTIVE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --dir)
            REMOTE_DIR="$2"
            shift 2
            ;;
        --yes|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done
if [ "$DEPLOY_NON_INTERACTIVE" = "1" ] || [ "$DEPLOY_NON_INTERACTIVE" = "true" ]; then
    NON_INTERACTIVE=true
fi
IS_INTERACTIVE=false
if [ "$NON_INTERACTIVE" != "true" ] && [ -t 0 ]; then
    IS_INTERACTIVE=true
fi

# Determine project root (supports global skill usage)
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
else
    echo "Warning: Could not determine project root. Using current directory."
    echo "Set PROJECT_ROOT environment variable if needed."
fi
PROJECT_ROOT="$PWD"

ENV_FILE="$PROJECT_ROOT/.env"

echo "=========================================="
echo "Deployment Update"
echo "=========================================="
echo ""

# Check if we're on deployment branch (warn if not)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$CURRENT_BRANCH" != "deployment" ] && [ "$CURRENT_BRANCH" != "production" ] && [ "$CURRENT_BRANCH" != "unknown" ]; then
    echo "⚠️  Warning: You're on branch '${CURRENT_BRANCH}', not 'deployment' or 'production'"
    echo "   Production deployments should use a dedicated branch"
    if [ "$IS_INTERACTIVE" = "true" ]; then
        read -p "Continue anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Update cancelled"
            exit 1
        fi
    else
        echo "❌ Error: Non-interactive mode requires deployment branch"
        exit 1
    fi
fi

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Use docker compose or docker-compose
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Check if services are running
if ! $DOCKER_COMPOSE ps | grep -q "Up\|running"; then
    echo "❌ Error: Services are not running"
    echo "   This script is for updating existing deployments."
    echo "   For first-time deployment, use: ./scripts/deploy_first_time.sh"
    exit 1
fi

echo "✅ Prerequisites verified"
echo ""

# Pull latest code
echo "📥 Pulling latest code..."
git pull origin "${CURRENT_BRANCH:-deployment}" || {
    echo "⚠️  Warning: Failed to pull latest code"
    if [ "$IS_INTERACTIVE" = "true" ]; then
        read -p "Continue with current code? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Update cancelled"
            exit 1
        fi
    else
        echo "❌ Error: Failed to pull latest code in non-interactive mode"
        exit 1
    fi
}

echo "✅ Code updated"
echo ""

# Detect change type (customize file patterns for your project)
HAS_MIGRATIONS=false
HAS_STATIC=false
HAS_DEPENDENCIES=false
HAS_NGINX_CONFIG=false
HAS_TRANSLATIONS=false

# Get the commit hash before pull — prefer persistent state (survives crashes/partial deploys).
# Falls back to git reflog if no state file (e.g. first update after initial deploy).
# The state file is written at the end of a successful run, so a crashed rerun
# still compares against the last good deploy, not the broken in-progress one.
if [ -f "$PROJECT_ROOT/.deploy_commit_state" ]; then
    PREVIOUS_COMMIT=$(cat "$PROJECT_ROOT/.deploy_commit_state")
    echo "🔍 Comparing changes against last successful deploy state..."
else
    PREVIOUS_COMMIT=$(git rev-parse HEAD@{1} 2>/dev/null || echo "")
fi

if [ -n "$PREVIOUS_COMMIT" ]; then
    # Check for migrations (customize patterns for non-Django frameworks)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "(migrations/|db/migrate)"; then
        HAS_MIGRATIONS=true
    fi

    # Check for static files (CSS, JS, images, and SCSS/Sass source)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "\.(css|js|png|jpg|jpeg|gif|svg|ico|scss|sass)$|/scss/|/sass/"; then
        HAS_STATIC=true
    fi

    # Check for dependencies
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "(requirements.*\.txt|package\.json|Gemfile|^Dockerfile$)"; then
        HAS_DEPENDENCIES=true
    fi

    # Check for nginx / certbot config changes (config files, Dockerfile, entrypoint scripts)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "nginx/.*\.(conf|sh)|nginx/Dockerfile"; then
        HAS_NGINX_CONFIG=true
    fi

    # Check for translation file changes (.po files under any locale/ directory)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "locale/.*\.po"; then
        HAS_TRANSLATIONS=true
    fi

    # When dependencies changed:
    # - always run static (new code may have SCSS changes the file-pattern grep missed)
    # - always run migrations (new packages may ship their own, e.g. django-two-factor-auth's otp_* migrations)
    if [ "$HAS_DEPENDENCIES" = "true" ]; then
        HAS_STATIC=true
        HAS_MIGRATIONS=true
    fi
else
    # Can't auto-detect — ask user or exit in non-interactive mode
    if [ "$IS_INTERACTIVE" = "true" ]; then
        echo "💡 Unable to auto-detect change types. Please specify:"
        read -p "Does this update include database migrations? (yes/no): " mig_confirm
        [ "$mig_confirm" = "yes" ] && HAS_MIGRATIONS=true

        read -p "Does this update include static files (CSS/JS/SCSS)? (yes/no): " static_confirm
        [ "$static_confirm" = "yes" ] && HAS_STATIC=true

        read -p "Does this update include dependency changes? (yes/no): " deps_confirm
        if [ "$deps_confirm" = "yes" ]; then
            HAS_DEPENDENCIES=true
            HAS_STATIC=true
            HAS_MIGRATIONS=true
        fi

        read -p "Does this update include nginx configuration changes? (yes/no): " nginx_confirm
        [ "$nginx_confirm" = "yes" ] && HAS_NGINX_CONFIG=true

        read -p "Does this update include translation file changes? (yes/no): " trans_confirm
        [ "$trans_confirm" = "yes" ] && HAS_TRANSLATIONS=true
    else
        echo "❌ Error: Unable to auto-detect change types in non-interactive mode"
        echo "   Ensure git reflog is available or .deploy_commit_state exists"
        exit 1
    fi
fi

# Check for .env changes (user-driven; or force via DEPLOY_RECREATE_ENV=1)
env_changed="no"
if [ -n "$DEPLOY_RECREATE_ENV" ] && [ "$DEPLOY_RECREATE_ENV" != "0" ]; then
    env_changed="yes"
    echo "🔄 DEPLOY_RECREATE_ENV set — will force-recreate services"
elif [ "$IS_INTERACTIVE" = "true" ]; then
    read -p "Did you modify .env file? (yes/no): " env_changed
else
    echo "💡 Non-interactive mode: assuming .env was not modified"
    echo "   (set DEPLOY_RECREATE_ENV=1 to force-recreate services)"
fi

# Database backup (before migrations) — track success for accurate summary
PRE_MIGRATION_BACKUP_SUCCESS=false
if [ "$HAS_MIGRATIONS" = "true" ]; then
    echo "💾 Creating database backup before migrations..."
    if [ -f "$SCRIPT_DIR/backup_db.sh" ]; then
        if bash "$SCRIPT_DIR/backup_db.sh"; then
            PRE_MIGRATION_BACKUP_SUCCESS=true
        else
            echo "⚠️  Warning: Database backup failed, but continuing..."
        fi
    else
        echo "⚠️  Warning: backup_db.sh not found, skipping backup"
    fi
    echo ""
fi

# Handle dependency changes (requires rebuild)
if [ "$HAS_DEPENDENCIES" = "true" ]; then
    echo "🔨 Dependencies changed - rebuilding containers..."
    echo "   This may take several minutes depending on project size."
    $DOCKER_COMPOSE build web  # Customize: add worker/celery/other services as needed
    $DOCKER_COMPOSE up -d web  # Customize: add worker/celery/other services as needed
    echo "✅ Containers rebuilt"
    echo ""
fi

# Handle environment variable changes (requires recreate to pick up new env)
if [ "$env_changed" = "yes" ]; then
    echo "🔄 Recreating containers to pick up .env changes..."
    $DOCKER_COMPOSE up -d --force-recreate web  # Customize: add worker/celery/other services
    echo "✅ Containers recreated"
    echo ""
fi

# Run migrations (if needed) — back up again after success as a clean rollback point
POST_MIGRATION_BACKUP_SUCCESS=false
if [ "$HAS_MIGRATIONS" = "true" ]; then
    echo "🗄️  Running database migrations..."
    # Customize for your framework.
    # Django single-tenant (default):
    $DOCKER_COMPOSE exec -T web python manage.py migrate || {
        echo "❌ Error: Migrations failed"
        echo "   Database backup from before migrations is available in data/"
        exit 1
    }
    # django-tenants (uncomment if using):
    # $DOCKER_COMPOSE exec -T web python manage.py migrate_schemas --shared
    # $DOCKER_COMPOSE exec -T web python manage.py migrate_schemas
    echo "✅ Migrations completed"
    echo ""

    echo "💾 Creating database backup after successful migrations..."
    if [ -f "$SCRIPT_DIR/backup_db.sh" ]; then
        if bash "$SCRIPT_DIR/backup_db.sh"; then
            POST_MIGRATION_BACKUP_SUCCESS=true
        else
            echo "⚠️  Warning: Post-migration backup failed"
        fi
    fi
    echo ""
fi

# Compile translation messages (if .po files changed)
SERVICES_RESTARTED=false
if [ "$HAS_TRANSLATIONS" = "true" ]; then
    echo "🌐 Compiling translation messages..."
    $DOCKER_COMPOSE exec -T web python manage.py compilemessages || {
        echo "⚠️  Warning: Translation compilation failed, continuing..."
    }
    echo "✅ Translation messages compiled"
    # Restart so the newly compiled .mo files are loaded — Django caches the catalogue at startup.
    # Required especially when HAS_DEPENDENCIES=true: containers were started before compilemessages ran.
    echo "🔄 Restarting services to load compiled translations..."
    $DOCKER_COMPOSE restart web  # Customize: add worker/celery if they use translations
    SERVICES_RESTARTED=true
    echo "✅ Services restarted after translation compile"
    echo ""
fi

# Build theme from SCSS/Sass when static changed (then collectstatic)
if [ "$HAS_STATIC" = "true" ]; then
    echo "🎨 Building theme (SCSS/Sass if present)..."
    if [ -f "Makefile" ] && grep -q "build-scss" Makefile 2>/dev/null; then
        make build-scss || { echo "   (make build-scss skipped or failed)"; }
    fi
    if $DOCKER_COMPOSE exec -T web python manage.py compile_scss --style compressed 2>/dev/null; then
        echo "   SCSS compiled (Django compile_scss)"
    fi
    echo "📦 Collecting static files..."
    # Customize for your framework. Django example:
    $DOCKER_COMPOSE exec -T web python manage.py collectstatic --noinput
    echo "✅ Static files collected"
    echo ""
fi

# Restart services for code changes
# Skip if we already restarted for translations, deps rebuild already up -d'd, or env change already force-recreated
if [ "$HAS_DEPENDENCIES" != "true" ] && [ "$env_changed" != "yes" ] && [ "$SERVICES_RESTARTED" != "true" ]; then
    echo "🔄 Restarting services to pick up code changes..."
    $DOCKER_COMPOSE restart web  # Customize: add worker/celery/other services
    echo "✅ Services restarted"
    SERVICES_RESTARTED=true
    echo ""
fi

# Rebuild nginx (if nginx config or entrypoints changed)
if [ "$HAS_NGINX_CONFIG" = "true" ]; then
    echo "🔨 Rebuilding nginx (configuration changed)..."
    $DOCKER_COMPOSE build nginx
    $DOCKER_COMPOSE up -d nginx
    # Restart certbot if its entrypoint script changed (typical volume-mount pattern).
    if [ -n "$PREVIOUS_COMMIT" ] && \
       git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -q "nginx/certbot-entrypoint.sh"; then
        echo "🔄 Restarting certbot (entrypoint script changed)..."
        $DOCKER_COMPOSE restart certbot
    fi
    echo "✅ Nginx rebuilt and restarted"
    echo ""
fi

# Record successful deployment state — so a crashed rerun doesn't skip migrations
# by diffing against a bad HEAD@{1}.
git rev-parse HEAD > "$PROJECT_ROOT/.deploy_commit_state"

# Verify deployment
echo "📊 Verifying deployment..."
$DOCKER_COMPOSE ps

echo ""
echo "=========================================="
echo "✅ Update complete!"
echo "=========================================="
echo ""
echo "📋 Summary:"
echo ""
if [ "$HAS_MIGRATIONS" = "true" ]; then
    echo "  ✅ Migrations applied"
    if [ "$PRE_MIGRATION_BACKUP_SUCCESS" = "true" ] && [ "$POST_MIGRATION_BACKUP_SUCCESS" = "true" ]; then
        echo "  ✅ Database backups created (before and after migrations)"
    elif [ "$PRE_MIGRATION_BACKUP_SUCCESS" = "true" ]; then
        echo "  ⚠️  Pre-migration backup created, post-migration backup failed or skipped"
    elif [ "$POST_MIGRATION_BACKUP_SUCCESS" = "true" ]; then
        echo "  ⚠️  Post-migration backup created, pre-migration backup failed or skipped"
    else
        echo "  ⚠️  Database backups failed or were skipped (check warnings above)"
    fi
fi
if [ "$HAS_TRANSLATIONS" = "true" ]; then
    echo "  ✅ Translation messages compiled"
fi
if [ "$HAS_STATIC" = "true" ]; then
    echo "  ✅ Static files collected"
fi
if [ "$HAS_DEPENDENCIES" = "true" ]; then
    echo "  ✅ Containers rebuilt"
fi
if [ "$HAS_NGINX_CONFIG" = "true" ]; then
    echo "  ✅ Nginx rebuilt (config updated)"
fi
if [ "$env_changed" = "yes" ]; then
    echo "  ✅ Containers recreated (env changes)"
fi
if [ "$SERVICES_RESTARTED" = "true" ]; then
    echo "  ✅ Services restarted"
fi
echo ""
echo "🔍 Check logs: docker compose logs -f web"
