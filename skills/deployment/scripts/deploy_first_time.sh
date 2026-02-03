#!/bin/bash

# Generic First-Time Deployment Script
# Initial setup for new deployment
# Usage: ./scripts/deploy.sh (auto-detects) or ./scripts/deploy_first_time.sh [--remote user@host] [--dir /path] [--yes|-y]
#
# Non-interactive mode (skips prompts):
#   DEPLOY_NON_INTERACTIVE=1 ./scripts/deploy_first_time.sh
#   ./scripts/deploy_first_time.sh --yes

set -e

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
echo "Automated First-Time Deployment"
echo "=========================================="
echo ""

# Check if we're on deployment branch (warn if not)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$CURRENT_BRANCH" != "deployment" ] && [ "$CURRENT_BRANCH" != "production" ] && [ "$CURRENT_BRANCH" != "unknown" ]; then
    echo "⚠️  Warning: You're on branch '${CURRENT_BRANCH}', not 'deployment' or 'production'"
    echo "   Production deployments should use a dedicated branch"
    echo "   Switch with: git checkout deployment"
    if [ "$IS_INTERACTIVE" = "true" ]; then
        read -p "Continue anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Deployment cancelled"
            exit 1
        fi
    else
        echo "Non-interactive mode: proceeding..."
    fi
fi

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found at $ENV_FILE"
    echo "Please generate environment variables first"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Verify required variables (customize these for your project)
REQUIRED_VARS=("DOMAIN" "SECRET_KEY")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: Required environment variable $var is missing"
        exit 1
    fi
done

# Use docker compose or docker-compose
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "✅ Prerequisites verified"
echo ""

# Build Docker images
echo "🔨 Building Docker images..."
$DOCKER_COMPOSE build --no-cache

echo "✅ Docker images built"
echo ""

# Start services
echo "🚀 Starting services..."
$DOCKER_COMPOSE up -d

echo "✅ Services started"
echo ""

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check service status
echo "📊 Checking service status..."
$DOCKER_COMPOSE ps

echo ""
echo "⏳ Waiting for database to be ready (30 seconds)..."
sleep 30

# Run initial migrations (customize for your framework)
echo "🗄️  Running database migrations..."
# Example for Django:
$DOCKER_COMPOSE exec -T web python manage.py migrate && {
    echo "✅ Migrations completed"
    echo ""
} || {
    echo "⚠️  Warning: Migrations failed, continuing..."
    echo ""
}

# Collect static files (customize for your framework)
echo "📦 Collecting static files..."
# Example for Django:
$DOCKER_COMPOSE exec -T web python manage.py collectstatic --noinput && {
    echo "✅ Static files collected"
    echo ""
} || {
    echo "⚠️  Warning: Static files collection failed, continuing..."
    echo ""
}

# Initialize external services (customize for your project)
echo "📦 Initializing external services..."
# Example: Initialize MinIO bucket, create admin user, etc.
# Add your project-specific initialization here

echo ""

# Summary
echo "=========================================="
echo "✅ First-time deployment complete!"
echo "=========================================="
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Create superuser/admin account"
echo "2. Verify deployment: ./scripts/verify_deployment.sh"
echo "3. Access the application: https://${DOMAIN}"
echo ""
echo "4. Check logs: docker compose logs -f"