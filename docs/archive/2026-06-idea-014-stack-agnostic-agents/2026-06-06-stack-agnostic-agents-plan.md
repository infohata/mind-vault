---
stage: plan
slug: stack-agnostic-agents
created: 2026-06-06
source: ./IDEA-014-stack-agnostic-agents.md
status: shipped              # draft | ready | shipped
project: mind-vault
phase_scope: "Phase 1 only (craft/stack split + contract + detection, Django green). Laravel proving stack = follow-on PR per user decision 2026-06-06."
---

# IDEA-014: Stack-agnostic agent architecture (Phase 1)

## Context

mind-vault's 8 subagent profiles are generically **named** (`mv-backend`, …, shipped by IDEA-011) but their **bodies are hard-wired to Django**. A profile's craft (stack-agnostic engineering judgment) and its stack enforcement (concrete framework rules) are fused, so: stack specifics duplicate between the profile and `skills/django*` and can drift; a generic `mv-backend` on a Laravel repo is schizophrenic ("use Django ORM" while editing Eloquent); and adding a stack is an N×M edit across every profile. This plan executes **Phase 1**: split each persona into a **craft core** (stays in the profile) + a **`## Stack adapter`** that points at the active stack skill's contract headings, define that **skill contract**, add **stack resolution**, and keep **Django green** as the regression guard. Phase 2 (the Laravel proving stack) is a separate follow-on PR — the genuine zero-agent-edit proof once the contract is stable.

## Problem Frame

- **Craft/stack fusion in profiles.** Measured coupling (this plan's research pass, not estimates): `mv-frontend` ~13 stack refs (≈90% of body), `mv-curator` ~13 (≈50%, split backend+frontend), `mv-backend` ~8 (≈60%), `mv-test-engineer` ~6 (≈10%, isolated to one pass). The 4 already-generic profiles (`mv-devops`, `mv-documentation`, `mv-researcher`, `mv-architect`) need only a light adapter touch-up.
- **No interface between agent and skill.** The agent has no uniform way to say "enforce the ORM-eager-loading rule for *this repo's* stack" — it names `select_related` directly. Without a fixed heading contract, a generic agent can't resolve stack rules uniformly.
- **Reviewers assert what authors write — same anchors, different verb.** `mv-curator` / `mv-test-engineer` *check* stack idioms ("did the queryset use eager-loading?") rather than *author* them. Their adapter must reference the **same** contract headings the author skills fill — not a parallel set.

## Requirements Trace

- **R1.** A **skill contract** doc (`agents/SKILL_CONTRACT.md`, per Q1) defines the required anchor-heading set: **6 backend** (ORM eager-loading · Input-validation boundary · Background jobs · Data isolation/scoping boundary · Permissions/authorization · Testing conventions) + **4 frontend** (Reactivity model · Partial/fragment response · Component system · Form-submission lock) — the minimal core every framework-stack skill MUST expose so a generic agent resolves uniformly; skills MAY add extras (user decision: minimal-required-core + optional extras; IDEA "Skill contract").
- **R2.** `skills/django/SKILL.md` + `skills/django-frontend/SKILL.md` expose every contract heading (rename/add sections per the mapping in Context & Research); Django behaviour unchanged (IDEA Phase 1 step 1).
- **R3.** The 4 stack-heavy profiles (`mv-backend`, `mv-frontend`, `mv-curator`, `mv-test-engineer`) are split: craft core stays; stack enforcement is replaced by a `## Stack adapter` section pointing at contract headings of the *active* backend/frontend skill (IDEA "Core principle"; "craft core + skill-pointer" mechanism).
- **R4.** The 4 already-generic profiles get a `## Stack adapter` section where relevant + light touch-ups; no craft loss.
- **R5.** Stack resolution is documented (user decision: documented signals + existing dispatch hook) — `.claude/dispatch.md` `stack:` pin → `AGENTS.md` pin → auto-detect signals (`manage.py`/`settings.py`→django; `composer.json`+`artisan`→laravel; `package.json`→node) → ask once. Extends `skills/work/references/persona-dispatch.md`; **no new `tools/detect-stack.sh`** in Phase 1.
- **R6.** Django is the **regression guard**, verified **deterministically** (MF4): a line-conservation diff proves every line dropped from a profile is accounted for (a `Stack profile:` line or a stack-mechanic now carried by a named skill contract heading) — NOT a non-deterministic reasoning re-run. Plus every adapter must specify fail-open behaviour: unresolved stack → craft-only enforcement + announce the gap, never silent skip.
- **R7.** Sequenced per `RULE_rename-before-drop`: contract + skill headings land **first** (move), profiles still green; **then** the stack bodies strip out of the profiles; full pass between. No big-bang rename+drop.
- **R8.** This plan **establishes** the forward-looking tiering invariant `craft agent → framework-stack skill (django) → language-base skill (python)`; only **framework-stack** skills expose the contract. 014 depends on the *framework* layer (django — exists), NOT on the language-base layer: `skills/python/` does not exist yet (IDEA-009 is in flight on PR #164, unmerged), so R8 is satisfied trivially (nothing to touch) and is an invariant 009 will slot beneath when it merges — NOT a dependency on shipped 009 work (MF3).

## Scope Boundaries

**In scope (Phase 1):**

- New skill-contract doc (location decided in Q1) — backend + frontend required heading sets + the "optional extras" rule + the reviewer-consumes-same-anchors note.
- Section renames/additions in `skills/django/SKILL.md` + `skills/django-frontend/SKILL.md` to expose the contract headings (mapping below).
- Craft/stack split of all 8 `agents/AGENT_*.md` profiles (4 heavy surgery + 4 light).
- Stack-resolution documentation: extend `skills/work/references/persona-dispatch.md`; document the `.claude/dispatch.md` `stack:` pin convention.

**Out of scope (→ follow-on PRs / other IDEAs):**

- **Phase 2 — `skills/laravel` + `skills/laravel-frontend`** (the proving stack). Planned in the IDEA body; ships as its own PR after Phase 1 merges. The contract this plan defines is what Phase 2 fills.
- A `tools/detect-stack.sh` helper (deferred; documented signals suffice until a 3rd stack exists).
- A `tools/setup-laravel-boost.sh` analogue (Phase 2 open question).
- Any change to `skills/python/` (IDEA-009 owns it; this plan only references the tiering).
- Re-litigating the IDEA-011 subagent schema (names + recognition already shipped).

**Explicit non-goals:**

- No behaviour change on Django repos — Phase 1 is a pure craft/stack re-seam (R6).
- Not splitting `mv-curator` into two profiles — it stays one reviewer with a dual (backend+frontend) stack adapter (the assert-side of the same contract).
- No per-stack profile forks and no thin dispatcher agent — the mechanism is craft-core + skill-pointer (IDEA "Chosen mechanism").

## Context & Research

### Persona coupling map (research pass, 2026-06-06)

Craft/stack cut is consistent across all four heavy profiles — craft = architecture (no fat controllers, service-layer), efficiency-as-concept (zero-N+1, bulk-ops), security-as-principle (never-trust-input, tenant isolation as scoping), test hygiene (hostile input, state isolation), frontend philosophy (server-driven UI, double-submit guard, a11y), review discipline (trace-don't-glance, parity, zero-false-positive). Stack = the named mechanics (`select_related`/DRF/Celery/`drf_has_permission_in_tenant` · HTMX/Alpine/Bulma/`data-sync-submit` · `django-tenants` `TenantTestCaseBase`). Per-profile stack clusters:

- **`mv-backend`** (agents/AGENT_backend.md): `Stack profile:` line L30; PASS 3 ORM (L57), PASS 4 Celery (L63), PASS 5 DRF permissions (L68). Craft cores: PASS 2 service-layer (already generic).
- **`mv-frontend`** (AGENT_frontend.md): most-coupled; `Stack profile:` L30; nearly every pass names HTMX/Alpine/Bulma/`data-sync-submit` (L34–63). Craft core: PASS 5 UI-parity principle.
- **`mv-curator`** (AGENT_curator.md): dual-stack reviewer; `Stack profile:` L32; PASS 2/4 backend asserts, PASS 5/6 frontend asserts. **Asserts, not authors** → adapter references *both* the active backend and frontend skill's contract headings.
- **`mv-test-engineer`** (AGENT_test-engineer.md): leanest; only PASS 5 (L60–70) is `django-tenants`-specific (TenantTestCase, schema pooling, `TRUNCATE…CASCADE`). Adapter references the backend skill's *Data isolation / scoping boundary* + *Testing conventions* headings (post-MF1).

### Contract heading set (grounded in django's actual sections)

Minimal **required** core (user decision) — the anchors the agent passes reference; skills MAY add more:

| Backend contract heading (required floor — 6) | Django section today (file:line)                                                   | Action                                | Agent-pass referent (the driver)                |
| --------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------------- |
| ORM eager-loading                             | "ORM optimisation — N+1 prevention" `skills/django/SKILL.md:374`                   | rename to match                       | backend PASS 3; curator PASS 4 (assert)         |
| Input-validation boundary                     | scattered (L197 DRF, L418, L484)                                                   | **create** one anchor section         | backend PASS 5 / Directive                      |
| Background jobs                               | deferred to `references/CELERY.md` (L573)                                          | **add** brief anchor stub → reference | backend PASS 4; curator PASS 4                  |
| **Data isolation / scoping boundary**         | "Multi-tenancy vs ForeignKey boundaries" L136 (django fills with schema-isolation) | **rename + generalize** (MF1)         | backend PASS 5; curator PASS 2; test-eng PASS 5 |
| Permissions/authorization                     | "Permission DRY-ness via probe pattern" L220                                       | rename to match                       | backend PASS 5; curator PASS 2                  |
| Testing conventions                           | deferred to `references/TESTING.md`                                                | **add** brief anchor stub → reference | test-eng PASS 5                                 |

**MF1 — `Multi-tenancy` → `Data isolation / scoping boundary`.** The django section is explicitly `django-tenants` schema-isolation scoped — a *strategy* artifact, not a universal anchor (a single-tenant or `stancl/tenancy` Laravel app has no schema-isolation section). The **universal** craft concern is "never leak across the isolation boundary; scope every query to the caller's data" — every backend has *some* answer (even "single-tenant, no scoping"). The generalized anchor name carries the universal half; django fills it with schema-vs-FK content. Keeps the test-engineer + curator adapter targets resolvable while making the heading stack-neutral (this was the one place the adapter seam leaked Django through the heading name itself).

**MF2 — `Translation workflow` demoted to optional-extras.** Applying the plan's own driver test mechanically: no backend *author* pass references it, and the only referent (curator's `format_html`/`format_lazy` i18n-drift assert) is a Django-specific lazy-translation gotcha, not a cross-stack workflow the agent enforces. A backend with no i18n has nothing to put here → it's a floor over-reach. Django keeps its Translation section (now an *extra*); curator may still reference it. Floor shrinks 7→6.

| Frontend contract heading | Django-frontend section today (file:line)                                          | Action                |
| ------------------------- | ---------------------------------------------------------------------------------- | --------------------- |
| Reactivity model          | "Alpine.js global state on `<html>`" `skills/django-frontend/SKILL.md:109` (+L153) | rename/umbrella       |
| Partial/fragment response | "Partial-vs-full template dispatch" L46                                            | keep (aligned)        |
| Component system          | "Cotton components" L91 (+ "Bulma standards" L492)                                 | keep; note spans both |
| Form-submission lock      | "Global single-submit locking" L271                                                | keep (aligned)        |

"Optional extras" (skill keeps, NOT required of every stack): backend — **translation workflow** (MF2), async/real-time (Channels), model-layer abstractions, migrations, caching; frontend — modal management, URL-query safety, HTMX dynamics, template hazards, a11y, scroll preservation. These stay as Django skill content; Laravel only fills the required core unless its passes need more.

### References inventory

- `skills/django/references/` — 20 framework-specific files stay (anchor contract headings); the 2 Python-general (`MODULE_SPLIT_AST_EXTRACTION`, `ENV_DRIVEN_ALLOWLISTS`) are IDEA-009's lift, **excluded here**.
- `skills/django-frontend/references/` — 37 files, all frontend-specific, all stay.

### Stack resolution — existing infra (reuse, don't rebuild)

`skills/work/references/persona-dispatch.md` already documents the hierarchy (`.claude/dispatch.md` pin → `AGENTS.md` → auto-detect → ask). `.claude/dispatch.md` is not yet present at root; `AGENTS.md` exists. Phase 1 extends persona-dispatch.md with the `stack:` key + the auto-detect signal table; no executable detector.

### Institutional learnings

- `RULE_rename-before-drop` — contract+headings move first (skills green), profiles strip second, full pass between (R7).
- IDEA-009 (in flight on PR #164, unmerged) co-establishes this tiering from the python side — its `django → python` down-pointer is the same pointer *shape* as this plan's `agent → django` adapter. The two are mutually reinforcing but independent: **014 does not depend on 009 having shipped** (MF3); 014 proves the adapter-pointer shape itself, here, against the framework layer that already exists.
- IDEA-011 (archived) — the recognized `mv-<persona>` subagent schema this plan keeps; it gave names, this gives generic bodies.
- `skills/skill-writer/SKILL.md` § cross-project portability — contract headings + fenced examples are the same discipline.

## Key Technical Decisions

- **Contract = minimal required core + optional extras** (user decision). The required set is exactly the anchors the agent passes reference (6 backend / 4 frontend above, post-MF1/MF2). Skills expose more freely; the contract is a *floor* for cross-stack resolution, not a checklist every stack must exhaust — this is what keeps Phase 2 a true zero-edit drop-in and avoids forcing empty slots on Laravel (the over-abstraction failure).
- **Reviewers consume the same contract; they don't define their own.** `mv-curator` / `mv-test-engineer` adapters reference the active skill's contract headings in *assert* voice ("confirm the queryset satisfies the active backend skill's **ORM eager-loading** rule"). No parallel reviewer-contract — one contract, author-fills + reviewer-checks.
- **`## Stack adapter` section, uniform across all 8 profiles.** Slots after the craft "Prime Directives"/core, before/within the pass workflow. Names the *role* ("the active backend skill") + the *contract heading*, never the concrete stack. Craft passes keep their intent; only the mechanic clause is replaced by a heading pointer.
- **Detection: documented signals + existing dispatch hook** (user decision). Extend persona-dispatch.md; `.claude/dispatch.md` gains a `stack:` pin convention. No `tools/detect-stack.sh` until a real 3rd stack justifies it.
- **Phase 1 only this PR; Laravel follows** (user decision). Django is the regression guard; the contract proves out against the stack it was extracted from before any second stack lands. Phase 2 is additive and edits zero profiles — that's its proof.
- **Establish the tiering forward (R8, MF3).** Only framework-stack skills (`django`, `django-frontend`, future `laravel*`) expose the contract; a language-base skill (`skills/python/`, when IDEA-009 ships it) does not — it sits beneath. 014 needs only the framework layer (django, present) to prove the adapter; it does not depend on `skills/python/` existing. Exposing contract headings in the django skill touches nothing python-side.

## Open Questions

- **Q1. Where does the skill-contract doc live? → RESOLVED (architect): `agents/SKILL_CONTRACT.md`.** Agent-side interface spec, co-located with the consuming profiles. **Drop the `AGENT_` prefix** — that prefix is reserved for dispatchable persona profiles (Claude dispatches on frontmatter `name:`); a contract doc named `AGENT_*.md` risks being mistaken for a persona or globbed by persona tooling. Rejected: `skills/_contract/` (an underscore pseudo-skill dir invites `validate-skills.sh` confusion).
- **Q2. `mv-curator`'s dual adapter shape? → RESOLVED (architect confirms default): one `## Stack adapter` with `### Backend` + `### Frontend` subsections.** Two top-level sections would imply two independent adapters and invite splitting the persona — which non-goal #2 forbids. One section, two subsections, mirrors the 6-pass body.
- **Q3. Inbound-anchor-link rename risk? → RESOLVED: low risk, audit as resolve-not-match.** Most cross-refs are file-level (`skills/django/SKILL.md`), not anchor-level — small blast radius. But run the step-1 audit as **resolve-not-match** (grep the anchor fragment, then confirm each hit resolves to a live heading post-rename), and the grep list must include all three renames: `ORM optimisation`, `Permission DRY-ness`, **and `Multi-tenancy vs ForeignKey` → `Data isolation / scoping boundary`** (MF1, A4).

## Execution Sequence

**Phase 1A — define + expose the contract (skills green, no profile edits yet):** ✅ DONE (Commit A)

1. ✅ **Pre-flight + link audit (resolve-not-match, Q3/A4).** Grep inbound anchor links to the three sections being renamed — `ORM optimisation`, `Permission DRY-ness`, `Multi-tenancy vs ForeignKey` — across `skills/ rules/ docs/ agents/`; for each hit, resolve the anchor against the post-rename heading and `test` it lands; list any to repoint.
2. **Write the skill-contract doc `agents/SKILL_CONTRACT.md`** (Q1) — the **6** backend required headings + **4** frontend, the optional-extras rule, the reviewer-consumes-same-anchors note, the fail-open contract (unresolved stack → craft-only + announce), and the resolution pointer to persona-dispatch.md. This is R1, the central artifact.
3. **Expose contract headings in `skills/django/SKILL.md`:** rename `ORM optimisation…`→`ORM eager-loading`, `Permission DRY-ness…`→`Permissions/authorization`; **create** an `Input-validation boundary` anchor consolidating the scattered DRF/form/model validation prose (pointer, not rewrite); **add** brief `Background jobs`→`references/CELERY.md` and `Testing conventions`→`references/TESTING.md` anchor stubs. Repoint any Q3 inbound links. No recipe content change.
4. **Expose contract headings in `skills/django-frontend/SKILL.md`:** rename/umbrella `Reactivity model`; confirm `Partial/fragment response`, `Component system`, `Form-submission lock` anchors resolve.
5. **Green gate:** `./tools/validate-skills.sh django django-frontend`; link-audit (resolve-not-match) on the contract doc + renamed anchors; self-sweep. Commit A: `feat(skills): IDEA-014 — define skill contract + expose contract headings in django skills`.

**Phase 1B — split the profiles (craft core + stack adapter):** ✅ DONE (Commits B, C1–C4 `bbd1a55`/`7fe99f1`/`4aa2959`/`76a5d22`, D `4f189b1`, E `ea8498e`)

6. ✅ **Stack resolution docs first** (the adapter targets must exist to point at): extend `skills/work/references/persona-dispatch.md` with the `stack:` pin + auto-detect signal table; document `.claude/dispatch.md` `stack:` convention. **Signal precedence (A2):** backend markers (`artisan`, `manage.py`) resolve the *backend* stack; `package.json` resolves only the *frontend* stack, NEVER the backend — so a Laravel repo shipping a Vite/Tailwind `package.json` isn't misdetected as Node. Commit B: `docs(dispatch): IDEA-014 — stack resolution (dispatch pin + auto-detect signals)`.
7. ✅ **Split the 4 heavy profiles** (`mv-backend`, `mv-frontend`, `mv-curator`, `mv-test-engineer`) — this step **replaces enforcement clauses with adapter pointers** (it does NOT delete the `Stack profile:` header lines — that's step 9, A1). For each: add a `## Stack adapter` section pointing at the contract heading of the active skill; rewrite each stack-mechanic clause to name the role+heading ("satisfies the active backend skill's **ORM eager-loading** rule"); keep craft passes intact. **Every adapter MUST carry the fail-open clause (MF4):** "if stack resolution yields no skill (no pin / no detect / ambiguous), enforce craft-only and **announce the unresolved-stack gap** — never silently skip a stack rule." `mv-curator` gets one `## Stack adapter` with `### Backend`+`### Frontend` subsections (Q2); `mv-test-engineer` adapter → backend skill's **Data isolation / scoping boundary** + **Testing conventions** (post-MF1 heading name). One commit per profile (C1–C4) for bisectability — each leaves Django green (the `Stack profile:` lines still physically present).
8. ✅ **Light-touch the 4 generic profiles** (`mv-devops`, `mv-documentation`, `mv-researcher`, `mv-architect`): add a `## Stack adapter` section where relevant (e.g. devops compose/CI is partly stack-shaped), else a one-line "stack-agnostic; no adapter needed" marker for uniformity. Commit D.
9. ✅ **Drop ONLY the now-orphaned `Stack profile:` header lines + any dead remnants** the step-7 rewrite left behind (the rename-before-drop *drop* step — only after 7–8 land green; step 7 already replaced the enforcement clauses, so this commit owns *only* the orphaned header lines, A1). Commit E: `refactor(agents): IDEA-014 — drop orphaned Django Stack-profile lines (craft cores remain)`.

**Phase 1C — regression-guard + wrap:** ✅ DONE

10. ✅ **Django regression gate (R6, MF4) — deterministic primary.** Line-conservation mapping table + fail-open check recorded in [`2026-06-06-phase1-verification-log.md`](2026-06-06-phase1-verification-log.md). All 8 deterministic checks (V1–V8) green; zero unaccounted enforcement removals.
11. ✅ No architect re-clearance triggered (no architectural decision shifted — reconciliations logged in the verification log §). Next: `/wrap` → `/review-loop` → `/land`.

## Verification

- **Contract completeness.** The skill-contract doc lists exactly the required backend (6) + frontend (4) headings; each maps to a real, resolvable section in `skills/django*/SKILL.md` (grep each heading, confirm present).
- **Skill lint.** `./tools/validate-skills.sh django django-frontend` green after the renames.
- **Link integrity (resolve-not-match).** Every inbound link to a renamed section repointed; zero dangling anchors; the contract doc's pointers resolve from its own dir.
- **Profile split parity (R6 — the load-bearing gate, MF4). Primary check is DETERMINISTIC, not a reasoning re-run** (a subagent dry-run is non-deterministic — it can't crisply fail, so it can't falsify "no behaviour change"). For each of the 4 heavy profiles, `git diff` pre/post and produce a **line-conservation mapping table**: every removed line is either (a) a `Stack profile:` header line, or (b) a stack-mechanic clause whose enforcement now lives under a named contract heading in the active skill — `dropped profile line → skill heading that now carries it`. **Zero unaccounted-for removals.** This is repeatable and *can fail*. The reasoning dry-run on a Django diff stays only as advisory color, never the gate.
- **Fail-open guard (MF4 — the failure mode the dry-run hides).** Confirm every split profile's `## Stack adapter` states the resolution-failure behaviour: when stack resolution yields nothing (no pin, no detect, ambiguous), the craft core enforces **craft-only and ANNOUNCES the unresolved-stack gap** — it never silently skips the stack rule. (Pre-split, the rule was inline = always enforced; post-split it depends on the skill being loaded. Without this clause the agent fails open on exactly the un-provisioned repos Phase 2 targets — same class as `RULE_self-sweep` #3 and the v4.6.5 "fails open on a new surface" compound.)
- **No `skills/python/` touch (R8).** `git diff --name-only` shows no `skills/python/` path; the tiering note in the contract doc states python is language-base, not contract-bearing.
- **Adapter uniformity.** All 8 profiles carry a `## Stack adapter` section (or the explicit "no adapter needed" marker); none names a concrete stack in a craft pass.
- **Detection doc.** persona-dispatch.md resolution order is `.claude/dispatch.md stack: → AGENTS.md → auto-detect → ask`; signal table covers django + laravel + node.

______________________________________________________________________

## Architect review (2026-06-06)

Reviewed by **`mv-architect`** (real dispatch). **Verdict: 🟡 REQUIRES ABSTRACTION → all 4 must-fixes + 4 advisories folded; now sound.** No circular deps, no scaling trap; the craft/stack cut, rename-before-drop sequencing, reviewer-consumes-same-contract, documented-signals deferral, and the role+heading adapter seam all verified sound as-is. The four must-fixes:

1. **MF1 — `Multi-tenancy` was a `django-tenants` artifact** (over-reach in the required floor; breaks the zero-edit Laravel drop-in). → generalized to **`Data isolation / scoping boundary`** (universal craft concern; django fills the schema-isolation half). Adapter targets (test-eng, curator) renamed with it.
2. **MF2 — `Translation workflow` had no backend-author referent.** → demoted to optional-extras; floor 7→6. Django keeps the section.
3. **MF3 — the "IDEA-009 landed first / de-risks" premise was false on disk** (`skills/python/` doesn't exist; 009 unmerged on #164). → R8 + learnings reframed as a *forward-looking* invariant 014 establishes; 014 depends only on the framework layer (django, present), not on phantom python work.
4. **MF4 — the R6 reasoning-parity check was unfalsifiable** (non-deterministic subagent re-run can't fail) **and hid a fail-open** (a stack rule that moved into the skill is only enforced if the skill loads). → replaced with a **deterministic line-conservation diff** (dropped-line → skill-heading mapping table, zero unaccounted removals) as the primary gate; **every `## Stack adapter` must carry a fail-open clause** (unresolved stack → craft-only + announce the gap, never silent skip — same class as the v4.6.5 "fails open on a new surface" compound).

Advisories folded: A1 (step 7 replaces clauses / step 9 drops only orphaned header lines — no commit contention); A2 (backend-signal-precedence: `package.json` resolves frontend only, never backend); A3 (Q1 → `agents/SKILL_CONTRACT.md`, no `AGENT_` prefix); A4 (Q3 grep list includes the isolation rename, resolve-not-match). Q1/Q2/Q3 resolved inline.

______________________________________________________________________

**Status:** ready — architect-reviewed (🟡 → all must-fixes folded → sound). Phase 1 scope (craft/stack split + 6/4 contract + documented detection, Django the deterministic regression guard); Laravel proving stack is the follow-on PR. Hand to `/work` with this plan path.
