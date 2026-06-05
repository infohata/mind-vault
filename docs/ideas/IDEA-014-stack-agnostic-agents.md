---
id: IDEA-014
title: Stack-agnostic agent architecture + Laravel proving stack
status: idea
priority: medium
supersedes: []
superseded_by: null
depends_on: []
related: [IDEA-011]
created: 2026-05-20
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false
auto_safe_reason: "Cross-cutting refactor of 8 agent profiles + the craft/stack taxonomy + a detection mechanism — heavy design judgment (what is craft vs stack, the skill-contract heading set, detection signals). Must go through /plan + architect review before any unattended run."
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Scope is confined to agents/, skills/, docs/, and a possible tools/ detection helper — no auth, permission, schema, infra, secrets, or payment paths. mind-vault has no app runtime to touch."
---

# IDEA-014: Stack-agnostic agent architecture + Laravel proving stack

## Problem

mind-vault's subagent profiles are generically **named** (`mv-backend`, `mv-frontend`, …) but their **bodies are hard-wired to Django**: each carries a literal `**Stack profile:** Django + django-tenants + DRF + Celery` line, and the 5-pass workflows enforce `select_related`/`prefetch_related`, DRF serializers, HTMX/Alpine/Bulma by name. Stack-coupling count today: `mv-frontend` 9 mentions, `mv-curator` 11, `mv-test-engineer` 5, `mv-backend` 4.

Consequences:

- Stack specifics are **duplicated** — partly in the agent body, partly in `skills/django` + `skills/django-frontend` — and the two can drift.
- Dropping in a new stack (Laravel, Node, Go) means an agent that is **schizophrenic** on that repo: a `mv-backend` that insists on "Django ORM" while editing Eloquent models.
- Adding any stack is an N×M edit across every profile instead of a single skill drop-in.

## Core principle — split craft from stack

Every persona splits into two layers:

- **Craft** (stack-agnostic engineering judgment) → **stays in the agent profile**.
- **Stack enforcement** (concrete framework rules) → **unloaded to skills**.

A generic `mv-backend` then works *any* backend stack by loading that repo's active backend skill for the concrete rules. (Chosen mechanism: **craft core + skill-pointer**, not a thin dispatcher and not per-stack profile forks.)

### The craft / stack cut

| Stays in agent (craft) | Moves to skill (stack) |
|---|---|
| No fat controllers/views; service-layer extraction | `select_related`/`prefetch_related` vs Eloquent `with()`/`load()` |
| Eager-load relations / zero N+1 **as a concept** | DRF serializers vs Form Requests + Resources |
| Never trust raw strings; parameterized boundaries | Celery vs Horizon / queues |
| Bulk operations at volume | django-tenants vs Laravel multi-tenancy package |
| Server-driven UI preference; defend global scope; idempotent submissions; accessibility | HTMX / Alpine / Bulma vs Livewire / Inertia / Blade |

## Skill contract — the interface

For the generic agent's **Stack adapter** pointer to resolve uniformly, every backend skill exposes the **same anchor headings** (e.g. *ORM eager-loading*, *Input-validation boundary*, *Background jobs*, *Multi-tenancy*, *Translation workflow*); every frontend skill exposes its own set (e.g. *Reactivity model*, *Partial/fragment response*, *Component system*, *Form submission lock*). The agent references the heading; the skill fills the stack-specific content. **This contract is what makes Phase 2 a zero-agent-edit drop-in.** Defining the exact heading set is the central `/plan`-stage deliverable.

## Stack resolution

Resolve the active stack per repo, override-first:

1. `.claude/dispatch.md` pin (`stack: laravel`) — wins if present (reuses the existing project-override hook).
2. `AGENTS.md` pin.
3. Auto-detect signals — `manage.py`/`settings.py` → django; `composer.json` + `artisan` → laravel; `package.json` frameworks → node/etc.
4. None / ambiguous → ask the user once.

A small `tools/detect-stack.sh` analogue (vs inline documented signals) is a `/plan` open question.

## Phasing — RULE_rename-before-drop applies (this is an extraction refactor)

### Phase 1 — Generalize (Django stays green)

Per [`RULE_rename-before-drop`](../../rules/RULE_rename-before-drop.md), move **before** dropping:

1. Move the Django-specific rules **into** `skills/django` + `skills/django-frontend` under the contract headings (they're partly there already); verify green.
2. **Then** strip the stack bodies from the profiles down to craft cores + a `## Stack adapter` section.
3. Add stack resolution (detection + override order above).
4. Full pass — Django is the **regression guard**; behaviour on Django repos must be unchanged.

Stack-heavy profiles needing surgery: **`mv-backend`, `mv-frontend`, `mv-curator`, `mv-test-engineer`**. Already-generic (`mv-devops`, `mv-documentation`, `mv-researcher`, `mv-architect`) need only light touch-ups + the adapter section where relevant.

### Phase 2 — Laravel proves it (zero agent edits)

Add `skills/laravel` + `skills/laravel-frontend` conforming to the skill contract. Detection picks up `composer.json`; **no agent profile is touched** — that is the proof the architecture holds. This phase absorbs the original Laravel landscape research intact (below).

---

## Phase 2 detail — Laravel skill landscape (original research, preserved)

### Approach — hybrid: defer to Laravel Boost, derive mind-vault conventions on top

Don't vendor any existing skill pack wholesale. Build a thin pair that anchors on the official ecosystem:

- **Anchor**: [`laravel/boost`](https://github.com/laravel/boost) (MIT, 3.5k★) — Laravel core team's MCP-server-based skill pack, auto-detects Livewire / Inertia / Tailwind / Filament / Pest / Pint versions per project, generates `CLAUDE.md` + `.mcp.json` at `boost:install`. *De facto* what serious Laravel projects already have.
- **Standard fit**: [agentskills.io](https://agentskills.io/) uses the exact `SKILL.md` + `references/` + `assets/` layout mind-vault already uses — no structural translation needed.
- **Mine for references/**: [`jpcaparas/superpowers-laravel`](https://github.com/jpcaparas/superpowers-laravel) (MIT, 131★) — best community Laravel skill collection, closest shape to mind-vault. Covers form requests, policies, Eloquent relationships, transactions, HTTP client, scheduling, API resources, Blade, uploads, rate-limiting.

### Concrete deliverables

1. **`skills/laravel/SKILL.md`** (thin, ~150–250 lines) — fills the backend skill contract headings with Laravel content:
   - Service container + facades + dependency injection
   - Eloquent N+1 discipline (`with()`/`load()`, not `select_related()`), polymorphic relations vs generic FK, scopes vs managers
   - Form Requests + Resources (vs DRF serializers / ModelSerializer)
   - Artisan command conventions
   - Queue/Horizon basics (vs Celery)
   - Multi-tenancy (mirror the Django skill's section)
   - Translation workflow
2. **`skills/laravel/references/`** — mined from `jpcaparas/superpowers-laravel` with attribution headers: `form-requests.md`, `policies.md`, `eloquent-relationships.md`, `queues-horizon.md`, `pest-testing.md`, `api-resources.md`.
3. **`skills/laravel-frontend/SKILL.md`** — **dispatcher**, not single-stack assumption. Detect from `composer.json`:
   - Livewire (≈ HTMX mental model — Laravel's first-party pick, default pairing)
   - Inertia (React/Vue/Svelte SPA bridge)
   - Blade-only
   - Filament admin (orthogonal — its own reference)
4. **`skills/laravel-frontend/references/`** — `livewire.md`, `inertia.md`, `filament.md`, `tailwind.md`, `alpine.md`.
5. **Top-level note in `skills/laravel/SKILL.md`**: *"If Boost is installed in the target project, defer to its `CLAUDE.md` for version-specific guidance. mind-vault carries cross-project conventions only."* Same compositional discipline as the Django split.

### Explicit non-goals

- ❌ Wholesale vendoring of `iSerter/laravel-claude-agents` — its role-based agent split (architect/reviewer/debugger) doesn't match mind-vault's skill model (one `mv-backend`, dispatched by skill, not 10 role agents).
- ❌ Mirroring `JustSteveKing/laravel-api-skill`'s opinionated `Actions/Payloads/Responses` pattern — too project-specific to bake into a cross-project skill.
- ❌ Fighting Boost. If Boost ships version-specific guidance, defer; mind-vault carries only what Boost won't.

### Adoption signal — top candidates surveyed (all MIT)

| Repo | Stars | Shape | Decision |
|------|-------|-------|----------|
| `laravel/boost` | 3.5k | MCP + auto-detect guidelines | **Anchor — defer to it** |
| `laravel/agent-skills` | 622 | Meta-pack | Thin on Eloquent/Pest/Filament — skip |
| `jpcaparas/superpowers-laravel` | 131 | Per-skill SKILL.md | **Mine for references/** |
| `iSerter/laravel-claude-agents` | 37 | Role-based agents | Wrong shape — skip |
| `JustSteveKing/laravel-api-skill` | 22 | REST-only | Too narrow — skip |
| `PatrickJS/awesome-cursorrules` Laravel entries | n/a | Monolithic `.cursorrules` | Content reference only |

---

## Cohort fit

Cross-cutting architectural refactor (Phase 1) + a standalone new stack (Phase 2). Phase 1 is the heavy lift and the gate; Phase 2 is additive once the contract exists. Likely 3+ PRs (extract-to-django, strip-profiles+detection, laravel pair) per `rename-before-drop` sequencing.

## Relationship to IDEA-011

[IDEA-011](../archive/2026-06-idea-011-agent-profiles-subagent-schema/IDEA-011-agent-profiles-subagent-schema.md) already gave the profiles generic `mv-<persona>` **names** and the recognized subagent schema. This idea completes that arc by making the profile **bodies** generic too — names without Django-coupled content.

## Open questions for /plan stage

- The exact **skill-contract heading set** for backend and frontend skills (the interface every stack skill must satisfy). This is the central design artifact.
- Detection mechanism form: inline documented signals vs a `tools/detect-stack.sh` helper vs a resolver baked into the `/work` dispatch step.
- How `mv-curator` and `mv-test-engineer` (review/test personas) express their stack adapter — they assert on stack idioms, not author them, so their adapter shape may differ from backend/frontend.
- Filament-as-own-skill (`skills/laravel-filament/`) vs a reference under `laravel-frontend/` — admin-only, arguably orthogonal.
- Pest-only vs Pest+PHPUnit references (Pest is the modern default; PHPUnit ships in legacy projects).
- Does mind-vault want a `tools/setup-laravel-boost.sh` analogue to the playwright bootstrap script for green-field Laravel projects?
