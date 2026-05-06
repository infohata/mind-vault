# RULE_tenant-scoped-fk-validation

## Validate-and-prune FK helpers must scope existence checks explicitly when a model carries an `org_id` (or equivalent tenant) column

In a multi-tenant Django project, models split into two schema homes:

- **Tenant-schema models** — isolated by the active DB connection's schema (django-tenants routes per request). Queries against these are implicitly tenant-scoped because the connection itself is. No `org_id` column lives on the table.
- **Shared/public-schema models that carry an `org_id` FK** — `OwnedModel`-style mixin, where the row IS tenant data but lives in the shared schema for cross-tenant operations (admin, billing, directory lookups). Queries against these are NOT implicitly scoped — the schema routing doesn't help, because the table is in `public`.

A validate-and-prune helper that walks a heterogeneous list of FK kinds (some tenant-schema, some shared-with-`org_id`) and does `Model.objects.filter(id__in=session_ids)` is **silently broken on the shared/`org_id` side**: a session can carry stale ids that match a different tenant's row, and the existence query returns those rows as "valid", leaving the stale filter in session.

## The Hard Rule

For every FK validate-and-prune (or validate-and-resolve, or validate-and-permission-probe) helper that walks shared/public-schema models carrying an `org_id`:

**Explicitly filter `org_id=<current_org_id>` on the existence query, even when the helper runs in a tenant-bound request context.**

For tenant-schema models: no explicit filter needed — the schema routing IS the isolation, and the model has no `org_id` column to filter by anyway.

When the helper walks both kinds in one loop, mark each kind with a `tenant_scope_required` boolean (or equivalent flag) and apply the `org_id` filter conditionally. This makes the schema-vs-public distinction visible at the call site, not implicit in the developer's memory of which model lives where.

## Pattern

```python
# Per-kind: (FK key, model, container dict, "is multi-id list",
#           "tenant_scope_required")
fk_specs = (
    ('scope',    Scope,    cross_existing,  False, True),   # public schema, has org_id
    ('property', Property, cross_existing,  False, True),   # public schema, has org_id
    ('category', Category, cross_existing,  False, False),  # tenant schema, no org_id
    ('tags',     Tag,      entity_existing, True,  False),  # tenant schema, no org_id
)

for kind, model, container, is_multi, tenant_scope_required in fk_specs:
    requested_ids = _collect_ids(...)
    if not requested_ids:
        continue
    existence_qs = model.objects.filter(id__in=requested_ids)
    if tenant_scope_required:
        existence_qs = existence_qs.filter(org_id=org_id)
    present_ids = set(
        str(pk) for pk in existence_qs.values_list('id', flat=True)
    )
    stale_ids = set(requested_ids) - present_ids
    # ... drop stale, toast, track fingerprint, etc.
```

## When This Applies

Any helper that takes user-supplied (session, querystring, form, JSON body, signal payload) FK ids and decides "exist or not, keep or drop":

- **Filter pruners** — session-scoped UI filters that need to drop stale references after deletes/cross-tenant moves. (The motivating case.)
- **Session-cleanup helpers** — periodic / on-login cleanup that walks pinned-record references.
- **Generic-FK resolvers** — `GenericForeignKey` resolution where the `content_object` lookup spans heterogeneous models with different schema homes.
- **Permission-probe helpers** — "can the user see record N?" that walks an FK to determine ownership.
- **Bulk-export sanitisation** — exports filtered by an opaque id list need the same defence.
- **Webhook / API handlers** that accept FK ids from outside the request's tenant context.

## Why Schema Routing Alone Is Insufficient

Three failure modes:

1. **The model is in the public schema by design** — `Org`, `User`, `Domain`, and any `OwnedModel`-style table that needs cross-tenant operations. Schema routing doesn't help; the table is shared by construction. Per-row `org_id` filtering is the only isolation.

2. **The helper runs outside a tenant connection.** Signals, Celery tasks (without a `tenant_context()` block), management commands, raw-SQL dashboards, periodic-job sweepers — schema routing is a request-middleware artefact, and code that runs before / after / outside the request lifecycle doesn't get it. Explicit `org_id` filters work everywhere.

3. **The session itself is the cross-tenant carrier.** A user who switches orgs (or whose session gets restored from a backup, or whose ids are guessed by an attacker) presents a stale id from a foreign tenant. The schema is right at request-time; the *id payload* is wrong. Schema routing has no opinion on payload contents.

## When NOT to Apply

- The model is a **tenant-schema** model (no `org_id` column, isolated by schema). Adding `.filter(org_id=org_id)` would raise `FieldError`. Not applicable.
- The helper has already filtered through a queryset that was itself produced by a tenant-scoped manager (e.g. `request.user.org.scope_set.filter(id__in=...)`). The reverse FK from `org` IS the explicit scope. Not adding additional filtering.
- Single-tenant projects (no `Org`, no `org_id` anywhere). The whole concept doesn't exist; this rule is silent.

## Related Rules / Skills

- [`skills/django/SKILL.md` § Multi-tenancy vs. ForeignKey boundaries](../skills/django/SKILL.md) — the schema-home decision (which models get `org_id`, which don't); this rule extends the operational discipline for the validate-and-prune side of the same boundary.
- [`skills/django/references/MULTI_TENANT.md`](../skills/django/references/MULTI_TENANT.md) — full multi-tenant patterns reference.
- [`RULE_self-sweep-before-push`](RULE_self-sweep-before-push.md) — the `tenant_scope_required` flag is exactly the kind of boolean a self-sweep contract-change check should grep for when a new FK kind is added to an `fk_specs` tuple; missing the flag silently regresses isolation.

## Anti-Patterns

- ❌ "The connection is tenant-scoped, the query is automatically scoped" — only true for tenant-schema models.
- ❌ Coarse helper-level gate: `if not is_authenticated: return`. The auth check doesn't substitute for per-row tenant scoping; an authenticated user from tenant A can present tenant B's ids.
- ❌ Trusting session payload because "the user must have set it from a valid view". Session contents are user-modifiable in the threat model.
- ❌ Adding `org_id` filtering to tenant-schema-model queries to "be safe" — the field doesn't exist; this is a code error, not extra defence.
- ❌ Encoding the schema home implicitly via "I'll remember which model lives where". The flag in the spec tuple makes the distinction reviewable.

## Diagnostic Recipe

When triaging "stale filter survives across deletion of foreign-tenant rows" or "user sees record from another tenant in dropdown" symptoms:

```bash
# Find every validate-and-prune-shaped helper:
rg -n 'objects\.filter\(id__in=' --type=py | grep -iE 'prune|exist|valid|sanit|clean'

# For each hit, verify the model's schema home:
#   - In SHARED_APPS / public schema with org_id FK → MUST have explicit org filter
#   - In TENANT_APPS / tenant schema → no org_id, schema routing covers it
```

For django-tenants projects, `SHARED_APPS` and `TENANT_APPS` lists in `settings.py` are the source of truth.

## Provenance

Surfaced in teisutis [PR #428](https://github.com/infohata/teisutis/pull/428) cycle 2 (bugbot review 4232905213, fix commit `f1cca20c`) — `_prune_stale_fk_filters` queried `Scope` and `Property` (both `OwnedModel` carrying `org_id` in the public schema) by `id__in` only, while `Category` and `Tag` queries (both tenant-schema, no `org_id`) were correctly schema-isolated. Cross-tenant ids in session counted as "valid" and survived pruning, producing an empty-list-no-toast regression for any foreign-tenant id. Fix introduced `tenant_scope_required` per-kind flag and conditional `org_id=org_id` filter.

---

**Last Updated**: 2026-05-06
