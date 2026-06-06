---
name: laravel
description: Apply Laravel 12 backend conventions across the six data-layer concerns — Eloquent eager-loading (with()/preventLazyLoading), the Form-Request + API-Resource input boundary, queued jobs on Redis/Horizon, tenant data-isolation via global scopes, Policy/Gate authorization, and Pest testing — plus the split-by-ownership translation workflow. Loads before controllers, models, or migrations ship.
license: Apache-2.0
metadata:
  author: mind-vault
  version: '0.1'
---

# laravel

Core Laravel backend patterns organised around the six data-layer contract concerns: how relations are eager-loaded (no N+1, bulk writes), where untrusted input is validated, how deferred work is queued, how every query is scoped to the caller's tenant, who is allowed to act, and how tests stay fast and isolated. Target baseline is **Laravel 12 / PHP 8.2** (the `br-internal-panel` rework destination). Deep mechanics live in `references/`; the body leads cleanly with the contract headings so a generic agent resolves each one by its verbatim string.

**Pairs with:** [laravel-frontend](../laravel-frontend/SKILL.md) for Blade / Livewire / Inertia template patterns. Load both on full-stack feature work (e.g. a controller that returns a Blade fragment on an `HX-Request`).

## When to use

**TRIGGER when:** editing a Laravel project (`composer.json` + `artisan`, `app/Models`, `app/Http/Controllers`, `app/Http/Requests`, `database/migrations/`); adding an Eloquent model or relation; writing a controller, Form Request, or API Resource; dispatching a queued job; adding a Policy/Gate or tenant scope; running `php artisan test`; debugging N+1 or lazy-loading exceptions.

**SKIP for:** Blade/Livewire/Inertia template-only work (use [laravel-frontend](../laravel-frontend/SKILL.md)); non-Laravel PHP (raw PHP, Symfony, legacy ZF1 — different idioms); DevOps without code.

## Pattern

Each `###` below is a contract heading — the same verbatim string the active backend skill exposes on every stack, so a stack-agnostic agent greps one anchor and resolves the Laravel rule under it. Each carries a mechanism, the best-practice default to enforce, the anti-pattern to flag, and a runnable sample; depth pushes into `references/`.

### ORM eager-loading

Eloquent lazy-loads relations on access, so any relation touched inside a loop without a prior `with()` is an N+1 storm. Eager-load every looped relation; use `withCount()` for counts, `load()`/`loadMissing()` to top-up an already-fetched model, `chunkById()`/`lazy()`/`cursor()` for large sets, and `insert()`/`upsert()` for bulk writes instead of `create()` in a loop.

```php
// ❌ N+1 — one query per post to fetch its author
$posts = Post::all();
foreach ($posts as $post) {
    echo $post->author->name;
}

// ✅ single extra query for all authors
$posts = Post::with('author')->withCount('comments')->get();

// ✅ top-up a model already in memory (no re-fetch)
$post->loadMissing('author');

// ✅ bulk write — one INSERT, not N create() round-trips
Post::insert($rows);                       // raw, skips casts/timestamps/events
Post::upsert($rows, ['slug'], ['title']);  // insert-or-update on unique 'slug'
```

The **default to enforce**: `with()` on every relation traversed in a loop, plus strict mode in dev/CI so an accidental lazy load throws instead of silently degrading.

```php
// app/Providers/AppServiceProvider.php — boot()
use Illuminate\Database\Eloquent\Model;

// Laravel-native superpower with NO Django analog: turn N+1 into a hard error
// off-production. Django has no equivalent runtime guard — assertNumQueries is
// opt-in per test; this is global and automatic.
Model::preventLazyLoading(! $this->app->isProduction());
// Model::shouldBeStrict(! app()->isProduction()) also catches lazy loads,
// silently-discarded attributes, and missing-attribute access.
```

**Anti-pattern to flag:** `$model->relation` inside a loop with no `with()`; `Model::create()` called in a loop where `insert()`/`upsert()` would do one round-trip; `chunk()` while mutating the column being paginated (rows shift — use `chunkById()`). See [`references/EAGER_LOADING.md`](references/EAGER_LOADING.md).

### Input-validation boundary

Untrusted input is validated **at the edge** in a Form Request, never inline in a fat controller. The Form Request's `rules()` defines the schema, `authorize()` gates the action, and the controller only ever sees `$request->validated()` — the validated subset, never `$request->all()`. Responses go out through an API Resource (`JsonResource`), never as a raw Eloquent model.

```php
// app/Http/Requests/StorePostRequest.php
class StorePostRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Post::class);
    }

    public function rules(): array
    {
        return [
            'title' => ['required', 'string', 'max:255'],
            'body'  => ['required', 'string'],
        ];
    }
}

// Controller — thin: validated() only, Resource out (auto-422 JSON on failure)
public function store(StorePostRequest $request): PostResource
{
    $post = Post::create($request->validated());
    return new PostResource($post);
}
```

**Anti-pattern to flag:** `$request->validate([...])` inline in a bloated controller; reading `$request->all()` / `$request->input('x')` *after* validation (re-admits unvalidated keys); returning `return $post;` or `Post::all()` straight as JSON (leaks every column, including hidden ones, and skips the Resource contract). See [`references/FORM_REQUESTS_RESOURCES.md`](references/FORM_REQUESTS_RESOURCES.md).

### Background jobs

Any unit of work over ~300ms (email, external API call, image processing, report build) is decoupled into a queued job implementing `ShouldQueue` with the `Queueable` trait, dispatched onto **Redis** and supervised by **Horizon**. Pass IDs, not models; chain with `Bus::chain()` and fan out with `Bus::batch()`.

```php
// app/Jobs/ProcessPodcast.php
class ProcessPodcast implements ShouldQueue
{
    use Queueable;

    public function __construct(public int $podcastId) {} // ID, not the model

    public function handle(): void
    {
        $podcast = Podcast::findOrFail($this->podcastId);
        // ... heavy work ...
    }
}

// Dispatch AFTER the surrounding DB transaction commits, so the worker
// (a separate connection) never races a not-yet-committed row.
ProcessPodcast::dispatch($podcast->id)->afterCommit();
```

The **default to enforce:** Redis + Horizon under a supervised `queue:work` (never `queue:listen` in prod); `->afterCommit()` on any dispatch inside a transaction; idempotency via `ShouldBeUnique` (dedupe queued copies) or the `WithoutOverlapping` middleware (serialise by key) so a retry never double-runs.

**Anti-pattern to flag:** dispatching inside a transaction without `afterCommit` (the job runs before commit and 404s on its own row); an unsupervised worker in prod (dies silently, queue stalls); serializing a whole model into the payload (stale snapshot + bloated job). See [`references/QUEUES_HORIZON.md`](references/QUEUES_HORIZON.md).

### Data isolation / scoping boundary

Multi-tenant isolation is Laravel's idiom-stress point. The native answer is a **global scope** that silently rewrites every query plus a trait that *both* filters reads and stamps the `tenant_id` on writes. The scope must **fail closed** — return zero rows when there is no tenant context — and the trait registers it once (do not also add `#[ScopedBy]`; Laravel keys scopes by class name, so a second registration just overwrites the first).

```php
// app/Models/Scopes/TenantScope.php — FAIL CLOSED is the load-bearing line.
public function apply(Builder $builder, Model $model): void
{
    $tenantId = auth()->user()?->tenant_id;
    // No auth context — queue worker, artisan, scheduler. A naive
    // `if ($tenantId)` adds no filter and leaks EVERY tenant's rows.
    if ($tenantId === null) { $builder->whereRaw('1 = 0'); return; }
    $builder->where($model->getTable() . '.tenant_id', $tenantId);
}
```

```php
// app/Models/Concerns/BelongsToTenant.php
trait BelongsToTenant
{
    protected static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);          // READ — single registration
        static::creating(function ($model) {              // WRITE — stamp, fail closed
            $tenantId = $model->tenant_id ?? auth()->user()?->tenant_id;
            if ($tenantId === null) {
                throw new \RuntimeException('No tenant context — set tenant_id explicitly in queue/CLI code.');
            }
            $model->tenant_id = $tenantId;                // null `??=` would orphan the row
        });
    }
}

class Invoice extends Model { use BelongsToTenant; }       // trait boots the scope; no #[ScopedBy]
```

**Cross-direction warning (load-bearing).** This heading must warn *both* directions: (1) Django-trained devs **under-trust** Laravel's implicit global scope and re-add manual `->where('tenant_id', …)` everywhere — redundant, and one missed call is a leak; trust the scope (which is exactly why the scope **must fail closed** — a non-HTTP context with no `auth()->user()` would otherwise return every tenant's rows, and "trust the scope" leaves no manual fallback). (2) The real hazard is the **create-path stamping gap** — a global scope filters *reads* but does nothing on *writes*, so a model with the scope but no `creating` stamp inserts rows with a null/foreign `tenant_id` that the scope then hides from everyone (orphans). A read-only guard that *skips* rows is itself a data-shape claim — same failure class as [`RULE_self-sweep §3`](../../rules/RULE_self-sweep-before-push.md): validate it against the producer's real data, not a mock. Reach for `stancl/tenancy` (full-stack: DB/cache/filesystem isolation, DB-per-tenant) or the leaner `spatie/laravel-multitenancy` only when single-column scoping is not enough. See [`references/DATA_ISOLATION_TENANCY.md`](references/DATA_ISOLATION_TENANCY.md).

### Permissions/authorization

Authorization lives in **Policies** (one per model, `make:policy --model`, auto-discovered in Laravel 11+ — no `$policies` array to register) and **Gates** for model-less checks. Enforce structurally: `Gate::authorize()` / `$this->authorize()` in the controller, the `can` middleware on the route, `@can` in Blade. Use `spatie/laravel-permission` only as the *storage* for roles/permissions — the decision still belongs in the policy.

```php
// app/Policies/PostPolicy.php — auto-discovered for the Post model
class PostPolicy
{
    public function viewAny(User $user): bool { return true; }

    public function update(User $user, Post $post): bool
    {
        return $user->id === $post->user_id;
    }
}

// Controller — structural 403 if the gate denies (throws AuthorizationException)
public function update(UpdatePostRequest $request, Post $post): PostResource
{
    $this->authorize('update', $post);
    $post->update($request->validated());
    return new PostResource($post);
}
```

**Anti-pattern to flag:** `if ($user->role === 'admin')` scattered through controllers (no single source of truth); Blade-only gating (`@can`) while the endpoint itself stays open (the API is the real surface); a missing `viewAny` so list endpoints silently authorize everyone. See [`references/POLICIES_GATES.md`](references/POLICIES_GATES.md).

### Testing conventions

**Pest** is the conventional default (`laravel new` prompts for it / `--pest` selects it since Laravel 11); PHPUnit coexists in the same suite and is a perfectly valid choice. Tests split into `tests/Feature` (exercise the HTTP boundary — the most valuable tier) and `tests/Unit`. Use `RefreshDatabase` for a clean schema per test, factories for data, and `php artisan test --parallel` to keep the suite fast.

```php
// tests/Feature/PostTest.php (Pest)
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

it('creates a post for an authenticated user', function () {
    $user = User::factory()->create();           // factory, not hand-built row

    $response = $this->actingAs($user)
        ->postJson('/api/posts', ['title' => 'Hi', 'body' => 'There']);

    $response->assertCreated();
    expect($user->posts()->count())->toBe(1);
});
```

**Anti-pattern to flag:** DB-touching tests without `RefreshDatabase` (state bleeds between tests, order-dependent failures); hand-built rows via `Model::create([...])` instead of factories (brittle, no relationships); over-mocked Unit tests that assert on the mock rather than behaviour. See [`references/PEST_TESTING.md`](references/PEST_TESTING.md).

### Translation workflow

(Optional contract extra — included because every ZF1→Laravel rework hits it.) The spine is **split by ownership**:

- **Developer-owned UI strings** (labels, validation messages, errors) → static `lang/*.php` files resolved through `__()`. Version-controlled, deployed with code, testable. This is the floor.
- **Operator / business-owned + per-tenant content** (booking copy, email templates, per-client customisation) → DB-backed and runtime-editable, but **on rails**: `barryvdh/laravel-translation-manager` (DB store + web UI + import/export, keys still resolve through `__()`) and/or `spatie/laravel-translatable` for per-record attribute translations.

```php
// Developer-owned — static, ships with the bundle, testable:
echo __('messages.welcome', ['name' => $user->name]); // lang/en/messages.php

// Operator-owned — same __() key, but the value lives in a DB-backed manager
// (translation-manager) so non-devs edit + Excel-roundtrip without a deploy.
echo __('booking.confirmation_intro'); // resolves: DB override → file fallback
```

**The dissolving move:** kill the *bespoke* translation engine; keep the *DB-backed editing model* on top of Laravel's `__()` API. **Anti-pattern to flag (codebase-grounded, from a real ZF1→Laravel rework):** never serve UI strings via a per-request translation API backed by a runtime cache — that is static data forced onto a dynamic path, and it spawns a dedicated Redis cache just to survive the load. Compile UI strings to JSON shipped with the frontend bundle, or resolve them server-side via `__()` so they never cross the wire as data. **"If you're caching translations in Redis, that's the smell."** Only genuinely per-tenant/operator content stays a small versioned runtime payload.

## When NOT to use these patterns

- **Non-Laravel PHP** (raw PHP, Symfony, the legacy ZF1 *source* of a rework) — different idioms; Eloquent/Form-Request/Policy patterns do not map.
- **A tiny single-model app or a console-only package** — Form Requests, Policies, and tenant scopes are overhead; plain validation and a single Gate may be enough.
- **Single-tenant by design** — the Data-isolation heading still applies (the answer is "no scoping, document it"), but skip the tenant trait and packages entirely.
- **A Laravel version below 12** — `#[ScopedBy]` (≥ 10.34), policy auto-discovery (≥ 11), and the Pest installer default (≥ 11) are version-gated; verify each against the target's `composer.lock`.

## References

- [Eager loading](references/EAGER_LOADING.md) — N+1 prevention, `with()`/`load()`/`withCount()`, `preventLazyLoading`/`shouldBeStrict` strict mode, `chunkById`/`lazy`/`cursor`, bulk `insert`/`upsert`.
- [Form Requests & Resources](references/FORM_REQUESTS_RESOURCES.md) — the `validated()`-only controller contract, `authorize()`, API Resources, 422 JSON envelope.
- [Queues & Horizon](references/QUEUES_HORIZON.md) — `ShouldQueue`, Redis + Horizon, `afterCommit`, `ShouldBeUnique`/`WithoutOverlapping`, supervised workers, IDs-not-models.
- [Data isolation & tenancy](references/DATA_ISOLATION_TENANCY.md) — global scope + `BelongsToTenant` trait, the create-path stamping gap, `stancl` vs `spatie` comparison, the cross-direction warning expanded.
- [Policies & Gates](references/POLICIES_GATES.md) — policies/gates, auto-discovery, `spatie/laravel-permission` as RBAC storage, structural 403, the `viewAny` gap.
- [Pest testing](references/PEST_TESTING.md) — Pest as the conventional default, Feature vs Unit, `RefreshDatabase`, factories, `--parallel`.
- [Conventions](references/CONVENTIONS.md) — paraphrased Laravel Boost + Spatie style guidelines (defer to the target project's Boost CLAUDE.md if installed).
- [Laravel Documentation](https://laravel.com/docs/12.x)
- [Eloquent Relationships](https://laravel.com/docs/12.x/eloquent-relationships)
- [Pest](https://pestphp.com/docs/installation)
