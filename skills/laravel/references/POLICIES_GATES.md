# Policies & Gates — authorization

"Is this caller allowed?" has exactly one source of truth per resource: a **Policy** (model-scoped) or a **Gate** (model-less). Authorization is enforced structurally at the request boundary, not re-derived ad hoc in controllers or templates.

## Policies — one per model

```php
// php artisan make:policy PostPolicy --model=Post
class PostPolicy
{
    // Called for list/index endpoints — easy to forget, easy leak.
    public function viewAny(User $user): bool
    {
        return true;
    }

    public function view(User $user, Post $post): bool
    {
        return true;
    }

    public function update(User $user, Post $post): bool
    {
        return $user->id === $post->user_id;
    }

    public function delete(User $user, Post $post): bool
    {
        return $user->id === $post->user_id || $user->can('posts.delete');
    }

    // Runs before every ability — global override (super-admin).
    public function before(User $user, string $ability): ?bool
    {
        return $user->is_super_admin ? true : null; // null = fall through
    }
}
```

**Auto-discovery (L11+):** Laravel maps `App\Models\Post` → `App\Policies\PostPolicy` by convention — no `$policies` array in a provider to register. (Pre-L11 you registered the map in `AuthServiceProvider::$policies`.) Override the mapping with `Gate::policy()` only when names diverge.

## Gates — model-less checks

```php
// app/Providers/AppServiceProvider.php — boot()
Gate::define('view-admin-dashboard', fn (User $user) => $user->is_staff);
```

## Enforce structurally — three surfaces, one decision

```php
// 1. Controller — throws AuthorizationException → 403 (structural, not a flag)
public function update(UpdatePostRequest $request, Post $post): PostResource
{
    $this->authorize('update', $post);   // or Gate::authorize('update', $post)
    $post->update($request->validated());
    return new PostResource($post);
}

// 2. Route middleware — gate before the controller even runs
Route::put('/posts/{post}', [PostController::class, 'update'])
    ->middleware('can:update,post');

// 3. Form Request authorize() — coarse class-level gate (see FORM_REQUESTS_RESOURCES.md)
public function authorize(): bool
{
    return $this->user()->can('create', Post::class);
}
```

Blade `@can('update', $post) ... @endcan` only hides UI — it is **never** the enforcement point. The endpoint must gate independently.

## RBAC storage — `spatie/laravel-permission`

For role/permission *storage* (DB tables, role assignment, caching), use `spatie/laravel-permission`. Keep the **decision** in the policy — the package supplies the data, the policy supplies the logic.

```php
$user->assignRole('editor');
$user->givePermissionTo('posts.publish');

// Policy still owns the decision; it just consults spatie for the fact:
public function publish(User $user, Post $post): bool
{
    return $user->can('posts.publish') && $post->tenant_id === $user->tenant_id;
}
```

## Anti-patterns to flag

- `if ($user->role === 'admin')` (or `=== 'editor'`, etc.) scattered through controllers — no single source of truth, drifts the moment roles change. Move it into a policy/gate.
- **Blade-only gating with the endpoint left open** — `@can` hides the button but the route still accepts the request. The API is the real attack surface; gate it.
- **Missing `viewAny`** — list/index endpoints silently authorize everyone because the ability was never defined. Every resource policy needs `viewAny`.
- Re-deriving a policy's logic in a second place (a console command, a job, a fragment endpoint) instead of calling `Gate::allows('update', $post)` — copies drift, and a copy that authorizes on the wrong field is a silent bypass.

## Reviewer grep

- `$user->role ===` / `->role ==` in controllers/jobs.
- A controller `update`/`destroy`/`store` method with no `$this->authorize(`/`Gate::` and no `can:` middleware on its route.
- A policy file missing `viewAny`.

## Version note

Policy auto-discovery (no `$policies` array) is Laravel 11+. On L9/L10 register policies in `AuthServiceProvider::$policies`. `before()`, `Gate::authorize`, and `can:` middleware are stable across L9–L12. (L13 drift — re-verify auto-discovery conventions if targeting 13.)
