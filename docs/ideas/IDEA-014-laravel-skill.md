---
id: IDEA-014
title: Laravel skill — backend + frontend dispatcher pair
status: idea
priority: medium
supersedes: []
superseded_by: null
depends_on: []
related: []
created: 2026-05-20
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "Greenfield skill-authoring with open design judgment calls — which references to mine, Filament-as-own-skill vs reference, Pest-only vs Pest+PHPUnit, and whether to add a setup-laravel-boost.sh bootstrap. Resolve in /plan before any unattended run."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Scope is confined to skills/laravel*, docs/, and (possibly) a new tools/ bootstrap script — no auth, permission, schema, infra, secrets, or payment paths. mind-vault has no app runtime to touch."
---

# IDEA-014: Laravel skill — backend + frontend dispatcher pair

## Problem

mind-vault carries first-class `skills/django/` + `skills/django-frontend/` for the Python/Django stack but nothing for PHP/Laravel. Cross-stack engineers (or agents handed a Laravel codebase) lose the same conventions-and-references productivity boost.

## Approach — hybrid: defer to Laravel Boost, derive mind-vault conventions on top

Don't vendor any existing skill pack wholesale. Build a thin pair that anchors on the official ecosystem:

- **Anchor**: [`laravel/boost`](https://github.com/laravel/boost) (MIT, 3.5k★) — Laravel core team's MCP-server-based skill pack, auto-detects Livewire / Inertia / Tailwind / Filament / Pest / Pint versions per project, generates `CLAUDE.md` + `.mcp.json` at `boost:install`. *De facto* what serious Laravel projects already have.
- **Standard fit**: [agentskills.io](https://agentskills.io/) uses the exact `SKILL.md` + `references/` + `assets/` layout mind-vault already uses — no structural translation needed.
- **Mine for references/**: [`jpcaparas/superpowers-laravel`](https://github.com/jpcaparas/superpowers-laravel) (MIT, 131★) — best community Laravel skill collection, closest shape to mind-vault. Covers form requests, policies, Eloquent relationships, transactions, HTTP client, scheduling, API resources, Blade, uploads, rate-limiting.

## Concrete deliverables

1. **`skills/laravel/SKILL.md`** (thin, ~150–250 lines) — mirrors `skills/django/SKILL.md` headings 1:1 where concepts map; adds Laravel-only sections explicitly:
   - Service container + facades + dependency injection
   - Eloquent N+1 discipline (`with()` not `select_related()`), polymorphic relations vs generic FK, scopes vs managers
   - Form Requests + Resources (vs DRF serializers / ModelSerializer)
   - Artisan command conventions
   - Queue/Horizon basics (vs Celery)
   - Multi-tenancy (mirror Django skill's section)
   - Translation workflow
2. **`skills/laravel/references/`** — mined from `jpcaparas/superpowers-laravel` with attribution headers:
   - `form-requests.md`
   - `policies.md`
   - `eloquent-relationships.md`
   - `queues-horizon.md`
   - `pest-testing.md`
   - `api-resources.md`
3. **`skills/laravel-frontend/SKILL.md`** — **dispatcher**, not single-stack assumption. Detect from `composer.json`:
   - Livewire (≈ HTMX mental model — Laravel's first-party pick, default pairing)
   - Inertia (React/Vue/Svelte SPA bridge)
   - Blade-only
   - Filament admin (orthogonal — its own reference)
4. **`skills/laravel-frontend/references/`** — `livewire.md`, `inertia.md`, `filament.md`, `tailwind.md`, `alpine.md`.
5. **Top-level note in `skills/laravel/SKILL.md`**: *"If Boost is installed in the target project, defer to its `CLAUDE.md` for version-specific guidance. mind-vault carries cross-project conventions only."* Same compositional discipline as the Django split.

## Explicit non-goals

- ❌ Wholesale vendoring of `iSerter/laravel-claude-agents` — its role-based agent split (architect/reviewer/debugger) doesn't match mind-vault's skill model (one `AGENT_backend`, dispatched by skill, not 10 role agents).
- ❌ Mirroring `JustSteveKing/laravel-api-skill`'s opinionated `Actions/Payloads/Responses` pattern — too project-specific to bake into a cross-project skill.
- ❌ Fighting Boost. If Boost ships version-specific guidance, defer; mind-vault carries only what Boost won't (cross-project conventions, multi-tenancy patterns, etc.).

## Adoption signal — top candidates surveyed (all MIT)

| Repo | Stars | Shape | Decision |
|------|-------|-------|----------|
| `laravel/boost` | 3.5k | MCP + auto-detect guidelines | **Anchor — defer to it** |
| `laravel/agent-skills` | 622 | Meta-pack | Thin on Eloquent/Pest/Filament — skip |
| `jpcaparas/superpowers-laravel` | 131 | Per-skill SKILL.md | **Mine for references/** |
| `iSerter/laravel-claude-agents` | 37 | Role-based agents | Wrong shape — skip |
| `JustSteveKing/laravel-api-skill` | 22 | REST-only | Too narrow — skip |
| `PatrickJS/awesome-cursorrules` Laravel entries | n/a | Monolithic `.cursorrules` | Content reference only |

## Cohort fit

Mid-size standalone IDEA. No dependencies. Auto-safe candidate once plan exists. Likely splits into two PRs (one per skill) or single bundled PR depending on plan-stage scoping.

## Open questions for /plan stage

- Does mind-vault want a `tools/setup-laravel-boost.sh` analogue to the playwright bootstrap script? (Probably yes — green-field Laravel projects benefit.)
- Should Filament get its own top-level skill (`skills/laravel-filament/`) instead of being a reference under `laravel-frontend/`? Filament is admin-only and arguably orthogonal to user-facing frontend.
- Pest vs PHPUnit reference — both or just Pest? (Pest is the modern default; PHPUnit still ships in legacy projects.)
