# Multi-tenant Playwright — django-tenants fixtures

How to drive a `django-tenants` (schema-per-tenant) Django app from Playwright tests. Single-tenant projects can ignore this file. Reading order: skim [`../../django/references/MULTI_TENANT.md`](../../django/references/MULTI_TENANT.md) first if you don't already know how `django-tenants` resolves tenants from the request host.

Load this reference when:

- Authoring Playwright tests against a project that uses `django-tenants`.
- A Playwright test passes locally but hits "tenant not found" on CI.
- Writing pytest fixtures that bridge `django-tenants` schema setup to Playwright's `BrowserContext`.
- Designing the test-data seeding strategy across `public` schema (shared) + per-tenant schemas.

## The four problems multi-tenant Playwright tests must solve

1. **Tenant resolution by host** — `django-tenants` reads the `Host` header to pick the tenant schema. The browser must send the right host for the right test.
2. **Schema seeding** — every tenant schema needs migrations applied + seed data before tests run. Cross-test isolation needs a teardown story.
3. **Auth boundaries** — login happens within a tenant context; a session cookie from tenant A is meaningless on tenant B.
4. **`public` schema state vs tenant-schema state** — fixtures need to seed both, in the right order (public first — it owns `Tenant` rows that map host → schema).

## Test-server setup — `live_server` with tenant routing

`pytest-django`'s `live_server` fixture starts a real WSGI server that Playwright can hit. With `django-tenants`, the bare `live_server` works only for the `public` schema; tenant subdomains/paths need DNS or `Host`-header resolution.

Two integration shapes:

### Option A — `Host`-header injection per browser context

Simplest and recommended. Playwright sends an explicit `Host` header on every request:

```python
import pytest
from django_tenants.utils import schema_context, get_tenant_model

@pytest.fixture
def tenant_a(db):
    Tenant = get_tenant_model()
    tenant, _ = Tenant.objects.get_or_create(
        schema_name='tenant_a',
        defaults={'name': 'Tenant A'},
    )
    # django-tenants creates the schema on save; ensure it has migrations:
    from django.core.management import call_command
    with schema_context(tenant.schema_name):
        call_command('migrate_schemas', '--schema', tenant.schema_name, verbosity=0)
    return tenant


@pytest.fixture
def tenant_a_context(browser, tenant_a, live_server):
    # Replace 'localhost' (live_server default) with the tenant's primary domain.
    # django-tenants resolves the tenant from the Host header.
    primary_domain = tenant_a.domains.filter(is_primary=True).first().domain
    context = browser.new_context(
        base_url=live_server.url,
        extra_http_headers={'Host': primary_domain},
    )
    yield context
    context.close()


@pytest.fixture
def tenant_a_page(tenant_a_context):
    page = tenant_a_context.new_page()
    yield page
    page.close()
```

Use `tenant_a_page` instead of the default `page` fixture in tests that need tenant-A scope:

```python
def test_login_on_tenant_a(tenant_a_page, tenant_a_user):
    tenant_a_page.goto('/login/')
    tenant_a_page.fill('[name="username"]', tenant_a_user.username)
    tenant_a_page.fill('[name="password"]', 'pw')
    tenant_a_page.click('[type="submit"]')
    expect(tenant_a_page).to_have_url('/dashboard/')
```

### Option B — `/etc/hosts`-style aliasing (CI-only, brittle)

Some teams add `127.0.0.1 tenant-a.localtest.me` to the test environment so the browser navigates to a real subdomain. Avoid in CI: requires root or a privileged container init step, and `localtest.me` is third-party DNS that occasionally fails. Option A is more portable.

## Schema seeding — what runs once vs per-test

Three layers:

| Layer | When it runs | What it does |
|-------|--------------|--------------|
| `db` (pytest-django) | Once per session | Creates the test DB; runs migrations on the `public` schema. |
| Per-tenant schema | Once per session (or per test, project choice) | `migrate_schemas --schema=<tenant>` creates the tenant schema + applies tenant-app migrations. |
| Test data seed | Per test (or per fixture scope) | Creates rows inside the tenant schema. |

Recommended scope: `db` + per-tenant schema in `session` scope; test data seed in `function` scope with explicit teardown. Per-test schema creation is too slow (`migrate_schemas` is multi-second per tenant).

Session-scoped fixture, conftest.py:

```python
@pytest.fixture(scope='session')
def django_db_setup(django_db_setup, django_db_blocker):
    """Override pytest-django's django_db_setup to add tenant schemas."""
    Tenant = get_tenant_model()
    with django_db_blocker.unblock():
        for schema_name, host in [
            ('tenant_a', 'tenant-a.example.test'),
            ('tenant_b', 'tenant-b.example.test'),
        ]:
            tenant, _ = Tenant.objects.get_or_create(
                schema_name=schema_name,
                defaults={'name': schema_name.title()},
            )
            tenant.domains.get_or_create(
                domain=host,
                defaults={'is_primary': True, 'tenant': tenant},
            )
            from django.core.management import call_command
            call_command('migrate_schemas', '--schema', schema_name, verbosity=0)
```

## Test-data seeding — `schema_context` is mandatory

```python
@pytest.fixture
def tenant_a_user(tenant_a):
    from django.contrib.auth import get_user_model
    User = get_user_model()
    with schema_context(tenant_a.schema_name):
        user, _ = User.objects.get_or_create(
            username='tenant_a_user',
            defaults={'email': 'a@example.test'},
        )
        user.set_password('pw')
        user.save()
    return user
```

The `schema_context` block is non-negotiable: without it, Django queries hit `public` and either fail (if the model is tenant-scoped) or pollute (if the model exists in `public`).

## Authentication — pre-baked cookies vs UI login

For tests that don't *exercise* the login flow, pre-bake the session cookie to skip a full UI login on every test:

```python
@pytest.fixture
def tenant_a_authed_page(tenant_a_context, tenant_a, tenant_a_user, live_server):
    from django.contrib.sessions.backends.db import SessionStore
    from django_tenants.utils import schema_context
    with schema_context(tenant_a.schema_name):
        session = SessionStore()
        session['_auth_user_id'] = str(tenant_a_user.id)
        session['_auth_user_backend'] = 'django.contrib.auth.backends.ModelBackend'
        session.save()
    primary_domain = tenant_a.domains.filter(is_primary=True).first().domain
    tenant_a_context.add_cookies([{
        'name': 'sessionid',
        'value': session.session_key,
        'domain': primary_domain,
        'path': '/',
    }])
    page = tenant_a_context.new_page()
    yield page
    page.close()
```

Two non-obvious gotchas:

- `session.save()` MUST happen inside `schema_context` — sessions live in the tenant schema (per `django-tenants` defaults).
- The cookie's `domain` field must match the `Host` header the browser sends (Option A above). Mismatched domain → cookie not sent → session not picked up → test redirects to `/login/`.

## Cross-tenant isolation — verifying no leak

A key benefit of `django-tenants` is that tenant A's rows never appear in tenant B's queries. Test it:

```python
def test_tenant_a_rows_invisible_to_tenant_b(
    tenant_a_authed_page, tenant_b_authed_page,
    tenant_a_record, tenant_b_record,
):
    tenant_a_authed_page.goto('/records/')
    expect(tenant_a_authed_page.locator(f'#record-{tenant_a_record.id}')).to_be_visible()
    expect(tenant_a_authed_page.locator(f'#record-{tenant_b_record.id}')).to_have_count(0)

    tenant_b_authed_page.goto('/records/')
    expect(tenant_b_authed_page.locator(f'#record-{tenant_b_record.id}')).to_be_visible()
    expect(tenant_b_authed_page.locator(f'#record-{tenant_a_record.id}')).to_have_count(0)
```

Cheap and worth running once per release. Schema-per-tenant rarely regresses, but a misplaced query that bypasses tenant routing (e.g. raw SQL with hardcoded `public.table`) WILL slip through unit tests and only surface here.

See [`../../django/references/TENANT_SCOPED_FK_VALIDATION.md`](../../django/references/TENANT_SCOPED_FK_VALIDATION.md) for the orthogonal failure mode where shared-schema models with `org_id` need explicit per-row scoping — those bugs survive even strict schema isolation and Playwright cross-tenant tests are the right surface to catch them.

## Cleanup strategy — `transactional_db` won't help you

`pytest-django`'s `transactional_db` rollback works on a single schema. With multiple tenant schemas seeded per test, the rollback covers `public` only. Two options:

1. **Truncate per-tenant tables in fixture teardown** (fast, reliable):

```python
@pytest.fixture
def clean_tenant_a(tenant_a, db):
    yield
    with schema_context(tenant_a.schema_name):
        from django.db import connection
        with connection.cursor() as cur:
            cur.execute('TRUNCATE TABLE record, record_tag CASCADE;')
```

2. **Drop and re-create tenant schemas between tests** (slow, foolproof) — only if the test creates schema-level state (DDL), which is rare.

Default to option 1. Add an explicit list of tables that need truncation; `cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = %s", [tenant_a.schema_name])` is the dynamic version if the table list grows.

## Anti-patterns

- ❌ **Calling `goto('/login/')` without setting the `Host` header** — `django-tenants` resolves to `public`, the page renders, the test "works", but the assertion targets are wrong-tenant data.
- ❌ **Seeding tenant data in `public` schema** — silent until queried under `schema_context`, then nothing exists.
- ❌ **Sharing a `BrowserContext` across tenants** — cookies, localStorage, IndexedDB are context-scoped. One context per tenant.
- ❌ **Pre-baking session cookies WITHOUT `schema_context` on session save** — the session row lands in `public.django_session` instead of `<tenant>.django_session`; SessionMiddleware looks in the wrong schema.
- ❌ **Cookie `domain` mismatch** with the `Host` header — the browser silently drops the cookie. Symptom: every authed test redirects to login.

## Related references

- [`../../django/references/MULTI_TENANT.md`](../../django/references/MULTI_TENANT.md) — the underlying schema-per-tenant architecture.
- [`../../django/references/MULTI_TENANT_ASYNC.md`](../../django/references/MULTI_TENANT_ASYNC.md) — async/WebSocket counterparts.
- [`../../django/references/TENANT_SCOPED_FK_VALIDATION.md`](../../django/references/TENANT_SCOPED_FK_VALIDATION.md) — orthogonal isolation failure (shared-schema rows with `org_id`).
- [`HTMX_ALPINE_WAITS.md`](HTMX_ALPINE_WAITS.md) — Playwright wait recipes once tenant routing is solved.

---

**Last Updated**: 2026-05-09
