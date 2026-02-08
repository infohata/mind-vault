#!/bin/bash

# Generic Update/Rollout Script
# Updates existing deployment with latest code changes
# Usage: ./scripts/deploy_update.sh [--remote user@host] [--dir /path] [--yes|-y]
#
# Non-interactive mode (skips all prompts, uses safe defaults):
#   DEPLOY_NON_INTERACTIVE=1 ./scripts/deploy_update.sh
#   ./scripts/deploy_update.sh --yes

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

ENV_FILE="$PWD/.env"

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
# Aligns with Teisutis tools/deploy_update.sh: static includes CSS/JS/images and SCSS/Sass source
HAS_MIGRATIONS=false
HAS_STATIC=false
HAS_DEPENDENCIES=false

PREVIOUS_COMMIT=$(git rev-parse HEAD@{1} 2>/dev/null || echo "")

if [ -n "$PREVIOUS_COMMIT" ]; then
    # Check for migrations (customize patterns)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "(migrations/|db/migrate)"; then
        HAS_MIGRATIONS=true
    fi

    # Check for static files (CSS, JS, images, and SCSS/Sass source — compile_scss or make build-scss runs when static changed)
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "\.(css|js|png|jpg|jpeg|gif|svg|ico|scss|sass)$|/scss/|/sass/"; then
        HAS_STATIC=true
    fi

    # Check for dependencies
    if git diff "$PREVIOUS_COMMIT" HEAD --name-only | grep -qE "(requirements.*\.txt|package\.json|Gemfile|Dockerfile)"; then
        HAS_DEPENDENCIES=true
    fi
else
    # If we can't detect changes, ask user or assume minimal changes
    if [ "$IS_INTERACTIVE" = "true" ]; then
        echo "💡 Unable to auto-detect change types. Please specify:"
        read -p "Does this update include database migrations? (yes/no): " mig_confirm
        if [ "$mig_confirm" = "yes" ]; then
            HAS_MIGRATIONS=true
        fi

        read -p "Does this update include static files (CSS/JS/SCSS)? (yes/no): " static_confirm
        if [ "$static_confirm" = "yes" ]; then
            HAS_STATIC=true
        fi

        read -p "Does this update include dependency changes? (yes/no): " deps_confirm
        if [ "$deps_confirm" = "yes" ]; then
            HAS_DEPENDENCIES=true
        fi
    else
        echo "💡 Non-interactive mode: assuming no migrations or dependencies changed"
    fi
fi

# Check for .env changes
env_changed="no"
if [ "$IS_INTERACTIVE" = "true" ]; then
    read -p "Did you modify .env file? (yes/no): " env_changed
else
    echo "💡 Non-interactive mode: assuming .env was not modified"
fi

# Database backup (before migrations)
if [ "$HAS_MIGRATIONS" = "true" ]; then
    echo "💾 Creating database backup before migrations..."
    if [ -f "$SCRIPT_DIR/backup_db.sh" ]; then
        bash "$SCRIPT_DIR/backup_db.sh" || {
            echo "⚠️  Warning: Database backup failed, but continuing..."
        }
    else
        echo "⚠️  Warning: backup_db.sh not found, skipping backup"
    fi
    echo ""
fi

# Handle dependency changes
if [ "$HAS_DEPENDENCIES" = "true" ]; then
    echo "🔨 Dependencies changed - rebuilding containers..."
    echo "   This will take 5-15 minutes..."
    $DOCKER_COMPOSE build web  # Customize service names
    $DOCKER_COMPOSE up -d web
    echo "✅ Containers rebuilt"
    echo ""
fi

# Handle environment variable changes
if [ "$env_changed" = "yes" ]; then
    echo "🔄 Recreating containers to pick up .env changes..."
    $DOCKER_COMPOSE up -d --force-recreate web  # Customize service names
    echo "✅ Containers recreated"
    echo ""
fi

# Run migrations
if [ "$HAS_MIGRATIONS" = "true" ]; then
    echo "🗄️  Running database migrations..."
    # Customize for your framework
    # Django example:
    $DOCKER_COMPOSE exec -T web python manage.py migrate || {
        echo "❌ Error: Migrations failed"
        echo "   Database backup from before migrations is available"
        exit 1
    }
    echo "✅ Migrations completed"
    echo ""
fi

# Build theme from SCSS/Sass when static changed (then collectstatic)
# Try host make build-scss first, then Django compile_scss in container (e.g. Teisutis) — one will typically apply
if [ "$HAS_STATIC" = "true" ]; then
    echo "🎨 Building theme (SCSS/Sass if present)..."
    if [ -f "Makefile" ] && grep -q "build-scss" Makefile 2>/dev/null; then
        make build-scss || { echo "   (make build-scss skipped or failed)" ; }
    fi
    if $DOCKER_COMPOSE exec -T web python manage.py compile_scss --style compressed 2>/dev/null; then
        echo "   SCSS compiled (Django compile_scss)"
    fi
    echo "📦 Collecting static files..."
    # Customize for your framework
    # Django example:
    $DOCKER_COMPOSE exec -T web python manage.py collectstatic --noinput
    echo "✅ Static files collected"
    echo ""
fi

# Restart services (for code changes)
SERVICES_RESTARTED=false
if [ "$HAS_DEPENDENCIES" != "true" ] && [ "$env_changed" != "yes" ]; then
    echo "🔄 Restarting services to pick up code changes..."
    $DOCKER_COMPOSE restart web  # Customize service names
    echo "✅ Services restarted"
    SERVICES_RESTARTED=true
    echo ""
fi

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
    echo "  ✅ Database migrations applied"
fi
if [ "$HAS_STATIC" = "true" ]; then
    echo "  ✅ Static files collected"
fi
if [ "$HAS_DEPENDENCIES" = "true" ]; then
    echo "  ✅ Containers rebuilt"
fi
if [ "$env_changed" = "yes" ]; then
    echo "  ✅ Containers recreated (env changes)"
fi
if [ "$SERVICES_RESTARTED" = "true" ]; then
    echo "  ✅ Services restarted"
fi
echo ""
echo "🔍 Check logs: docker compose logs -f web"