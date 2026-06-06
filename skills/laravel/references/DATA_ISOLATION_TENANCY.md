# Data isolation & tenancy (authored fresh — ecosystem gap)

Multi-tenant data isolation is the single heading that most stresses the cross-stack contract, and it is thin-to-absent across surveyed Laravel skill projects — so mind-vault authors it natively. Read this whenever a model carries tenant/owner-scoped rows.

## Mechanism — global scope + a stamping trait

Laravel's idiom is a **global scope** (a query rewriter applied to every query for a model) paired with a trait that *both* filters reads and stamps the foreign key on writes. The read side and the write side are separate concerns and a working tenant model needs **both**.

```php
// app/Models/Scopes/TenantScope.php
use Illuminate\Database\Eloquent\Scope;
use Illuminate\Database\Eloquent\{Builder, Model};

class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        if ($tenantId = auth()->user()?->tenant_id) {
            $builder->where($model->getTable() . '.tenant_id', $tenantId);
        }
    }
}
```

```php
// app/Models/Concerns/BelongsToTenant.php
trait BelongsToTenant
{
    protected static function bootBelongsToTenant(): void
    {
        // READ side — every SELECT is tenant-filtered automatically.
        static::addGlobalScope(new TenantScope);

        // WRITE side — stamp tenant_id on insert so rows are never orphaned.
        static::creating(function (Model $model) {
            $model->tenant_id ??= auth()->user()?->tenant_id;
        });
    }
}
```

```php
// app/Models/Invoice.php — attach the scope declaratively (L >= 10.34)
use Illuminate\Database\Eloquent\Attributes\ScopedBy;

#[ScopedBy([TenantScope::class])]
class Invoice extends Model
{
    use BelongsToTenant;
}
```

With this, `Invoice::all()` returns only the current tenant's invoices and `Invoice::create([...])` auto-stamps `tenant_id` — no per-query `where` anywhere.

## The cross-direction warning (load-bearing)

This heading must warn **both** directions, because the two stacks fail it oppositely:

1. **Django devs under-trust the global scope.** Django's instinct is explicit QuerySet scoping (`.filter(org=...)`) or schema routing. Carried into Laravel, that becomes a reflexive `->where('tenant_id', $id)` on top of a scope that *already* filtered — redundant, and the moment one call site forgets it (relying on the manual habit instead of the scope) a leak appears. **Trust the scope; do not re-add manual `where`.**

2. **The real hazard is the create-path stamping gap.** A global scope rewrites *reads* and does nothing on *writes*. A model with `#[ScopedBy]` but no `creating` stamp will `INSERT` rows with a null or wrong `tenant_id` — and the same scope then **hides those rows from everyone**, including their rightful owner (silent orphans). The scope makes the bug invisible: reads look correct, data quietly rots. Always pair the scope with the `creating` stamp, and verify against real seeded data, not a mock.

A read-side guard that **skips/discards** rows is itself a data-shape claim — exactly the failure class in [`RULE_self-sweep §3`](../../../rules/RULE_self-sweep-before-push.md): a discard guard tested against your *assumed* shape passes, while the producer's real data silently drops every row. Grep the write site for what `tenant_id` actually holds before trusting a read-side skip.

### Bypassing the scope intentionally

```php
Invoice::withoutGlobalScope(TenantScope::class)->find($id); // admin/cross-tenant
Invoice::withoutGlobalScopes()->count();                    // all scopes off
```

Make every such bypass deliberate and reviewable — it is the one sanctioned leak.

## When a single column is not enough — packages

| Need | Reach for |
| --- | --- |
| Single shared schema, one `tenant_id` column, app-level scoping | The trait above — no package. |
| Cache / filesystem / queue isolation, DB-per-tenant, tenant-aware routing & migrations | `stancl/tenancy` (full-stack; single-DB *or* multi-DB; bootstrappers for cache/FS/Redis). |
| Lean multi-DB or single-DB scoping with less surface than stancl | `spatie/laravel-multitenancy` (minimal; you wire the tenant-finder + tasks). |

Use a package only when connection/cache/filesystem isolation or DB-per-tenant is a genuine requirement — for the common single-column case the trait is less to go wrong.

## Reviewer grep

- A model with `#[ScopedBy]`/`addGlobalScope` but **no** `creating`/`saving` stamp (orphan-on-write risk).
- `->where('tenant_id'` scattered in controllers/queries on a model that already has the scope (under-trust smell).
- `withoutGlobalScope(`/`withoutGlobalScopes(` with no comment justifying the cross-tenant read.
- A `creating` stamp present but bulk `insert()`/`upsert()` used elsewhere (bulk skips events — stamp in the payload; see [`EAGER_LOADING.md`](EAGER_LOADING.md)).

## Version note

`#[ScopedBy]` attribute is available since Laravel 10.34 (pre-10.34: register the scope in the model's `booted()` via `addGlobalScope`). Stable on the L12 baseline. (L13 drift — re-verify the attribute namespace if targeting 13.)
