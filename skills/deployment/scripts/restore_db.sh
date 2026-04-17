#!/bin/bash

# Generic database restore script
# Restores from a compressed SQL dump created by backup_db.sh
# Usage: ./scripts/restore_db.sh <backup_file> [--yes|-y]
#
# Non-interactive: DEPLOY_NON_INTERACTIVE=1 or --yes/-y (skips confirmation prompt)
#
# Backup filename convention (produced by backup_db.sh):
#   data/db_backup_YYYYMMDD_HHMMSS_<commit-sha>.sql.tar.gz

set -e

# Parse --yes/-y for non-interactive mode
NON_INTERACTIVE=false
BACKUP_FILE=""
for arg in "$@"; do
    case "$arg" in
        --yes|-y) NON_INTERACTIVE=true ;;
        *)        [ -z "$BACKUP_FILE" ] && BACKUP_FILE="$arg" ;;
    esac
done
if [ "$DEPLOY_NON_INTERACTIVE" = "1" ] || [ "$DEPLOY_NON_INTERACTIVE" = "true" ]; then
    NON_INTERACTIVE=true
fi

# Determine project root (supports global skill usage)
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
else
    echo "Warning: Could not determine project root. Using current directory."
fi
PROJECT_ROOT="$PWD"

ENV_FILE="$PROJECT_ROOT/.env"

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found at $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

# Database defaults (customize for your project)
DB_NAME="${DB_NAME:-project_db}"
DB_USER="${DB_USER:-postgres}"

# Use docker compose or docker-compose
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Require a backup file argument
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file> [--yes|-y]"
    echo ""
    echo "Available backups (newest first):"
    if [ -d "data" ]; then
        ls -lht data/db_backup_*.sql.tar.gz 2>/dev/null | head -10 || echo "  No backups found in data/"
    else
        echo "  No backups found — data/ directory does not exist"
    fi
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Check DB container is running
if ! $DOCKER_COMPOSE ps db | grep -qE "(Up|running)"; then
    echo "❌ Error: Database container is not running"
    echo "   Start it first: docker compose up -d db"
    exit 1
fi

echo "⚠️  WARNING: This will REPLACE the current database!"
echo "   Database: $DB_NAME"
echo "   Backup:   $BACKUP_FILE"

if [ "$NON_INTERACTIVE" != "true" ]; then
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

echo ""
echo "🗄️  Dropping and recreating database..."
$DOCKER_COMPOSE exec -T db psql -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" || true
$DOCKER_COMPOSE exec -T db psql -U "$DB_USER" -d postgres \
    -c "CREATE DATABASE \"$DB_NAME\";"

echo "📥 Restoring data..."

# Extract SQL from tar.gz (preferred format from backup_db.sh); fall back to plain gzip.
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

if tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" 2>/dev/null; then
    SQL_FILE=$(find "$TEMP_DIR" -name "*.sql" -type f | head -1)
    if [ -n "$SQL_FILE" ] && [ -f "$SQL_FILE" ]; then
        $DOCKER_COMPOSE exec -T db psql -U "$DB_USER" -d "$DB_NAME" < "$SQL_FILE"
    else
        echo "❌ Error: No SQL file found inside tar archive"
        exit 1
    fi
else
    # Plain gzipped SQL (non-tar format)
    gunzip -c "$BACKUP_FILE" | $DOCKER_COMPOSE exec -T db psql -U "$DB_USER" -d "$DB_NAME"
fi

echo ""
echo "✅ Database restored successfully from: $BACKUP_FILE"
echo ""
echo "Next steps:"
echo "  1. Restart services so they pick up the fresh state:"
echo "     $DOCKER_COMPOSE restart web   # plus worker/celery/search-api as applicable"
echo "  2. Verify: ./scripts/verify_deployment.sh"
