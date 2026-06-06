# IDEA-014 Phase 2 — verification log (the proof)

**Date:** 2026-06-07 · **Branch:** `feat/idea-014-phase2-laravel` · **Mirrors:** Phase 1's
line-conservation log. This is the structural proof gate (Open Q1 — v5 ships on this +
fast-follow, NOT on a live-repo run). It records: (a) the empty `agents/` diff, (b) all 10
contract headings resolving as non-stub `###` sections, (c) the content-resolution dispatch
dry-run (the *rule* each generic agent extracts, not mere heading presence), (d) body line
counts, and (e) the explicit content-correctness residual.

## (a) R4 — THE PROOF: zero agent-profile edits

```console
$ git diff --stat origin/main...HEAD -- agents/
$ echo $?
0
```

Empty output. **No `agents/AGENT_*.md` was touched.** A second, structurally-different stack
(Laravel) dropped in by adding only `skills/` content — the craft/stack split holds. This is
the deliverable: not that the architecture was designed, but that it survives a real second
stack with zero changes to any persona.

## (b) R1/R2/R3 — all 10 headings resolve as NON-STUB `###` sections

Heading strings are **verbatim-identical to Django's** (they are the grep-resolved cross-stack
interface). The anti-tautology awk gate (architect MUST-FIX 1) asserts each section carries a
code fence **and** ≥8 non-blank lines before the next `###` — a bare heading FAILS.

**Backend — `skills/laravel/SKILL.md`** (6 required + 1 optional extra):

| Heading (`###`) | non-blank lines | code fences | gate |
| --- | --- | --- | --- |
| ORM eager-loading | 27 | 4 | OK |
| Input-validation boundary | 25 | 2 | OK |
| Background jobs | 19 | 2 | OK |
| Data isolation / scoping boundary | 22 | 2 | OK |
| Permissions/authorization | 20 | 2 | OK |
| Testing conventions | 15 | 2 | OK |
| Translation workflow *(optional extra)* | 27 | 2 | OK |

**Frontend — `skills/laravel-frontend/SKILL.md`** (4 required):

| Heading (`###`) | non-blank lines | code fences | gate |
| --- | --- | --- | --- |
| Reactivity model | 14 | 2 | OK |
| Partial/fragment response | 29 | 4 | OK |
| Component system | 19 | 6 | OK |
| Form-submission lock | 37 | 2 | OK |

**Zero `STUB!` lines** across both files. (Reproduce with the `awk` block in the plan's
Verification section.)

## (c) Content-resolution dispatch dry-run (R5/R7, architect MUST-FIX 2)

With a notional `stack: laravel` pin, each `## Stack adapter` heading a generic agent names
resolves to a real Laravel section — and that section yields a **concrete one-line rule**, not
just a title. This is what converts the gate from a string-match tautology into a portability
proof.

**`mv-backend` / `mv-curator` → `skills/laravel/SKILL.md`:**

| Agent Stack-adapter heading | Resolved rule extracted from the Laravel section |
| --- | --- |
| ORM eager-loading | `with()` every relation traversed in a loop; `Model::preventLazyLoading(!isProduction())` so an accidental lazy-load *throws* in dev/CI (Laravel-native, no Django analog); `insert()`/`upsert()` for bulk, `chunkById()` while mutating. |
| Input-validation boundary | Validate at the edge in a Form Request; controller sees only `$request->validated()` (never `$request->all()` post-validate); responses via `JsonResource`, never a raw Eloquent model. |
| Background jobs | `ShouldQueue` on Redis + Horizon under a supervised `queue:work`; pass IDs not models; `->afterCommit()` on any dispatch inside a transaction; `ShouldBeUnique`/`WithoutOverlapping` for idempotency. |
| Data isolation / scoping boundary | Global scope via `#[ScopedBy]` + a `BelongsToTenant` trait that filters reads **and** stamps `tenant_id` on create; trust the scope (don't re-add manual `where`), but close the create-path stamping gap. |
| Permissions/authorization | Authorization lives in auto-discovered Policies (Gates for model-less); enforce structurally with `Gate::authorize()`/`$this->authorize()`; `spatie/laravel-permission` is RBAC storage only; never scatter `if ($user->role === 'admin')`. |
| Testing conventions | Pest (conventional default) Feature tests at the HTTP boundary + `RefreshDatabase` + factories + `--parallel`; no DB-touching test without `RefreshDatabase`. |

**`mv-frontend` / `mv-curator` → `skills/laravel-frontend/SKILL.md`:**

| Agent Stack-adapter heading | Resolved rule extracted from the Laravel-frontend section |
| --- | --- |
| Reactivity model | Baseline: server is the source of truth, scoped vanilla JS (Vite module, no globals) for local-only UI. `[Livewire]` public props via **deferred** `wire:model` (`.live` only where needed). `[Inertia]` refs/`useState` + JSON props. |
| Partial/fragment response | Baseline: one route returns the full page **or** a `@fragment` via `->fragmentIf($request->hasHeader('HX-Request'), …)` (the Django `HTMXMixin` twin) — never a second `/partial` endpoint. `[Livewire]` automatic DOM diff (don't hand-roll `@fragment`). `[Inertia]` `router.reload({ only: […] })`. |
| Component system | Baseline: Blade components (`<x-…>`, class-based + anonymous), CSS-framework-agnostic. `[Livewire]` Flux `<flux:…>` is a license-gated UI kit — Pro components gate CI without a token. `[Inertia]` SFC + shadcn. |
| Form-submission lock | Baseline: one delegated `submit` listener disables the button + sets inputs readonly, flipping a `data-` attribute the CSS reads (never overwrite `innerHTML`). `[Livewire]` automatic via bare `wire:submit`. `[Inertia]` `:disabled="form.processing"`. |

All 10 resolve to actionable rules. **No agent profile names a heading that the Laravel skills
fail to fill** — the contract floor is satisfied without forcing an empty slot.

## (d) Body line counts (R8 — lean bodies, depth in `references/`)

```console
$ wc -l skills/laravel/SKILL.md skills/laravel-frontend/SKILL.md
  239 skills/laravel/SKILL.md
  173 skills/laravel-frontend/SKILL.md
```

Both well under the 500-line IDEA-002 ceiling. Deep mechanics live in 11 reference files
(7 backend + 4 frontend, 1368 total insertions across the two skill trees).

## (e) Content-correctness residual (so v5 does not over-claim)

This gate proves the **contract resolves to actionable Laravel content** — it does **not** prove
every Laravel idiom is correct in every L12/L13 minor. Specifically:

- **Step 0 idioms are VERIFIED, not assumed.** All three research-flagged unverified frontend
  idioms were confirmed against current official docs before authoring; **no `<!-- unverified -->`
  markers were carried.** Flux button `<flux:button variant="primary" type="submit">` (free-tier)
  — `fluxui.dev`; Inertia `:disabled="form.processing"` (identical across Vue/React/Svelte) —
  `inertiajs.com/forms`; Livewire **4** with bare `wire:submit` (self-prevents) + deferred
  `wire:model` — `livewire.laravel.com`.
- **Version-sensitive lines** (`#[ScopedBy]` ≥ L10.34, policy auto-discovery ≥ L11, Pest installer
  default ≥ L11, `database` queue default ≥ L11) are noted inline against the **L12 baseline**;
  each reference carries an "L13 drift — re-verify" line.
- **The live-repo dogfood (post-v5) closes content-correctness.** Per Open Q1, a real modern
  Laravel 12 repo will be dogfooded to validate that the resolved rules are *right*, feeding
  corrections back as v5.x. The dogfood follows v5; it does not gate it.
- **License hygiene (R6):** `CONVENTIONS.md` paraphrases Laravel Boost + Spatie guidelines (both
  MIT) behind a `Sources:` footer; `noartem/skills` (license unverified) contributed nothing.
  Public-repo-safe — no customer/org name appears in any skill or reference.

## Verdict

**PROVEN.** Zero `agents/` diff + 10 non-stub headings resolving to extractable rules + a clean
license/version residual. The stack-agnostic architecture from Phase 1 holds against a second,
structurally-different stack. This is the v5 gate (Open Q1 = structural proof + fast-follow).
Docs close-out (CHANGELOG `## v5`, README banner, ideas-index move, IDEA frontmatter) is owned by
`/wrap`, the next stage.
