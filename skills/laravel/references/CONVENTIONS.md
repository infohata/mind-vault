# Conventions — Laravel style baseline

Paraphrased house style for Laravel 12 work, distilled from Laravel Boost's foundation guidelines and Spatie's Laravel guidelines. These are defaults, not laws — **if the target project ships a Laravel Boost `CLAUDE.md` (or `.ai/`), defer to it**; it encodes that team's choices and overrides anything here.

> All guidance below is **paraphrased** from MIT-licensed sources (attributed in the `Sources:` footer). No text is lifted verbatim from any source, and nothing is taken from license-unverified projects.

## Use the framework, don't fight it

- Reach for first-party features before pulling a package: queues, events, notifications, scheduling, cache, storage, validation, policies all ship in core.
- Generate scaffolding with `artisan make:*` (`make:model -mfsc` wires migration, factory, seeder, controller in one go) so files land in conventional locations with conventional names.
- Check `composer.json` / `composer.lock` for the actual installed versions before assuming an API exists — match the project's Laravel and PHP version, don't guess.

## Naming & structure

- **Models** singular PascalCase (`Post`, `OrderLine`); **tables** plural snake_case (`posts`, `order_lines`); **pivot tables** the two singular models alphabetical (`post_tag`).
- **Controllers** plural-resource + `Controller` suffix (`PostsController` or `PostController` — follow the project's existing choice); keep them thin (resourceful actions, delegate logic out).
- **Form Requests** `{Verb}{Model}Request` (`StorePostRequest`); **Resources** `{Model}Resource`; **Policies** `{Model}Policy`; **Jobs** verb-phrase (`ProcessPodcast`).
- Routes named with dot notation (`posts.store`); use route-model binding (`Route::resource`) rather than manual `find()` in the controller.

## Fat controllers are a smell

Logic that spans multiple models, calls an external service, or sends mail belongs in a **service / action class** or a model method — not in the controller and not in a Resource. The controller orchestrates: resolve the validated request, hand off, return a Resource. (This is the same Service-Layer extraction the backend persona enforces.)

```php
// ✅ thin controller delegating to an action class
public function store(StorePostRequest $request, PublishPost $action): PostResource
{
    return new PostResource($action->execute($request->validated()));
}
```

## Migrations & schema

- One concern per migration; never edit a shipped migration — add a new one.
- Index every foreign key; declare `foreignId(...)->constrained()->cascadeOnDelete()` (or `restrictOnDelete()`) explicitly so deletion behaviour is intentional.
- Prefer `timestamps()` on every table (the `created_at`/`updated_at` audit pair) unless there is a reason not to.

## Types, formatting, tooling

- PHP 8.2+: typed properties, constructor property promotion, typed args and return types on every method, enums over magic strings.
- Format with **Laravel Pint** (`./vendor/bin/pint`) — the project's `pint.json` (or the default preset) is the arbiter; don't hand-format.
- Static analysis with PHPStan / Larastan where the project runs it; match the configured level.

## Don't reinvent

- Validation → Form Requests (see [`FORM_REQUESTS_RESOURCES.md`](FORM_REQUESTS_RESOURCES.md)).
- Authorization → Policies/Gates (see [`POLICIES_GATES.md`](POLICIES_GATES.md)).
- Deferred work → queued jobs (see [`QUEUES_HORIZON.md`](QUEUES_HORIZON.md)).
- Tenant scoping → global scope + trait (see [`DATA_ISOLATION_TENANCY.md`](DATA_ISOLATION_TENANCY.md)).
- Tests → Pest + factories + `RefreshDatabase` (see [`PEST_TESTING.md`](PEST_TESTING.md)).

## Anti-patterns to flag

- Business logic in a controller, Resource, or Blade template.
- Raw SQL string concatenation with request input (use the query builder / Eloquent bindings).
- Editing a previously-shipped migration instead of adding a new one.
- Hand-formatting instead of running Pint; ignoring the project's PHPStan level.
- Adding a package for something core already provides.

---

**Sources:** Paraphrased from **Laravel Boost** `.ai/foundation` guidelines (MIT, `github.com/laravel/boost`) and the **Spatie Laravel guidelines** / `spatie/boost-spatie-guidelines` (MIT, `spatie.be/guidelines/laravel-php`). Both are MIT-licensed; this file restates their guidance in original wording with attribution and copies no text verbatim. License-unverified sources (e.g. `noartem/skills`) contributed nothing to this file.
