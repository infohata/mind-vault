# IDEA-014 Phase 2 — Laravel deep-research findings (planning input)

**Date:** 2026-06-07 · **Method:** 3-way `mv-researcher` fan-out (landscape · backend idioms · frontend idioms). Supersedes the IDEA's pre-Phase-1 "Phase 2 detail — preserved" section for planning purposes; that section is retained as historical record only.

**Why re-research:** the preserved section was written before Phase 1 shipped `agents/SKILL_CONTRACT.md`. It names backend headings (*Multi-tenancy*, *Translation workflow*) that are NOT the shipped required floor. This doc maps Laravel onto the **actually-shipped** contract.

## The shipped contract is the target (not the IDEA's old guess)

`agents/SKILL_CONTRACT.md` required floor — every stack skill must expose these as literal headings:

- **Backend (6):** ORM eager-loading · Input-validation boundary · Background jobs · Data isolation / scoping boundary · Permissions/authorization · Testing conventions
- **Frontend (4):** Reactivity model · Partial/fragment response · Component system · Form-submission lock

`Translation workflow` is an **optional extra** (the skill keeps it; not required of every stack). Multi-tenancy folds into **Data isolation / scoping boundary**.

## Build-vs-reuse landscape

| Project | Type | License | Decision |
| --- | --- | --- | --- |
| `laravel/boost` | Official MCP server + `.ai/` Blade guidelines | **MIT** | Paraphrase `.ai/foundation` + per-package prose into `references/` (attribute). Do NOT vendor the MCP server. Keep "defer to Boost's CLAUDE.md if installed in target project" note. |
| `spatie/boost-spatie-guidelines` | Guidelines package/skills | **MIT** | Highest-quality style/convention prose → paraphrase into `references/conventions.md`. |
| `jpcaparas/superpowers-laravel` | CC plugin, ~52 skills | **MIT** | Use the 52-skill **taxonomy as a coverage checklist** for which `references/` to write. Don't lift its `/plan`,`/work` workflow skills (clash with mind-vault's own). |
| `agentskills.io` | SKILL.md spec + validator | spec | mind-vault already conforms — cite as the conformance target; optionally run `skills-ref validate`. |
| `PatrickJS/awesome-cursorrules` | `.mdc` rules | **CC0** | Thin; TALL-stack cross-check only. (File bodies NOT verified — repo restructured to `.mdc`.) |
| `noartem/skills` | Laravel + Vue3 skills | **UNVERIFIED ⚠️** | Inspiration only; **do NOT copy text** until a LICENSE is confirmed (the repo's own README says licenses unverified). |

**Ecosystem gaps to author fresh:** multi-tenancy and deep frontend (Inertia/Livewire/Vue) coverage are thin-to-absent across ALL surveyed projects. These are the parts mind-vault must write natively.

**Structural decision:** clone the `skills/django` + `skills/django-frontend` pair heading-for-heading rather than adapting any external — keeps the dispatch contract uniform.

## Backend heading → Laravel mapping (verified vs laravel.com/docs/12.x)

| Contract heading | Laravel mechanism | Enforce (default) | Anti-pattern to flag |
| --- | --- | --- | --- |
| ORM eager-loading | `with()`/`load()`/`loadMissing()`/`withCount()`; `chunkById()`/`lazy()`/`cursor()`; `upsert()`/`insert()` bulk; `Model::preventLazyLoading(!app()->isProduction())` | `with()` every looped relation; strict-mode N+1 throws in dev/CI; `chunkById()` for mutating loops | `$model->rel` in a loop w/o `with()`; `create()` in a loop vs `insert()`/`upsert()`; `chunk()` while mutating the paginated column |
| Input-validation boundary | Form Request (`make:request`) `rules()`+`authorize()`; controller sees only `$request->validated()`; output via API Resources (`JsonResource`) | one Form Request per write endpoint; auto-422-JSON | inline validation in fat controllers; `$request->all()` post-validate; returning raw Eloquent models as JSON |
| Background jobs | `ShouldQueue`+`Queueable`; `dispatch()`/`Bus::chain()`/`Bus::batch()`; Redis + **Horizon**; `ShouldBeUnique`/`WithoutOverlapping`; supervised `queue:work` | Redis+Horizon+Supervisor; `->afterCommit()`; pass IDs not models | dispatch in a txn w/o `afterCommit`; `queue:listen`/unsupervised worker in prod; serializing whole models |
| Data isolation / scoping boundary | global scope via `#[ScopedBy([TenantScope::class])]` + `BelongsToTenant` trait (filter + auto-stamp); packages `stancl/tenancy` (full-stack, single/multi-DB) vs `spatie/laravel-multitenancy` (lean) | `BelongsToTenant` global scope so every query is tenant-filtered by default; package only when connection/cache/FS isolation or DB-per-tenant needed | hand-written `->where('tenant_id', …)` per query (one miss = leak); scope filters reads but create path forgets to stamp `tenant_id` (orphan rows) |
| Permissions/authorization | Policies (`make:policy --model`, auto-discovered) per-model; Gates for model-less; enforce `Gate::authorize()`/`can` middleware/`@can`; `spatie/laravel-permission` for RBAC storage | Policies canonical; structural 403 via `Gate::authorize()`; keep decisions in policies even when roles in spatie-permission | `if ($user->role==='admin')` scattered; Blade-only gating w/ endpoint open; missing `viewAny` |
| Testing conventions | **Pest** (conventional default since L11) over PHPUnit; `tests/Feature`(HTTP)+`tests/Unit`; `php artisan test --parallel`; `RefreshDatabase`; factories | Pest + Feature tests at HTTP boundary + `RefreshDatabase` + factories; `--parallel` + disposable test DB | DB tests w/o `RefreshDatabase`; hand-built rows vs factories; over-mocked Unit tests asserting nothing |

**Version sensitivity:** `preventLazyLoading`/`shouldBeStrict` ≥ L8.43; `database` default queue connection since L11; `#[ScopedBy]` ≥ L10.34; AuthServiceProvider `$policies` array removed (auto-discovery) in L11; Pest installer-default since L11 (community-verified, not docs-stated — phrase as "conventional default"). Docs banner now steers to L13 — re-verify version-sensitive lines if plan targets 13.

**Fundamental Django↔Laravel stress point (flag in plan):** Data isolation is the heading that most stresses the contract. Django's instinct is *schema routing* (separate Postgres schemas) + explicit QuerySet scoping; Laravel's idiom is *implicit global scopes that silently rewrite every query*. The anti-pattern guidance must warn **both directions** — Django devs under-trust the global scope (re-add manual `where`), while the real hazard is the create-path stamping gap (scope filters reads, forgotten `tenant_id` on write orphans rows). Structurally identical to `RULE_self-sweep §3` (a discard/skip guard is a data-shape claim) — cross-reference it. Secondarily, `preventLazyLoading` has **no Django analog** — present as a Laravel-native superpower, not a mapping.

## Frontend heading → Laravel mapping

**Stack fork (surface up front):** Breeze/Jetstream era is over. Laravel 12 first-party starter kits = **Livewire 4 (+Flux UI)** and **Inertia 2** (Vue 3 / React 19 / Svelte 5 + shadcn). **Recommendation: center `laravel-frontend` on Livewire+Flux as DEFAULT** (philosophical 1:1 with django-frontend's server-driven thesis), with **Inertia** and **plain Blade+HTMX/Alpine** as documented adapter variants (announce on dispatch).

| Contract heading | Livewire (default) | Adapter: Inertia 2 | Adapter: Blade+HTMX (Django twin) |
| --- | --- | --- | --- |
| Reactivity model | PHP public props ↔ DOM via `wire:model` (deferred); `wire:click`/`wire:submit`; bundled Alpine `x-data` for local-only. ANTI: `wire:model.live` on every input | Vue refs / React `useState`; JSON props | Alpine `x-data`/`x-model` |
| Partial/fragment response | automatic — component re-render + server DOM diff. ANTI: hand-rolling `@fragment` in a Livewire project | `router.reload({ only:[…] })`/`except:` | `@fragment`+`->fragmentIf($request->hasHeader('HX-Request'),'x')` (≈ Django HTMXMixin) |
| Component system | Blade components (`<x-…>`, class-based + anonymous, `<x-slot>`); UI kit = **Flux** (`<flux:…>`). ANTI: Flux **Pro** components (chart/date-picker/editor) w/o paid license = CI build gate | Vue/React/Svelte SFC + shadcn (`npx shadcn add`) | Blade components / django-cotton analog |
| Form-submission lock | **AUTOMATIC** — `wire:submit` disables button + `readonly` inputs in-flight; add `wire:loading.delay`/`wire:target`/`wire:dirty.class`. ANTI: stacking a manual Alpine lock on a `wire:submit` form (desync) | `:disabled="form.processing"` | Alpine `x-data:{submitting}` |

**Version sensitivity:** pin Laravel ≥12 for starter-kit assumptions (Breeze/Jetstream = legacy); Livewire ≥3 target 4 (`wire:submit` self-prevents in v3/4; `wire:model` deferred-by-default from v3, was live in v2); Inertia 2 (lazy/deferred props); **Flux is freemium + Livewire-version-coupled** — Pro license gate is a real CI hazard, flag Pro components as license-sensitive.

**Unverified flags:** Flux `<flux:button>` namespace inferred from starter-kit docs, not a rendered code sample — verify at `fluxui.dev/docs` before hardcoding tags. Inertia `form.processing` cited from general knowledge — confirm at `inertiajs.com/forms`.

## Refined open questions for /plan

1. **laravel-frontend shape**: single SKILL.md with Livewire default + Inertia/Blade adapter sections, vs. a dispatcher that hard-forks? (Lean: one SKILL, default + adapter-variant sections, mirroring how django-frontend handles HTMX/Alpine/cotton in one skill.)
2. **References to write** (from the superpowers-laravel taxonomy checklist, gaps authored fresh): backend — eloquent-eager-loading, form-requests-resources, queues-horizon, data-isolation-tenancy (fresh), policies-gates, pest-testing, conventions (paraphrased Boost+Spatie). frontend — livewire-loading-states, blade-fragments-htmx (Django twin), flux-license-gating (fresh), inertia-partial-reloads.
3. **Detection**: inline documented signals (`composer.json`+`artisan`) already in `persona-dispatch.md` — does Phase 2 need the deferred `tools/detect-stack.sh`, or do the documented signals suffice for the proof? (Lean: documented signals suffice; defer the script.)
4. **Filament** admin — own skill vs a `laravel-frontend` reference vs out-of-scope for the proof. (Lean: out-of-scope for the zero-edit proof; note as follow-up IDEA.)
5. **The zero-agent-edit proof gate**: how do we *demonstrate* it? A verification log (mirroring Phase 1's line-conservation log) asserting the 10 headings resolve + zero `git diff` on `agents/`. What's the concrete check?
6. **Translation workflow** (optional extra) — include a Laravel localization section or omit for the proof? (Lean: omit from required scope; optional extra, add only if cheap.)
7. **Version pinning** — target Laravel 12 (current starter kits) and note 13 drift, or target 13? (Lean: 12 as the verified baseline, note 13.)

## Sources
- laravel.com/docs/12.x: eloquent-relationships, eloquent, validation, queues, authorization, testing · pestphp.com/docs/installation · tenancyforlaravel.com · spatie.be/docs/laravel-multitenancy · spatie.be/docs/laravel-permission
- github.com/laravel/boost (+ /tree/main/.ai) · laravel.com/ai/boost · github.com/jpcaparas/superpowers-laravel · agentskills.io/specification · github.com/spatie/boost-spatie-guidelines · github.com/PatrickJS/awesome-cursorrules · github.com/noartem/skills
- laravel.com/docs/12.x/starter-kits · /blade · livewire.laravel.com/docs (quickstart, wire-loading, wire-dirty) · inertiajs.com/partial-reloads · fluxui.dev
