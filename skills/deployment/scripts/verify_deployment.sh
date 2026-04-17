#!/bin/bash

# Generic Deployment Verification Script
# Verifies that deployment is successful and all services are healthy
# Usage: ./scripts/verify_deployment.sh

# Don't use set -e here - we want to check all services and show complete report
set +e

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
echo "Deployment Verification"
echo "=========================================="
echo ""

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "⚠️  Warning: .env file not found, using defaults"
    DOMAIN="localhost"
fi

DOMAIN=${DOMAIN:-localhost}

# Use docker compose or docker-compose
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    exit 1
fi

ERRORS=0
WARNINGS=0

# Function to check service
check_service() {
    local service=$1
    if $DOCKER_COMPOSE ps | grep -qE "$service.*(Up|running)"; then
        echo "✅ $service: Running"
        return 0
    else
        echo "❌ $service: Not running"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check endpoint
check_endpoint() {
    local url=$1
    local description=$2
    if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200\|301\|302"; then
        echo "✅ $description: Accessible"
        return 0
    else
        echo "⚠️  $description: Not accessible"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

echo "🔍 Checking services..."
echo ""

# Check core services (customize these for your project)
SERVICES=("web" "db")  # Add more services as needed: nginx, redis, etc.

for service in "${SERVICES[@]}"; do
    check_service "$service"
done

echo ""
echo "🗄️  Checking database connectivity..."

# Database connectivity check (customize for your database)
case "${DB_TYPE:-postgresql}" in
    postgresql)
        if $DOCKER_COMPOSE exec -T db pg_isready -U "${DB_USER:-user}" -d "${DB_NAME:-db}" > /dev/null 2>&1; then
            echo "✅ Database: Connected"
        else
            echo "❌ Database: Connection failed"
            ERRORS=$((ERRORS + 1))
        fi
        ;;

    mysql)
        if $DOCKER_COMPOSE exec -T db mysql -u "${DB_USER:-user}" -p"${DB_PASSWORD:-password}" -e "SELECT 1" "${DB_NAME:-db}" > /dev/null 2>&1; then
            echo "✅ Database: Connected"
        else
            echo "❌ Database: Connection failed"
            ERRORS=$((ERRORS + 1))
        fi
        ;;

    *)
        echo "⚠️  Database check: Not implemented for ${DB_TYPE:-unknown} database"
        WARNINGS=$((WARNINGS + 1))
        ;;
esac

echo ""

# Check HTTP endpoints (customize URLs for your application)
echo "🌐 Checking HTTP endpoints..."

if [ "${DEPLOYMENT_MODE:-local}" = "production" ]; then
    # In production, HTTP should redirect to HTTPS (301/302) — a 200 indicates misconfiguration.
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" 2>/dev/null)
    if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "✅ HTTP: Redirecting to HTTPS (${HTTP_CODE})"
    else
        echo "⚠️  HTTP: Expected redirect, got ${HTTP_CODE} (may be normal if DNS not propagated)"
        WARNINGS=$((WARNINGS + 1))
    fi

    if curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN" 2>/dev/null | grep -q "200\|301\|302"; then
        echo "✅ HTTPS endpoint: Accessible"
    else
        echo "⚠️  HTTPS endpoint: Not accessible (SSL certificates may not be ready)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    # Local/dev mode: just confirm HTTP responds at all.
    check_endpoint "http://$DOMAIN" "HTTP endpoint"
fi

# Check API endpoint (customize path for your API)
if curl -s -k "http://$DOMAIN/api/health" 2>/dev/null | grep -q "ok\|healthy"; then
    echo "✅ API health check: OK"
else
    echo "⚠️  API health check: Not available"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# Check SSL certificates if in production
if [ "${DEPLOYMENT_MODE:-local}" = "production" ]; then
    echo "🔒 Checking SSL certificates..."
    if $DOCKER_COMPOSE ps | grep -q "certbot"; then
        if $DOCKER_COMPOSE exec -T certbot certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
            echo "✅ SSL certificates: Found"
            # Extract expiry so the operator can spot certs that are about to lapse.
            CERT_EXPIRY=$($DOCKER_COMPOSE exec -T certbot certbot certificates 2>/dev/null \
                | grep -A 2 "$DOMAIN" | grep "Expiry Date" | awk '{print $3, $4, $5}' || echo "")
            if [ -n "$CERT_EXPIRY" ]; then
                echo "   Expiry: $CERT_EXPIRY"
            fi
        else
            echo "⚠️  SSL certificates: Not found yet (may take a few minutes)"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "⚠️  SSL certificates: Certbot service not running"
        WARNINGS=$((WARNINGS + 1))
    fi
    echo ""
fi

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All checks passed! Deployment is healthy."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  Deployment is running with $WARNINGS warning(s)"
    echo "   Most warnings are normal during initial deployment"
    exit 0
else
    echo "❌ Deployment has $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check service logs: docker compose logs"
    echo "2. Check service status: docker compose ps"
    echo "3. Review deployment documentation"
    exit 1
fi