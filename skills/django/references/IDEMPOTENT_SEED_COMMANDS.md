# Idempotent seed / management commands

Patterns for a management command (or helper module) that provisions a
reproducible dev/test/e2e environment **from nothing** AND tops up an
already-initialised database without duplicating or corrupting rows. A seed that
only works on an empty DB isn't reproducible — it must be a safe no-op on the
second run and must *heal* drifted rows on an existing one.

## The top-up idempotency trio

`get_or_create` alone is not enough. Three recurring gaps turn a "re-run is a
no-op" claim into a re-run that silently leaves the environment broken:

### 1. Attach M2M / GenericFK relations unconditionally, not only on `created`

```python
obj, created = Model.objects.get_or_create(title=..., scope=..., defaults={...})
if created and tags:
    obj.tags.set(tags)          # ❌ a pre-existing untagged row never gets its tags
```

If a matching row already exists *without* its M2M tags or its GenericFK parent
link (a partial row from an earlier interrupted run, a manual edit, a schema that
predates the relation), the `if created` guard skips the attach and the row stays
incomplete. Downstream consumers that assume the relation (a filter that needs the
tag, a detail view that needs the parent) then fail even after a "successful" seed.

```python
obj, created = Model.objects.get_or_create(title=..., scope=..., defaults={...})
if tags:
    obj.tags.add(*tags)         # ✅ idempotent AND non-destructive — heals partial rows
# GenericFK link: repair on top-up too, don't bury it in defaults={} (defaults
# only apply on create).
if parent is not None and (obj.content_type_id is None or obj.object_id is None):
    obj.content_type = parent_ct
    obj.object_id = parent.pk
    obj.save(update_fields=["content_type", "object_id"])
```

**`add(*tags)` over `set(tags)`** when the goal is "ensure the required relations
exist" rather than "make the relation set exactly this". `set` is destructive — it
removes any extra relations a developer added to the synthetic row over time;
`add` is idempotent (re-adding an existing M2M row is a no-op) and preserves them.

### 2. Correct privileged-user flags on existing rows

```python
user, created = User.objects.get_or_create(username=..., defaults={
    "password": make_password(SEED_PW), "is_superuser": True, "is_staff": True,
})
```

`defaults` apply **only on create**. If the user already exists but was demoted
(superuser bit cleared, `is_staff` off, language drifted), the seed silently
leaves it wrong — and the test suite / docs that assume the privileged flags break
on an already-initialised DB. Correct the flags on top-up, **without touching the
password** (never reset an existing user's password from a seed):

```python
if not created:
    fields = []
    if user.is_superuser != want_superuser:
        user.is_superuser = want_superuser; fields.append("is_superuser")
    if not user.is_staff:
        user.is_staff = True; fields.append("is_staff")
    if fields:
        user.save(update_fields=fields)   # password untouched
```

### 3. Handle globally-unique conflicts without aborting

A field with a global `unique=True` (e.g. django-tenants `Domain.domain`, which is
unique across **all** tenants) breaks `get_or_create` keyed on `(field, owner)`:
if a *different* owner already holds the value, the lookup misses, the create fires,
and the global unique constraint raises `IntegrityError` — aborting the whole
seed instead of topping up.

```python
# ❌ aborts when another tenant already owns 'localhost'
Domain.objects.get_or_create(domain="localhost", tenant=org, defaults={...})

# ✅ look up by the globally-unique field alone; claim only when free or ours
existing = Domain.objects.filter(domain=name).first()
if existing is None:
    Domain.objects.create(domain=name, tenant=org, is_primary=is_primary)
elif existing.tenant_id != org.id:
    logger.warning("%r already owned elsewhere; skipping (routing won't reach %r)",
                   name, org.schema_name)   # don't claim it, don't crash
```

**Audit the newly-reachable state** the conflict-skip introduces. Skipping the
preferred-primary domain can leave the owner with only non-primary domains, so
`get_primary_domain()` returns nothing. Guarantee the invariant afterward:

```python
owned = Domain.objects.filter(tenant=org)
if owned.exists() and not owned.filter(is_primary=True).exists():
    promote = owned.order_by("id").first()
    promote.is_primary = True
    promote.save()   # promote one so a primary always exists
```

## Production safety guard on privileged-user seeds

A seed command that creates a **superuser with a known synthetic password** can run
in any environment. An accidental invocation against a production DB creates/modifies
privileged accounts with a guessable password. Gate the **command** (not the
underlying function) on `DEBUG`, with an explicit opt-in for the rare CI case that
runs with `DEBUG=False`:

```python
def add_arguments(self, parser):
    parser.add_argument("--allow-non-debug", action="store_true",
                        help="permit running with DEBUG=False (CI only)")

def handle(self, *args, **options):
    if not settings.DEBUG and not options["allow_non_debug"]:   # store_true → always present
        raise CommandError(
            "<cmd> is dev/test-only (creates privileged users with a known "
            "password) and refuses to run with DEBUG=False. Pass "
            "--allow-non-debug to override for a CI job."
        )
```

**Guard the command, not the function.** Put the `DEBUG` check in the management
command's `handle()`, NOT in the seed function it calls. The unit test that
exercises the seed runs with `DEBUG=False` (Django's test runner forces it) and
calls the function directly — a function-level guard would break the test, while a
command-level guard leaves the function callable and still blocks the real CLI
invocation on a non-debug host.

## Cross-schema teardown for tests that create a real tenant

A test that exercises a from-nothing seed creates a **real** tenant schema (DDL +
`migrate_schemas`), so it can't roll back inside an atomic `TestCase`. Use a
non-atomic `TransactionTestCase` + explicit teardown — and the teardown can't use
the ORM cascade. See [`MULTI_TENANT.md`](MULTI_TENANT.md) § *Tearing down a real
tenant in tests* for the `_drop_schema(force_drop=True)` + raw-SQL-delete pattern.

## When this applies

- Any `seed_*` / `bootstrap_*` / demo-data management command meant to run in
  multiple contexts (fresh volume, CI, existing dev DB, compose post-up hook).
- Especially when the command provisions auth users or globally-unique rows.
- Pairs with reproducible-e2e setups where the same command runs on a developer's
  long-lived DB and a CI fresh volume.
