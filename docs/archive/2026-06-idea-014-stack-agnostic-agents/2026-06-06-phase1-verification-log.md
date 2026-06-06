# IDEA-014 Phase 1 — Verification log

Run 2026-06-06 against `idea/014-stack-agnostic-agents` (commits A `d8dc9e3`, B `13e1c96`,
C1 `bbd1a55`, C2 `7fe99f1`, C3 `4aa2959`, C4 `76a5d22`, D `4f189b1`, E `ea8498e`).

## Deterministic checks (the gates)

| Check | Result |
| --- | --- |
| V1 Contract completeness — 6 backend + 4 frontend headings grep-resolve in `skills/django*/SKILL.md` | ✅ 10/10 |
| V2 Skill lint — `validate-skills.sh django django-frontend` | ✅ both exit 0 |
| V3 Link integrity — zero references to any OLD heading name (outside plan archive) | ✅ |
| V4 Profile split parity — line-conservation (below) | ✅ zero unaccounted enforcement removals |
| V5 Fail-open guard — every *stack-resolving* adapter states resolution-failure behaviour | ✅ 7/7 (documentation = marker, no stack rule to fail open on) |
| V6 No `skills/python/` touch (R8) | ✅ no `skills/python/` path in diff |
| V7 Adapter uniformity — all 8 profiles carry `## Stack adapter` | ✅ 8/8 |
| V8 Detection doc — resolution order + signal table (django/laravel/node) | ✅ |

## V4 — line-conservation mapping (the load-bearing gate)

Every line removed from the 4 heavy profiles is accounted for as one of: **(R)** craft line
reworded/genericized — enforcement preserved in the `+` replacement, no Django assumption;
**(S)** the orphaned `**Stack profile:**` header line (Commit E); **(H)** a stack-mechanic
clause whose enforcement now lives under a named contract heading in the active skill.

### mv-backend

| Removed | Class | Now carried by |
| --- | --- | --- |
| intro "master of Django ORM, REST APIs…" | R | genericized intro + `## Stack adapter` |
| `**Stack profile:** Django + …` | S | dropped (E) |
| PD1 Fat Views / `services.py` | R | PD1 "Fat Controllers" + Service Layer (craft) |
| PD2 `select_related`/`prefetch_related` | H | **ORM eager-loading** |
| PD3 serializers/ORM boundary | H | **Input-validation boundary** |
| PD4 `bulk_create`/`bulk_update` | H | **ORM eager-loading** (bulk) |
| PASS1 `on_delete`, `auto_now_add` | H | active backend skill model-layer conventions (optional-extra; django `BaseModel`) |
| PASS3 `select_related`/`prefetch_related`/`len()`/`.count()`/`.exists()` | H | **ORM eager-loading** |
| PASS4 Celery worker | H | **Background jobs** |
| PASS5 DRF authz / `IsAuthenticated` / probe | H | **Permissions/authorization** |
| PASS5 `request.user.tenant` cross-tenant | H | **Data isolation / scoping boundary** |

### mv-frontend

| Removed | Class | Now carried by |
| --- | --- | --- |
| intro HTMX/Alpine/Bulma/React/Vue | R | genericized intro + `## Stack adapter` |
| `**Stack profile:** HTMX 1.9+ …` | S | dropped (E) |
| PD1 HTMX | H | **Partial/fragment response** |
| PD2 `window`/Alpine `x-data`/Zustand | H | **Reactivity model** |
| PD3 `data-sync-submit` | H | **Form-submission lock** |
| PASS1 `x-data` scoping / Zustand / React Context | H | **Reactivity model** |
| PASS2 HTMX `hx-trigger`/`delay:500ms` | H | **Partial/fragment response** |
| PASS3 `x-show`/`is-hidden`/`{% if %}` | H | **Partial/fragment response** + **Reactivity model** |
| PASS4 `data-sync-submit`/`.textContent`/`.querySelector` | H | **Form-submission lock** |
| PASS5 Edit/Mobile Modal parity | R + H | craft parity + **Component system** |

### mv-curator (asserts the same contract; review voice)

| Removed | Class | Now carried by |
| --- | --- | --- |
| intro "specialized in Django…HTMX/Alpine" | R | genericized intro + dual `## Stack adapter` |
| `**Stack profile:** …` | S | dropped (E) |
| PD3 negative-space (`static/`, "Vanilla JS") | R | reworded craft (stack-neutral) |
| PASS2 tenant FK leak | H | **Data isolation / scoping boundary** |
| PASS2 `database_sync_to_async`/`tenant_context` | H | **Data isolation / scoping boundary** + async |
| PASS2 DRF probe `drf_has_permission_in_tenant` | H | **Permissions/authorization** |
| PASS2 HMAC `X-User-Context-Signature` | H | **Input-validation boundary** |
| PASS2 third-party ID strip / anon ownership / GET-mutates | R | reworded craft (stack-neutral) |
| PASS3 `format_html`/`format_lazy` migration drift | H | active backend skill lazy-translation convention |
| PASS3 `base.html`/`base_minimal.html` parity | H | **Component system** (layout-sibling parity) |
| PASS3 parser dedup / dict collisions / eviction / fat-models / `datetime.now()` | R | reworded craft (stack-neutral) |
| PASS4 `RunPython` backfill | R | reworded craft (data-backfill migration) |
| PASS4 GenericFK `.in_bulk()`/`ContentType` | H | **ORM eager-loading** (generic-relation case) |
| PASS4 `.all()`/`select_related`, `bulk_create` | H | **ORM eager-loading** |
| PASS4 Celery integrity | H | **Background jobs** |
| PASS4 `filterset_fields`/`search_fields` dead-field | H | active backend skill list-view config |
| PASS5 `data-sync-submit` family (double-submit / ghost-lock / spinner / lock-scope) | H | **Form-submission lock** (+ **Component system**) |
| PASS5 `scrollIntoView` / Save-Then-Attach | R | reworded craft (stack-neutral) |
| PASS6 Alpine `x-data`/`@click`/`escapejs` XSS | H | **Reactivity model** |
| PASS6 `x-model`/`value="{{ }}"` progressive enhancement | H | **Reactivity model** |
| PASS6 `x-data`+`x-show`/`{% if %}is-hidden` FOUC | H | **Reactivity model** + **Partial/fragment response** |
| PASS6 lexical-closure / API try-catch guards | R | reworded craft (stack-neutral JS) |
| PASS5/6 heading renames | R | "Frontend & UX" / "Client Reactivity & Defensive Execution" |

### mv-test-engineer (leanest; no Stack profile line)

| Removed | Class | Now carried by |
| --- | --- | --- |
| intro Python/JS | R | language-base framing retained + `## Stack adapter` (python = language-base, R8) |
| PASS3 `@override_settings` | R | "a settings-override decorator (e.g. …)" (example form) |
| PASS4 `setUpTestData()`/`.setUp()` | R | class-scoped vs per-method setup (e.g. form) |
| PASS5 django-tenants block (HTTP_HOST/`TenantTestCaseBase`/`search_path`/`create_schema`/`TRUNCATE…CASCADE`/canary) | H | **Data isolation / scoping boundary** + **Testing conventions** (django specifics resolve via `django/references/TESTING.md`) |
| PASS5 heading "(multi-tenant / django-tenants)" | R | "Parallel-Execution Resilience" |

**Result:** zero unaccounted-for enforcement removals. Every stack mechanic that left a
profile is now reachable through a named contract heading in the active skill — so on a
Django repo the loaded `skills/django*` supplies the same idiom (no behaviour change),
and on a future stack the same heading resolves to that stack's skill.

## Fail-open guard (MF4)

All 7 stack-resolving adapters (backend, frontend, curator, test-engineer, devops,
researcher, architect) carry the clause: unresolved stack → craft-only + **announce** the
gap, never silently skip. `mv-documentation` carries the "stack-agnostic; no adapter
needed" marker — it resolves no stack rule, so there is nothing to fail open on.

## Execution reconciliations (no architectural decision shifted)

1. **Frontend heading renames.** The plan's mapping table marked 3 frontend sections
   "keep (aligned)", but R1 ("every framework-stack skill MUST expose [the headings] so a
   generic agent resolves uniformly") + V1 ("grep each heading, confirm present") require
   the literal contract strings. Renamed all 4 (`Partial-vs-full template dispatch` →
   `Partial/fragment response`, `Alpine.js global state on <html>` → `Reactivity model`,
   `Cotton components` → `Component system`, `Global single-submit locking` →
   `Form-submission lock`). Resolves an internal inconsistency in favour of R1; not a
   design change. Inbound-link audit for these 4 ran the same resolve-not-match pass (one
   in-file prose ref repointed; no `#`-anchor links existed).
2. **Strict "no concrete stack in a craft pass."** Genericized a few Django tokens the
   coupling map didn't enumerate (backend PASS 1 `on_delete`/`auto_now_add`; test-eng
   PASS 3/4 `@override_settings`/`setUpTestData`; devops PD3 `Celery`) to honour V7's
   adapter-uniformity line. Concept-level checks preserved.
3. **Illustrative examples left intact** (curator sprint-end sweep category labels;
   architect plan-time probe example list; documentation "show don't tell" examples) — per
   the standing "don't over-harden illustrative examples" guidance; each sits under an
   adapter/marker that frames it as stack-illustrated.

No architect re-clearance triggered — the contract shape (6/4 floor), the craft-core +
skill-pointer mechanism, the dual-curator-adapter (Q2), the documented-detection deferral,
and the rename-before-drop sequencing all held as designed.
