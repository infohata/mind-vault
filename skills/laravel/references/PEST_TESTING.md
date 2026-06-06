# Pest testing

**Pest** is the conventional default for new Laravel apps — `laravel new` prompts for it, and `--pest` selects it (installer default since Laravel 11, community-verified rather than docs-guaranteed; phrase it as the convention, not an absolute). **PHPUnit coexists** in the same `tests/` tree and remains a fully valid choice; both run under `php artisan test`.

## Feature vs Unit

- `tests/Feature` — exercise the **HTTP boundary** (routes, controllers, middleware, validation, DB). The highest-value tier: one Feature test covers Form Request + policy + Resource + persistence in a single pass.
- `tests/Unit` — pure logic with no framework/DB (a value object, a calculator, a small service). Keep these genuinely isolated.

## Mechanism — a Feature test in Pest

```php
// tests/Feature/PostTest.php
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);              // clean schema per test

it('creates a post for an authenticated user', function () {
    $user = User::factory()->create();     // factory, not a hand-built row

    $response = $this->actingAs($user)
        ->postJson('/api/posts', ['title' => 'Hi', 'body' => 'There']);

    $response->assertCreated()
        ->assertJsonPath('data.title', 'Hi');

    expect($user->posts()->count())->toBe(1);
});

it('rejects an unauthenticated request', function () {
    $this->postJson('/api/posts', [])->assertUnauthorized();
});

it('422s on a missing title', function () {
    $this->actingAs(User::factory()->create())
        ->postJson('/api/posts', ['body' => 'x'])
        ->assertStatus(422)
        ->assertJsonValidationErrors('title');
});
```

The equivalent PHPUnit class extends `Tests\TestCase`, uses the `RefreshDatabase` trait, and uses `$this->assert*` methods — same assertions, different surface.

## `RefreshDatabase` — clean state per test

`RefreshDatabase` wraps each test in a transaction and rolls it back, so tests never see each other's rows. Without it, state bleeds and the suite becomes order-dependent.

```php
// Faster than re-migrating: migrate once, transaction-rollback per test.
uses(RefreshDatabase::class);

// Use a disposable test DB (often SQLite :memory: or a throwaway Postgres):
// phpunit.xml → <env name="DB_CONNECTION" value="sqlite"/>
//               <env name="DB_DATABASE" value=":memory:"/>
```

## Factories — never hand-build rows

```php
// database/factories/PostFactory.php
class PostFactory extends Factory
{
    public function definition(): array
    {
        return [
            'title' => fake()->sentence(),
            'body'  => fake()->paragraph(),
            'user_id' => User::factory(),     // relationship wiring for free
        ];
    }
}

// in a test:
$posts = Post::factory()->count(3)->for($user)->create();
$draft = Post::factory()->draft()->make();   // state method, not persisted
```

## Parallel runs

```bash
php artisan test                # full suite
php artisan test --parallel     # spread across CPU cores (paratest)
php artisan test --filter=PostTest
php artisan test --coverage --min=80
```

`--parallel` gives each worker its own test DB — works cleanly with `RefreshDatabase`. Tests that touch shared external state (a real cache key, a fixed file path) must be parallel-safe or excluded.

## Anti-patterns to flag

- DB-touching tests **without** `RefreshDatabase` (or manual cleanup) — state bleeds, failures are order-dependent and non-reproducible.
- Hand-built rows (`Post::create([...])` with literal data) instead of factories — brittle, no relationship wiring, breaks on the next non-nullable column.
- **Over-mocked Unit tests** that assert on the mock (`$mock->shouldReceive('foo')->once()`) and nothing about real behaviour — they pass while the code is broken. Prefer a Feature test against the real boundary.
- Asserting only the HTTP status and never the persisted side effect (or vice-versa).

## Version note

Pest installer-default since L11 (community-verified). `php artisan test --parallel` (paratest) stable since L8. `RefreshDatabase`, factories, and the `assertJson*` helpers are stable across L9–L12. (L13 drift — Pest 4 / PHPUnit 12 pairing: re-verify the installer prompt and `--coverage` driver if targeting 13.)
