#!/bin/bash

# Generic Database Backup Script
# Creates a compressed SQL dump with timestamp
# Supports PostgreSQL, MySQL, and SQLite
# Usage: ./scripts/backup_db.sh

set -e

# Determine project root (supports global skill usage)
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
else
    echo "Warning: Could not determine project root. Using current directory."
    echo "Set PROJECT_ROOT environment variable if needed."
fi

# Load environment variables from .env
if [ ! -f .env ]; then
    echo "Error: .env file not found in project root"
    exit 1
fi

# Source .env file
export $(grep -v '^#' .env | grep -v '^$' | xargs)

# Database configuration (customize these variable names)
DB_NAME="${DB_NAME:-myapp_db}"
DB_USER="${DB_USER:-myapp_user}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_TYPE="${DB_TYPE:-postgresql}"  # postgresql, mysql, sqlite

# Create data directory if it doesn't exist
DATA_DIR="data"
mkdir -p "$DATA_DIR"

# Generate timestamp and commit hash
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BACKUP_FILE="$DATA_DIR/db_backup_${TIMESTAMP}_${COMMIT_HASH}.sql.tar.gz"

echo "Starting database backup..."
echo "Database: $DB_NAME ($DB_TYPE)"
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"

# Check if Docker container is running
if ! docker compose ps db | grep -q "Up\|running"; then
    echo "Error: Database container is not running"
    echo "Start it with: docker compose up -d db"
    exit 1
fi

# Create backup based on database type
case "$DB_TYPE" in
    postgresql)
        echo "Creating PostgreSQL backup..."
        TEMP_SQL="/tmp/db_backup_${TIMESTAMP}.sql"
        docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists > "$TEMP_SQL"
        tar czf "$BACKUP_FILE" -C /tmp "db_backup_${TIMESTAMP}.sql"
        rm -f "$TEMP_SQL"
        ;;

    mysql)
        echo "Creating MySQL backup..."
        TEMP_SQL="/tmp/db_backup_${TIMESTAMP}.sql"
        docker compose exec -T db mysqldump -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" --add-drop-database --add-drop-table > "$TEMP_SQL"
        tar czf "$BACKUP_FILE" -C /tmp "db_backup_${TIMESTAMP}.sql"
        rm -f "$TEMP_SQL"
        ;;

    sqlite)
        echo "Creating SQLite backup..."
        # For SQLite, just copy the file (assuming it's in a volume)
        docker compose exec -T db cp "/app/db.sqlite3" "/tmp/db_backup_${TIMESTAMP}.sqlite3" 2>/dev/null || \
        cp "db/db.sqlite3" "/tmp/db_backup_${TIMESTAMP}.sqlite3" 2>/dev/null || \
        echo "Warning: Could not find SQLite file. Customize the path in backup_db.sh"
        if [ -f "/tmp/db_backup_${TIMESTAMP}.sqlite3" ]; then
            tar czf "$BACKUP_FILE" -C /tmp "db_backup_${TIMESTAMP}.sqlite3"
            rm -f "/tmp/db_backup_${TIMESTAMP}.sqlite3"
        else
            echo "Error: SQLite file not found"
            exit 1
        fi
        ;;

    *)
        echo "Error: Unsupported database type: $DB_TYPE"
        echo "Supported: postgresql, mysql, sqlite"
        exit 1
        ;;
esac

# Verify backup was created
if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✓ Backup created successfully: $BACKUP_FILE"
    echo "  Size: $BACKUP_SIZE"
    echo "  Commit: $COMMIT_HASH"
else
    echo "Error: Backup file was not created or is empty"
    exit 1
fi