#!/bin/bash

# Generic Deployment Wrapper Script
# Auto-detects whether this is first-time deployment or update
# Supports both local and remote deployment
# Usage: ./scripts/deploy.sh [--remote user@host] [--dir /path]

# Store script directory before changing directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse command line arguments
REMOTE_HOST=""
REMOTE_DIR="/opt/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--remote user@host] [--dir /remote/path]"
            exit 1
            ;;
    esac
done

# Determine project root (supports global skill usage)
if [ -n "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
else
    echo "Warning: Could not determine project root. Using current directory."
    echo "Set PROJECT_ROOT environment variable if needed."
fi

# Check if Docker Compose is available
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Error: Docker Compose is not installed"
    exit 1
fi

# Function to execute commands (local or remote) with confirmation for remote
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ -n "$REMOTE_HOST" ]; then
        echo "🔗 Remote operation: $description"
        echo "   Host: $REMOTE_HOST"
        echo "   Directory: $REMOTE_DIR"
        echo "   Command: $cmd"
        echo ""
        
        # Require explicit confirmation for remote operations
        if [ -t 0 ]; then
            read -p "⚠️  Execute this remotely? (yes/no): " confirm
            if [ "$confirm" != "yes" ]; then
                echo "Remote operation cancelled by user"
                exit 1
            fi
        else
            echo "⚠️  Non-interactive mode: proceeding with remote execution"
        fi
        
        ssh "$REMOTE_HOST" "cd '$REMOTE_DIR' && $cmd"
    else
        echo "💻 $description"
        eval "$cmd"
    fi
}

# Check if services are already running
SERVICES_RUNNING=false
if execute_command "$DOCKER_COMPOSE ps 2>/dev/null | grep -q 'Up\|running' && echo 'true' || echo 'false'" "Checking service status" | grep -q "true"; then
    SERVICES_RUNNING=true
fi

# Determine deployment type
if [ "$SERVICES_RUNNING" = "true" ]; then
    echo "📋 Detected: Existing deployment (services are running)"
    echo "   Using update script..."
    echo ""
    if [ -n "$REMOTE_HOST" ]; then
        # Execute deployment remotely without contaminating project repo
        REMOTE_SCRIPT_NAME="deploy_update_$(date +%s)_$$.sh"
        REMOTE_SCRIPT_PATH="/tmp/$REMOTE_SCRIPT_NAME"
        
        # Copy script to temporary location and execute with project directory
        scp "$SCRIPT_DIR/deploy_update.sh" "$REMOTE_HOST:$REMOTE_SCRIPT_PATH"
        execute_command "chmod +x '$REMOTE_SCRIPT_PATH' && PROJECT_ROOT='$REMOTE_DIR' '$REMOTE_SCRIPT_PATH'" "Executing remote deployment update"
        
        # Clean up remote temporary script
        ssh "$REMOTE_HOST" "rm -f '$REMOTE_SCRIPT_PATH'" 2>/dev/null || true
    else
        exec "$SCRIPT_DIR/deploy_update.sh"
    fi
else
    echo "📋 Detected: First-time deployment (no services running)"
    echo "   Using first-time deployment script..."
    echo ""
    if [ -n "$REMOTE_HOST" ]; then
        # Execute deployment remotely without contaminating project repo
        REMOTE_SCRIPT_NAME="deploy_first_time_$(date +%s)_$$.sh"
        REMOTE_SCRIPT_PATH="/tmp/$REMOTE_SCRIPT_NAME"
        
        # Copy script to temporary location and execute with project directory
        scp "$SCRIPT_DIR/deploy_first_time.sh" "$REMOTE_HOST:$REMOTE_SCRIPT_PATH"
        execute_command "chmod +x '$REMOTE_SCRIPT_PATH' && PROJECT_ROOT='$REMOTE_DIR' '$REMOTE_SCRIPT_PATH'" "Executing remote first-time deployment"
        
        # Clean up remote temporary script
        ssh "$REMOTE_HOST" "rm -f '$REMOTE_SCRIPT_PATH'" 2>/dev/null || true
    else
        exec "$SCRIPT_DIR/deploy_first_time.sh"
    fi
fi