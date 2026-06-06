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
        $tenantId = auth()->user()?->tenant_id;

        // FAIL CLOSED — this is the load-bearing line. Every queued job, artisan
        // command, scheduler tick, and event listener runs with auth()->user()
        // === null. A naive `if ($tenantId) { $builder->where(...) }` adds NO
        // filter in those contexts, so `Invoice::all()` inside a worker returns
        // EVERY tenant's rows — a silent cross-tenant leak, and the section below
        // tells you to trust the scope, so there is no manual fallback. Return
        // zero rows instead; use withoutGlobalScope(TenantScope::class) for a
        // deliberate, reviewable system query.
        if ($tenantId === null) {
            $builder->whereRaw('1 = 0');
            return;
        }

        $builder->where($model->getTable() . '.tenant_id', $tenantId);
    }
}
```

```php
// app/Models/Concerns/BelongsToTenant.php
trait BelongsToTenant
{
    protected static function bootBelongsToTenant(): void
    {
        // READ side — every SELECT is tenant-filtered automatically. This is the
        // SINGLE registration of TenantScope; do NOT also put #[ScopedBy] on the
        // model — Laravel keys class-based global scopes by class name, so a
        // second registration silently overwrites this one (redundant, not
        // additive, and muddies the bypass semantics).
        static::addGlobalScope(new TenantScope);

        // WRITE side — stamp tenant_id on insert so rows are never orphaned.
        // Fail closed here too: in a queue/CLI context auth()->user() is null,
        // so an unguarded `??=` would stamp null and create an orphan the read
        // scope then hides from everyone. Demand an explicit tenant_id when there
        // is no auth context rather than persisting a null.
        static::creating(function (Model $model) {
            $tenantId = $model->tenant_id ?? auth()->user()?->tenant_id;
            if ($tenantId === null) {
                throw new \RuntimeException(
                    'BelongsToTenant: no tenant context — set tenant_id explicitly '
                    . 'in queue/CLI/system code before saving ' . $model::class . '.'
                );
            }
            $model->tenant_id = $tenantId;
        });
    }
}
```

```php
// app/Models/Invoice.php — the trait boots the scope; nothing else to wire.
class Invoice extends Model
{
    use BelongsToTenant; // registers TenantScope (read) + the tenant_id stamp (write)
}
```

With this, `Invoice::all()` returns only the current tenant's invoices in an HTTP request, **zero rows** in an unauthenticated context (fail-closed), and `Invoice::create([...])` auto-stamps `tenant_id` or throws if no tenant is resolvable — no per-query `where` anywhere.

**Prefer the declarative `#[ScopedBy]` attribute (L ≥ 10.34)?** Use it *instead of* the trait's `addGlobalScope` call, never alongside it — put `#[ScopedBy([TenantScope::class])]` on the model and have the trait register only the `creating` stamp. One registration of the read scope, exactly.

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
