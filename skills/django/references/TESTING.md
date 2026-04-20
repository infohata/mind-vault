# Testing Patterns and Best Practices

**Comprehensive testing strategies for Django applications**

## Language and Locale in Tests

**CRITICAL**: Tests that check text output (error messages, validation messages, etc.) MUST run in a consistent locale to ensure deterministic results.

### Enforce Consistent Locale

Always assert against English strings and force the English locale in tests that verify UI-facing strings, tool descriptions, or error messages. This prevents fuzzy matching failures and prevents brittle tests when running suites across different locales.

```python
from django.test import override_settings
from django.utils.translation import activate

@override_settings(LANGUAGE_CODE='en')
def test_some_ui_string(self):
    activate('en')  # Ensure the active thread uses English mapping
    response = self.client.get('/some-url/')
    self.assertContains(response, "Expected English String")
```

**✅ GOOD**: Override language code for tests checking text output
```python
from django.test import override_settings
from django.utils.translation import activate

@override_settings(LANGUAGE_CODE='en')
def test_validation_error(self):
    activate('en')  # Explicitly activate English
    response = self.client.post('/api/articles/', {})
    self.assertIn('required', response.context['form'].errors['field'][0].lower())
```

**For async/WebSocket tests**:
```python
@override_settings(LANGUAGE_CODE='en')
async def test_websocket_validation(self):
    activate('en')
    # WebSocket test code that checks error messages
```

**❌ BAD**: Tests that depend on default locale
```python
def test_validation_error(self):
    response = self.client.post('/api/articles/', {})
    # This will fail if default language produces different text!
    self.assertIn('privalomas', response.context['form'].errors['field'][0].lower())
```

**Why This Matters**:
- Project default language may change (Lithuanian, English, etc.)
- Tests become flaky when translations are updated
- Ensures consistent behavior across development environments
- Prevents false positives/negatives in CI

## External API Testing Patterns

**CRITICAL**: Tests that make real external API calls MUST be properly mocked or guarded to prevent:
- Cost overruns (paid APIs)
- Rate limiting
- Flaky tests due to network issues
- Slow test execution

### Mock API Calls in General Tests

**✅ GOOD**: Mock external API calls
```python
from unittest.mock import patch, MagicMock

@patch('requests.post')
def test_external_api_integration(self, mock_post):
    # Mock the API response
    mock_response = MagicMock()
    mock_response.json.return_value = {'choices': [{'text': 'Mocked response'}]}
    mock_post.return_value = mock_response
    
    result = self.service.call_external_api('test prompt')
    self.assertEqual(result, 'Mocked response')
```

**For complex mocking**:
```python
@patch.object(ExternalService, 'make_request')
def test_service_with_mocked_dependency(self, mock_request):
    mock_request.return_value = {'data': 'mocked'}
    
    service = ExternalService()
    result = service.process_data()
    self.assertEqual(result['data'], 'mocked')
```

### Guard Real API Tests

**✅ GOOD**: Skip real API tests by default
```python
import unittest
import os

@unittest.skipUnless(os.getenv('RUN_REAL_API_TESTS'), 
                    "Set RUN_REAL_API_TESTS=1 to run. WARNING: Consumes API quota!")
class RealAPITestCase(TestCase):
    def test_real_api_call(self):
        # Real API call - expensive!
        result = self.service.call_real_api()
        self.assertIsNotNone(result)
```

**Environment variable control**:
```bash
# Development - mocked tests only
make test

# Enable real API tests (with warning)
RUN_REAL_API_TESTS=1 python manage.py test real_api_tests
```

**❌ BAD**: Real API calls in general test suite
```python
def test_api_integration(self):
    # ❌ BAD: Consumes quota, slow, flaky
    result = self.service.call_real_api()
    self.assertIsNotNone(result)
```

## Tool Executor Testing Requirements

**For systems with AI tools or complex business logic executors**:

### Parameter Mapping Validation

**✅ GOOD**: Test parameter mapping and database persistence
```python
def test_executor_parameter_mapping(self):
    """Test tool executor correctly maps parameters to database operations."""
    executor = ToolExecutor(self.user)
    
    # Test with actual tool parameter names
    result = executor.update_article(
        article_id=self.article.id,
        category_id=self.new_category.id  # Tool parameter name
    )
    
    self.assertNotIn('error', result)
    
    # CRITICAL: Verify database was actually updated
    self.article.refresh_from_db()
    self.assertEqual(self.article.category.id, self.new_category.id)
    
    # Verify return value structure
    self.assertEqual(result['category_id'], self.new_category.id)
```

**Required test coverage**:
- [ ] Test each parameter individually (`category_id`, `scope_id`, etc.)
- [ ] Test multiple parameters together
- [ ] Verify database persistence with `refresh_from_db()`
- [ ] Verify return value contains correct data
- [ ] Test permission validation (if applicable)

**❌ BAD**: Testing return values only
```python
def test_executor_update(self):
    result = executor.update_article(article_id=1, category_id=2)
    # ❌ BAD: Only checks return value, not actual database change
    self.assertEqual(result['category_id'], 2)
```

### Permission Validation Testing

**For operations that can change ownership or scope**:

```python
def test_scope_change_permission_denied(self):
    """Test scope change fails when user lacks destination permissions."""
    # User has write access to source scope but not destination
    with self.assertRaises(PermissionDenied):
        executor.move_article_to_scope(
            article_id=self.article.id,
            new_scope_id=self.restricted_scope.id
        )
    
    # Verify database was NOT updated
    self.article.refresh_from_db()
    self.assertEqual(self.article.scope.id, self.original_scope.id)

def test_scope_change_permission_allowed(self):
    """Test scope change succeeds when user has both scope permissions."""
    result = executor.move_article_to_scope(
        article_id=self.article.id,
        new_scope_id=self.allowed_scope.id
    )
    
    self.assertNotIn('error', result)
    self.article.refresh_from_db()
    self.assertEqual(self.article.scope.id, self.allowed_scope.id)
```

## Full Test Suite Execution Strategy

**CRITICAL**: Large test suites (1000+ tests) require systematic execution to avoid wasting time on repeated failures.

### Single Comprehensive Run Strategy

**NEVER run the full test suite multiple times** during troubleshooting. Collect ALL failures in ONE run.

1. **Run once with output capture**:
```bash
# Capture all output for analysis
make test 2>&1 | tee /tmp/test_output.log
```

2. **Extract all failures systematically**:
```bash
# Count failures and errors
grep -E "^(FAILED|ERROR)" /tmp/test_output.log | wc -l

# Group by error type
grep "FAILED" /tmp/test_output.log | head -20
grep "ERROR" /tmp/test_output.log | head -20
```

3. **Identify root causes**:
- Group failures by error pattern (same exception type, same module)
- Look for infrastructure issues (middleware, database, settings)
- Check for common patterns across multiple tests

4. **Fix systematically**:
- Fix one root cause at a time
- Use targeted tests to verify fixes:
```bash
# Test specific app after fix
make test ARGS="myapp"
```

5. **Final verification**:
```bash
# Single final run after all fixes
make test 2>&1 | tee /tmp/final_test_output.log

# Verify zero failures
grep -E "^(FAILED|ERROR)" /tmp/final_test_output.log | wc -l  # Should be 0
```

### Time Management

- **Full suite**: ~10-15 minutes (1000+ tests)
- **Targeted module**: ~1-2 minutes
- **Strategy**: Collect failures → Fix root causes → Verify targeted → Final full run

### Common Failure Patterns

**Middleware errors**:
```
MessageFailure: You cannot add messages without django.contrib.messages.middleware.MessageMiddleware
```
**Fix**: Add MessageMiddleware to test settings or mock messages framework.

**URL routing failures**:
```
AssertionError: 404 != 200
```
**Fix**: Use TenantTestCase for multi-tenant apps or add required middleware.

**Database schema errors**:
```
no schema has been selected
```
**Fix**: Use proper tenant test case or set schema context.

**Schema/Field Deletions (The Keyword Argument Phantom)**:
```
TypeError: Event() got unexpected keyword arguments: 'org'
```
**Fix**: When squashing migrations or dropping model fields (e.g. removing `org` from an entity), `makemigrations` does NOT update your test suite logic. You must run a codebase-wide find/replace for direct model instantiations (e.g., `Event(org=...)` or `Model.objects.create(org=...)`) and manually purge the dead kwargs from test factories.

**Form Queryset Filtering vs Custom Clean Validation**:
```
AssertionError: 'invalid_tags_scope' not found in []
```
**Fix**: If a `ModelMultipleChoiceField` dynamically restricts its `queryset` in `__init__` (e.g., strictly filtering tags by scope), Django will natively raise a `Select a valid choice` field-error when an invalid ID is POSTed. Tests should assert that invalid objects are explicitly excluded `assertNotIn(invalid_obj, form.fields['tags'].queryset)` rather than testing for custom `clean()` non-field errors, which will be preempted by default Django field validation.


## Database Query Optimization Testing

**Verify queryset optimization prevents N+1 queries**:

```python
from django.test import TestCase
from django.db import connection

class ArticleListTest(TestCase):
    def test_queryset_optimization(self):
        # Create test data
        for i in range(10):
            Article.objects.create(title=f'Article {i}', category=self.category)
        
        # Test optimized query count
        with self.assertNumQueries(2):  # 1 for articles, 1 for prefetch
            articles = Article.objects.select_related('category').prefetch_related('tags')
            for article in articles:
                _ = article.category.name  # select_related
                _ = list(article.tags.all())  # prefetch_related
        
        # Without optimization - would be N+1 queries
        with self.assertNumQueries(11):  # 1 + 10 for categories
            articles = Article.objects.all()
            for article in articles:
                _ = article.category.name  # N+1!
```

## Parallel Execution Under django-tenants (pytest-xdist + schema pooling)

For large multi-tenant suites (1000+ tests), two orthogonal levers compose to cut wall-clock dramatically:

### Lever 1 — pytest-xdist (per-worker test DBs)

pytest-django appends `_gw{worker-id}` to the test DB name automatically when running under `pytest-xdist`, so each worker gets its own Postgres database. Combine with `--dist loadscope` so a `TenantTestCase` class lands on one worker (avoids re-paying `setUpClass` schema creation cost on multiple workers).

```bash
pytest -n 8 --dist loadscope --create-db  # default pattern
```

Use `-n` equal to physical-core count. SMT adds negligible wall-clock once physical cores saturate and pushes the CPU to sustained thermal limits.

**Measured on an 8c/16t Ryzen 7 H class chip + 46 GB RAM** (2286 tests, django-tenants):

| Config | Wall-clock | Speedup |
|---|---:|---:|
| Serial | 52:22 | 1.0× |
| `-n 4` | 14:12 | 3.69× |
| `-n 8` | 08:17 | 6.32× (default) |
| `-n 16` | 08:14 | 6.36× (thermal-ceiling knee) |

### Lever 2 — Tenant-schema pooling (reuse one schema per worker)

Per-class `CREATE SCHEMA + migrate TENANT_APPS + DROP SCHEMA` is the biggest cost pytest-xdist cannot touch. Pooling reuses ONE pre-migrated schema per worker with `TRUNCATE RESTART IDENTITY CASCADE` between classes. Opt-in via env var.

```bash
TEISUTIS_POOLING=1 pytest -n 8 --dist loadscope --create-db  # ~17% faster
```

The pool fixture lives in `web/conftest.py`:

```python
@pytest.fixture(scope="session", autouse=True)
def _tenant_schema_pool(django_db_setup, django_db_blocker):
    import os
    if os.environ.get("TEISUTIS_POOLING") != "1":
        yield
        return

    from django_tenants.test.cases import TenantTestCase
    from teisutis_auth.models import Domain, Org

    worker = os.environ.get("PYTEST_XDIST_WORKER", "main")
    pool_schema = f"test_pool_{worker}"
    with django_db_blocker.unblock():
        # Create pool tenant once per worker; migrate its schema.
        pool_org = Org.objects.create(
            name=f"Pool-{worker}",
            schema_name=pool_schema,
        )
        # Snapshot field defaults so setUpClass can restore after test mutations.
        pool_defaults = {
            f.attname: getattr(pool_org, f.attname)
            for f in pool_org._meta.concrete_fields
            if f.attname not in {"id", "schema_name", "name"}
        }

        original_setUpClass = TenantTestCase.setUpClass
        original_tearDownClass = TenantTestCase.tearDownClass

        def pooled_setUpClass(cls):
            cls.add_allowed_test_domain()
            # Restore pool_org defaults (undo prior class's tenant mutations).
            for attname, val in pool_defaults.items():
                setattr(pool_org, attname, val)
            pool_org.save()
            # Per-class domain (is_primary=True) so HTTP_HOST routing resolves
            # via the class's expected hostname.
            class_domain = cls.get_test_tenant_domain()
            Domain.objects.filter(domain=class_domain).delete()
            cls.domain = Domain.objects.create(
                tenant=pool_org, domain=class_domain, is_primary=True,
            )
            cls.tenant = pool_org
            connection.set_tenant(pool_org)

        def pooled_tearDownClass(cls):
            # TRUNCATE every tenant-schema table; drop class domain.
            connection.set_schema_to_public()
            Domain.objects.filter(
                tenant=pool_org, domain=cls.get_test_tenant_domain()
            ).delete()
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = %s AND table_type = 'BASE TABLE'
                    """,
                    [pool_schema],
                )
                tables = [row[0] for row in cursor.fetchall()]
                if tables:
                    quoted = ", ".join(f'"{pool_schema}"."{t}"' for t in tables)
                    cursor.execute(f"TRUNCATE TABLE {quoted} RESTART IDENTITY CASCADE")

        TenantTestCase.setUpClass = classmethod(pooled_setUpClass)
        TenantTestCase.tearDownClass = classmethod(pooled_tearDownClass)
        try:
            yield
        finally:
            TenantTestCase.setUpClass = original_setUpClass
            TenantTestCase.tearDownClass = original_tearDownClass
```

### Gotchas both levers share

- **`search_path` reset before nested `create_schema`.** If a test calls `create_test_org(...)` inside a pooled class, the search_path is on the pool schema; `org.create_schema()` will migrate against the wrong target (CREATE TABLE `django_admin_log` fails with `DuplicateTable`). Add `connection.set_schema_to_public()` immediately before `org.create_schema()` in `create_test_org`. Harmless when pooling is off — equivalent to a redundant reset.
- **`is_primary=True` convention.** django-tenants' upstream `TenantTestCase.setUpClass` creates the class Domain **without** setting `is_primary`. `tenant.get_primary_domain()` then returns `None`. Override `setup_domain` in your `TenantTestCaseBase`:

  ```python
  @classmethod
  def setup_domain(cls, domain):
      domain.is_primary = True
  ```

  This is a **quality improvement independent of pooling** — lets tests use `self.tenant.get_primary_domain().domain` reliably as `HTTP_HOST` without worrying about None. Bonus: prevents cross-worker races at `-n 16` when multiple classes share the default `tenant.test.com` domain.
- **Test mutations of `self.tenant` fields.** Tests that do `self.tenant.is_public_chat_enabled = True; self.tenant.save()` will persist the mutation in `pool_org` and leak into the next class. The snapshot-restore in `pooled_setUpClass` above handles this — if you implement pooling, don't skip it.
- **Hardcoded `HTTP_HOST = "tenant.test.com"` in tests.** Works fine under non-pooled (default `get_test_tenant_domain()` returns `tenant.test.com`) but can race under xdist `-n 16`. Migrate to `self.tenant.get_primary_domain().domain` as defragilization work.
- **Pool-tenant DDL races at `-n 8+`** (deadlock on pg_catalog). Autouse session-scoped pool setup does `Org.objects.create(schema_name=pool_schema)` per worker, which fires `CREATE SCHEMA + migrate(TENANT_APPS)`. Eight parallel runs of the tenant-migration `ADD CONSTRAINT` against tables with FKs into public-schema anchors (e.g. `auth_user`) deadlock on `ShareRowExclusiveLock` / `AccessExclusiveLock` on system-catalog relations. Symptom: `psycopg2.errors.DeadlockDetected` during `django_db_setup`, often for pure `SimpleTestCase`-only modules (the autouse fixture runs regardless of what was collected). Single-worker runs pass; `-n 2` usually passes; `-n 8` reliably fails. Fix — serialize the DDL-heavy portion with a PostgreSQL advisory lock, no new Python dep, auto-released on worker exit:

  ```python
  @pytest.fixture(scope="session", autouse=True)
  def _tenant_schema_pool(django_db_setup, django_db_blocker):
      if os.environ.get("POOLING") != "1":
          yield
          return
      from django.db import connection as _pool_conn
      POOL_SETUP_LOCK_ID = 0x5F00B4  # arbitrary int64, keyed on purpose

      with django_db_blocker.unblock():
          with _pool_conn.cursor() as cur:
              cur.execute("SELECT pg_advisory_lock(%s)", [POOL_SETUP_LOCK_ID])
          try:
              with schema_context("public"):
                  Org.objects.create(schema_name=f"test_pool_{worker}")
          finally:
              with _pool_conn.cursor() as cur:
                  cur.execute("SELECT pg_advisory_unlock(%s)", [POOL_SETUP_LOCK_ID])
          yield
          # teardown …
  ```

  Held only during the migration; monkey-patching of `TenantTestCase.setUpClass` afterwards doesn't need the lock. (Teisutis PR #330 cycle 10.)

### When to use each lever

| Use `pytest-xdist` alone (default) | Use `pytest-xdist` + pooling |
|---|---|
| Debugging a single failing test | Full-suite CI-grade sweeps |
| First parallel-run on a suite (simpler) | Mature suite with many `TenantTestCase` subclasses |
| Test-infra refactor in progress | Steady-state test infra |

Pooling is **opt-in behind an env var** — always leave the default path (non-pooled) working so individual test iteration isn't tied to the pool's success.

## Test Organization Patterns

### Base Test Classes

**For multi-tenant applications**:
```python
from django_tenants.test.cases import TenantTestCase

class TenantTestCaseBase(TenantTestCase):
    """Base class for tenant-aware tests."""

    @classmethod
    def get_test_schema_name(cls):
        return 'test_schema'

    @classmethod
    def setup_domain(cls, domain):
        """Mark class Domain as is_primary=True; see Parallel Execution
        section above for rationale — makes get_primary_domain() return a
        real domain and unblocks the `self.tenant.get_primary_domain().domain`
        idiom for HTTP_HOST derivation."""
        domain.is_primary = True

    def setUp(self):
        super().setUp()
        self.tenant = self.get_tenant()  # Test tenant
        # Create test data in tenant schema
```

**For API testing**:
```python
from rest_framework.test import APITestCase

class APIBaseTest(APITestCase):
    """Base class for API tests with authentication."""
    
    def setUp(self):
        self.user = User.objects.create_user('test@example.com', 'pass')
        self.client.force_authenticate(user=self.user)
```

## Testing Best Practices

- ✅ **Always mock external APIs** in general test suite
- ✅ **Guard expensive tests** with environment variables
- ✅ **Test database persistence**, not just return values
- ✅ **Verify query optimization** with `assertNumQueries`
- ✅ **Use consistent locale** for text-checking tests
- ✅ **Organize tests** with descriptive base classes
- ✅ **Run full suite once** to collect all failures
- ✅ **Fix root causes** systematically before re-running
- ❌ **Never run expensive tests** in CI without explicit flags
- ❌ **Never skip database verification** in business logic tests
- ❌ **Never depend on default locale** for text assertions