# Eager loading — N+1 prevention & bulk writes

Eloquent relations are **lazy by default**: accessing `$model->relation` fires a query the first time. Inside a loop that is one query per row — the classic N+1. The fix is to declare the relations you will traverse up front, and to make accidental lazy loads loud in dev/CI.

## Mechanism — eager load every traversed relation

```php
// ❌ N+1 — 1 query for posts, then 1 per post for the author = N+1
$posts = Post::all();
foreach ($posts as $post) {
    echo $post->author->name;
}

// ✅ 2 queries total, regardless of row count
$posts = Post::with('author')->get();

// ✅ nested + constrained eager load
$posts = Post::with([
    'author',
    'comments' => fn ($q) => $q->where('approved', true)->latest(),
    'comments.user',
])->get();

// ✅ counts without loading the rows
$posts = Post::withCount('comments')->get();   // $post->comments_count
```

### Top-up an already-fetched model

`load()` re-loads even if present; `loadMissing()` only loads relations not already eager-loaded — prefer it to avoid redundant queries.

```php
$post = Post::findOrFail($id);
$post->loadMissing('author', 'tags');   // idempotent top-up
```

## Default to enforce — strict mode (the Laravel-native superpower)

Django has **no runtime analog** to this. `assertNumQueries` is opt-in per test; `preventLazyLoading` is global and automatic. Turn lazy loads into exceptions everywhere except production:

```php
// app/Providers/AppServiceProvider.php — boot()
use Illuminate\Database\Eloquent\Model;

public function boot(): void
{
    // Narrow: only lazy loading throws.
    Model::preventLazyLoading(! $this->app->isProduction());

    // Broad: lazy loads + assigning unfillable attributes + accessing
    // attributes that weren't retrieved all throw. Recommended for new apps.
    Model::shouldBeStrict(! $this->app->isProduction());
}
```

With this on, the N+1 example above throws `LazyLoadingViolationException` in tests/local — the bug surfaces at author time, not as a slow endpoint in prod.

## Large sets — chunk / lazy / cursor

Loading 100k rows into memory OOMs the worker. Stream instead:

```php
// ✅ chunkById — stable cursor by PK; safe even while mutating rows
Post::where('archived', false)->chunkById(500, function ($posts) {
    foreach ($posts as $post) { /* ... */ }
});

// ✅ lazy() — a LazyCollection, one row hydrated at a time, fluent API
Post::where('archived', false)->lazy()->each(fn ($p) => /* ... */);

// ✅ cursor() — single query, lowest memory, but NO eager loading
foreach (Post::where('archived', false)->cursor() as $post) { /* ... */ }
```

**Anti-pattern:** `chunk()` (offset-based) while mutating the paginated column — rows shift between pages and you skip records. Always `chunkById()` for mutating loops.

## Bulk writes — never `create()` in a loop

```php
// ❌ N round-trips, N sets of events/timestamps
foreach ($rows as $row) {
    Post::create($row);
}

// ✅ one INSERT (skips casts, mutators, timestamps, model events — by design)
Post::insert($rows);

// ✅ insert-or-update on a unique key, one statement
Post::upsert(
    $rows,
    ['slug'],            // unique-by columns
    ['title', 'body'],   // columns to update on conflict
);
```

**Caveat — bulk ops bypass the model layer.** `insert()`/`upsert()`/mass `update()` issue SQL directly: no `created_at`/`updated_at`, no `creating`/`saving` events, no observers, no casts. If timestamps matter, include them in the payload explicitly. (Structurally identical to Django's `.update()`/`bulk_create` model-layer-bypass caveat.) A tenant `creating` stamp — see [`DATA_ISOLATION_TENANCY.md`](DATA_ISOLATION_TENANCY.md) — is also skipped, so bulk-inserting tenant rows requires stamping `tenant_id` in the payload yourself.

## Reviewer grep

- `foreach` body dereferencing a relation with no `with()` on the source query.
- `->create(` inside a `foreach`/`for`/`while`.
- `chunk(` (vs `chunkById`) near an `update`/`save` in the closure.

## Version note

`preventLazyLoading` / `shouldBeStrict` are available since Laravel 8.43 — solid on the L12 baseline. (L13 drift — re-verify the strict-mode helper names against laravel.com/docs/13.x if targeting 13.)
