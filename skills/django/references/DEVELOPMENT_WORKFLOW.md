# Development Workflow and Configuration

**Environment management, commit processes, and development tooling patterns**

## Environment Variables Configuration

**CRITICAL**: All configuration must come from environment variables, never hardcoded values.

### Access Patterns

**✅ GOOD**: Use `os.getenv()` with sensible defaults
```python
import os
from dotenv import load_dotenv

load_dotenv()  # Load .env file in development

# Boolean values
DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'

# Integer values
MAX_PROMPT_LENGTH = int(os.getenv('MAX_PROMPT_LENGTH', '50000'))
DB_PORT = int(os.getenv('DB_PORT', '5432'))

# List values (comma-separated)
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Optional lists
ALLOWED_ORIGINS = (
    os.getenv('ALLOWED_ORIGINS', '').split(',')
    if os.getenv('ALLOWED_ORIGINS')
    else None
)
```

**❌ BAD**: Hardcoded configuration
```python
DEBUG = True  # ❌ Never hardcode
DB_NAME = 'production_db'  # ❌ Never hardcode
MAX_PROMPT_LENGTH = 50000  # ❌ Never hardcode
```

### Required Variables Validation

**✅ GOOD**: Validate critical variables at startup
```python
SECRET_KEY = os.getenv('SECRET_KEY')
if not SECRET_KEY:
    raise ValueError("SECRET_KEY environment variable must be set")

DATABASE_URL = os.getenv('DATABASE_URL')
if not DATABASE_URL:
    raise ValueError("DATABASE_URL must be configured")
```

**❌ BAD**: Silent failures on missing variables
```python
SECRET_KEY = os.getenv('SECRET_KEY')  # None causes runtime errors
```

### Sensitive Data Handling

**✅ GOOD**: Never log sensitive values
```python
api_key = os.getenv('API_KEY')
if api_key:
    logger.debug(f"API key configured: {api_key[:8]}...")  # Partial only
else:
    logger.warning("API key not configured")
```

**❌ BAD**: Logging sensitive data
```python
logger.info(f"API key: {api_key}")  # ❌ SECURITY RISK
```

### Environment-Specific Configuration

**Development (.env file)**:
```bash
DEBUG=True
DB_NAME=myapp_dev
ALLOWED_HOSTS=localhost,127.0.0.1
```

**Production (environment variables)**:
```bash
DEBUG=False
DB_NAME=myapp_prod
ALLOWED_HOSTS=myapp.com,www.myapp.com
```

**Feature flags**:
```python
ENABLE_NEW_FEATURE = os.getenv('ENABLE_NEW_FEATURE', 'false').lower() == 'true'
EXPERIMENTAL_API = os.getenv('EXPERIMENTAL_API', 'false').lower() == 'true'
```

### Pre-Commit Review Process

**For commit approval processes and review requirements**: See `../../rules/RULE_commit-approval.md`

## Makefile and Docker Workflow

**Use Makefiles for consistent development operations** (when applicable):

### Service Management
```bash
make start          # Start all services
make stop           # Stop all services
make restart-web    # Restart web service only
make logs           # View all service logs
make logs-web       # View web service logs only
```

### Django Operations
```bash
make migrate                    # Run database migrations
make makemigrations             # Create new migrations
make shell                      # Open Django shell
make manage ARGS="check"        # Run Django management commands
```

### Testing
```bash
make test                       # Run all tests
make test ARGS="myapp.tests"    # Run specific tests
make coverage                   # Run tests with coverage
```

### Database Operations
```bash
make backup-db                  # Create database backup
make restore-db FILE=backup.sql # Restore from backup
```

### Why Makefiles?

1. **Consistency**: Same commands across all environments
2. **Safety**: Prevents direct Docker commands that might cause issues
3. **Documentation**: Self-documenting command reference
4. **Abstraction**: Hides Docker complexity

### Development Workflow Example

```bash
# Start development environment
make start

# Set up database
make migrate

# Run tests
make test

# Check coverage
make coverage

# View logs if needed
make logs-web
```

## Docker Path Handling

**Understand volume mappings to avoid path confusion**:

### Volume Mapping Awareness
```
# Local development:
./web:/app (local web/ directory → container /app)

# Inside container: paths relative to /app
docker compose exec web tail -f logs/app.log

# From local filesystem: use web/ prefix
tail -f web/logs/app.log
```

### Common Path Mistakes

**✅ CORRECT**:
```bash
# Access logs inside container
docker compose exec web tail -f logs/app.log

# Access logs from local
tail -f web/logs/app.log

# Django commands (working dir is /app)
docker compose exec web python manage.py migrate
```

**❌ WRONG**:
```bash
# Don't use web/ prefix inside container
docker compose exec web tail -f web/logs/app.log  # Wrong!

# Don't use relative paths from host
tail -f logs/app.log  # Wrong - file doesn't exist locally
```

## Development Best Practices

- ✅ **Always use environment variables** for configuration
- ✅ **Validate required variables** at startup
- ✅ **Never log sensitive data** (keys, passwords, tokens)
- ✅ **Use Makefiles** for common operations when available
- ✅ **Understand Docker volume mappings** to avoid path confusion
- ✅ **Always review changes** before committing
- ✅ **Wait for explicit approval** before any commits
- ✅ **Use sensible defaults** for optional configuration
- ❌ **Never hardcode configuration** values
- ❌ **Never expose sensitive data** in logs or responses
- ❌ **Never commit without review** (except trivial cases)
- ❌ **Never use production values** as development defaults