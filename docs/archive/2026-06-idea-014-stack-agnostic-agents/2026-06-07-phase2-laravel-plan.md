---
stage: plan
slug: stack-agnostic-agents
phase: 2
created: 2026-06-07
source: ./IDEA-014-stack-agnostic-agents.md
research: ./2026-06-07-phase2-laravel-research.md
status: ready
project: mind-vault
---

# IDEA-014 Phase 2 — Laravel proving stack (plan)

## Context

Phase 1 (PR #178, v4.9) split every `agents/AGENT_*.md` persona into a stack-agnostic **craft core** + a `## Stack adapter` that resolves concrete idioms against the *active* stack skill, and shipped `agents/SKILL_CONTRACT.md` — a required **6 backend + 4 frontend** heading floor. Django/django-frontend expose all 10 headings verbatim and serve as the regression guard.

Phase 2 is the **proof**: add `skills/laravel` + `skills/laravel-frontend` that fill the same 10 contract headings, and demonstrate a generic `mv-backend`/`mv-frontend`/`mv-curator`/`mv-test-engineer` works a Laravel repo **with zero edits to any agent profile**. The zero-`agents/`-diff IS the deliverable — it's what proves the architecture holds, not just that it was designed.

Intended outcome: a second stack exists, the contract is demonstrated portable, and mind-vault bumps to **v5** ("demonstrated on a second stack", not merely architected).

## Problem Frame

Today mind-vault supports exactly one stack (Django). The craft/stack split is *architected* but **unproven** — a one-stack system can't distinguish "genuinely stack-agnostic" from "Django with extra indirection". Until a second, structurally-different stack drops in without touching a single agent profile, the v5 claim is unearned and any hidden Django-coupling in the "craft" cores stays invisible.

## Requirements Trace

- **R1** — `skills/laravel/SKILL.md` exposes all **6 backend** contract headings as literal `###` sections: ORM eager-loading · Input-validation boundary · Background jobs · Data isolation / scoping boundary · Permissions/authorization · Testing conventions. (IDEA "Skill contract"; research §"shipped contract is the target".)
- **R2** — `skills/laravel-frontend/SKILL.md` exposes all **4 frontend** contract headings as literal `###` sections: Reactivity model · Partial/fragment response · Component system · Form-submission lock.
- **R3** — Each heading carries genuine, current (Laravel 12) Laravel content — mechanism + best-practice default + anti-pattern — not a stub. (research backend/frontend mapping tables.)
- **R4** — **Zero edits to any `agents/AGENT_*.md`.** `git diff origin/main...HEAD -- agents/` is empty at PR HEAD. (IDEA Phase 2: "no agent profile is touched — that is the proof".)
- **R5** — Detection resolves Laravel: `composer.json` + `artisan` → backend, `resources/views/*.blade.php` → frontend, per the existing `persona-dispatch.md` signal table. The proof must show the 10 headings resolve under a `stack: laravel` pin.
- **R6** — License/provenance clean: paraphrase MIT sources (Boost `.ai/foundation`, Spatie guidelines) with attribution; **never copy** `noartem/skills` (license unverified); CC0 sources free. Safe-in-a-public-repo. (research landscape table; `/compound` scrub-gate discipline.)
- **R7** — A **verification log** records the proof (mirrors Phase 1's line-conservation log): empty `agents/` diff + grep-resolution of all 10 headings + a dispatch dry-run.
- **R8** — Skill bodies stay lean (<500 lines each, the IDEA-002 target); deep mechanics live in `references/`.

## Scope Boundaries

**In scope:**
- `skills/laravel/` — `SKILL.md`, `VERSION`, `references/` (backend).
- `skills/laravel-frontend/` — `SKILL.md`, `VERSION`, `references/` (frontend, Livewire-default + adapter variants).
- A light, NON-agent touch-up to `skills/work/references/persona-dispatch.md` IF the frontend-variant signal needs a row (allowed — it is a skill reference, not an agent profile; does not break R4).
- Symlink registration (`scripts/setup-claude-code-symlinks.sh`) for the two new skills.
- The verification log.
- Docs (CHANGELOG v5 section, README banner, ideas-index move, IDEA frontmatter close-out) — **owned by `/wrap`**, noted here for completeness.

**Out of scope / explicit non-goals:**
- ❌ **Any edit to `agents/AGENT_*.md`** — editing one would falsify the proof (R4). If a heading *cannot* be satisfied without an agent edit, that is a Phase-1 contract bug → STOP and re-plan, don't paper over it.
- ❌ **Vendoring Laravel Boost's MCP server** or any Blade-template guideline verbatim — paraphrase only (R6).
- ❌ **Filament admin** skill — orthogonal; note as a follow-up IDEA.
- ❌ **A live Laravel repo dogfood run** — mind-vault has no Laravel app to test against; the proof is structural (see Open Q1). A real-repo run is a post-v5 follow-up.
- ❌ **`tools/detect-stack.sh`** executable detector — documented signals suffice for the proof; the script stays deferred per Phase 1's decision.
- ❌ Reworking the contract or any Django skill content.

## Context & Research

- **Planning input (source of truth):** [`2026-06-07-phase2-laravel-research.md`](2026-06-07-phase2-laravel-research.md) — 3-way `mv-researcher` fan-out: landscape, backend idioms (verified vs laravel.com/docs/12.x), frontend idioms. Includes per-heading mechanism/default/anti-pattern tables and the Django↔Laravel stress-point note.
- **Layout to mirror:** `skills/django/` (633L SKILL.md + 21 references + `VERSION`=`5.5`, `metadata.version`=`5.0`) and `skills/django-frontend/` (622L + 38 references). Laravel mirrors the *shape* (SKILL.md + VERSION + references/), not the organic interleaving — greenfield, so structure cleanly around the contract spine.
- **Contract:** `agents/SKILL_CONTRACT.md` — the 6/4 floor, optional-extras rule, fail-open clause, "reviewers consume the same contract" note.
- **Detection:** `skills/work/references/persona-dispatch.md` already carries the `laravel` row (`composer.json`+`artisan` → backend; `resources/views/*.blade.php` → frontend) and the §"Stack resolution" order.
- **Reuse sources (all verified MIT unless noted):** `laravel/boost` `.ai/foundation` (MIT), `spatie/boost-spatie-guidelines` (MIT), `jpcaparas/superpowers-laravel` taxonomy (MIT, checklist-only), `agentskills.io` spec (conformance target), `awesome-cursorrules` (CC0), `noartem/skills` (**UNVERIFIED — do not copy**).
- **Memory:** per-skill symlinks need `scripts/setup-claude-code-symlinks.sh` re-run + session restart; mdformat not installed locally (manual markdown lint).

## Key Technical Decisions

1. **Greenfield skills are organized AROUND the contract spine.** Unlike django's organically-grown interleaving, `skills/laravel/SKILL.md` leads with the 6 backend headings as its primary `###` sections (plus When-to-use / Pattern / References scaffolding). Cleaner to grep-verify and read; lean body, depth in `references/`. **The contract-heading *strings* are verbatim-identical to Django's** (`### ORM eager-loading`, etc. — the strings ARE the interface, grep-resolved across stacks); only the surrounding scaffolding differs. A future editor must never "improve" a Laravel heading string — that silently breaks grep-resolution. (architect PASS 1.)
2. **`laravel-frontend` is ONE skill: Livewire+Flux default + Inertia/Blade adapter variants** — not a hard dispatcher. Mirrors how django-frontend keeps HTMX/Alpine/cotton in one skill. The 4 headings present the Livewire answer as default with `[Adapter] Inertia` / `[Adapter] Blade+HTMX` sub-notes. The fail-open/announce discipline extends to variant ambiguity. (research frontend recommendation; resolves IDEA open-Q "Filament/dispatcher".)
3. **VERSION = framework version, metadata.version = skill version.** `skills/laravel/VERSION`=`12`, `skills/laravel-frontend/VERSION`=`12`; `metadata.version: '0.1'` (new skill), `license: Apache-2.0` (matching the django pair).
4. **Reuse = paraphrase-with-attribution, never vendor.** Boost `foundation` + Spatie guidelines → paraphrased into `references/conventions.md` with a `Sources:` footer. superpowers-laravel taxonomy is a *checklist* for which references to write. noartem is inspiration-only. This satisfies R6 and the public-repo test.
5. **The proof is structural, gated by a verification log.** v5 ships on: (a) empty `agents/` diff, (b) all 10 headings grep-resolve as literal `###` in the new skills, (c) a dispatch dry-run mapping each agent Stack-adapter heading → the resolved Laravel section. No live Laravel repo required (Open Q1).
6. **Data isolation gets the cross-direction warning.** Per the research stress-point: the heading must warn BOTH that Django-trained devs under-trust Laravel's implicit global scopes AND that the real hazard is the create-path `tenant_id` stamping gap; cross-reference `RULE_self-sweep §3`. `preventLazyLoading` is presented as a Laravel-native superpower with no Django analog.
7. **Pest is the default testing reference; PHPUnit noted as coexisting.** Phrase Pest as "the conventional default (`laravel new` prompt / `--pest`)", not a docs-guaranteed absolute (research version-sensitivity flag).
8. **Target Laravel 12 as the verified baseline; note 13 drift** on version-sensitive lines (queue defaults, Pest 4/PHPUnit 12, starter kits).

## Open Questions

1. **Is the structural proof sufficient for v5, or does v5 gate on a live Laravel-repo run?** → **Default: structural proof suffices.** mind-vault has no Laravel app; blocking v5 on acquiring one stalls the release indefinitely. The zero-agent-diff + heading-resolution + dispatch dry-run demonstrate the contract holds. A real-repo dogfood becomes a post-v5 follow-up IDEA. *(Surfaced for user confirmation — it defines "done".)*
2. **How deep must each reference be for v5 — production-grade or proof-grade?** → **Default: proof-grade-plus.** Each of the 10 headings must be genuinely useful (mechanism + default + anti-pattern + a code sample), not a stub (R3), but exhaustive reference coverage (every superpowers-laravel taxonomy entry) is iterative post-v5. The floor: a reader could act on each heading today.
3. **Include the optional `Translation workflow` extra in `skills/laravel`?** → **Default: yes — include it** (parity with django, cheap: `lang/`, `__()`, `trans_choice()`), marked optional. **Architect coverage note (PASS 2):** the "omit" branch leaves `AGENT_curator` PASS 3's "active backend skill's lazy-translation convention" anchor resolving to nothing on Laravel — a fail-open gap (R4-safe, the curator announces it, but a coverage hole). Prefer the include default to close it.
4. **Touch `persona-dispatch.md` for the frontend variant (Livewire/Inertia/Blade) signal?** → **Default: document the variant detection IN `skills/laravel-frontend` itself**; leave the existing `persona-dispatch.md` laravel row as-is. Touch it only if the dry-run reveals a resolution gap. (Either way it is a non-agent edit, R4-safe.)

## Execution Sequence

> Purely additive — `RULE_rename-before-drop` does not apply (no renames, no drops). Order is logical build order. One commit per logical unit.

0. **Resolve the two research-flagged unverified frontend idioms FIRST** (architect PASS 4 residual) — confirm Flux's `<flux:button>` namespace against `fluxui.dev/docs` and Inertia's `form.processing` against `inertiajs.com/forms` before authoring step 3/4. If still unconfirmable, carry an explicit inline `<!-- unverified: ... -->` marker rather than shipping it as a confident rule. `mv-researcher`.
1. **`skills/laravel/SKILL.md` + `VERSION`** — frontmatter (name/description/license/metadata.version `0.1`), When-to-use, Pattern intro, then the **6 backend `###` headings** filled from the research backend table (mechanism/default/anti-pattern + one code sample each — **non-stub: each section carries a fenced code block + ≥8 non-blank lines**, R3), Decision-6 cross-direction warning on Data isolation, References list. `VERSION`=`12`. Lean body (<500L). `mv-backend` persona (author).
2. **`skills/laravel/references/`** — backend deep docs, taxonomy-checklist-driven: `EAGER_LOADING.md`, `FORM_REQUESTS_RESOURCES.md`, `QUEUES_HORIZON.md`, `DATA_ISOLATION_TENANCY.md` (authored fresh — ecosystem gap), `POLICIES_GATES.md`, `PEST_TESTING.md`, `CONVENTIONS.md` (paraphrased Boost+Spatie, `Sources:` footer). `mv-backend` + `mv-documentation`.
3. **`skills/laravel-frontend/SKILL.md` + `VERSION`** — frontmatter, Stack table (Livewire default + adapter-variant callout), the **4 frontend `###` headings** (Livewire default + `[Adapter]` Inertia/Blade sub-notes) from the research frontend table, References list. `VERSION`=`12`. `mv-frontend` (author).
4. **`skills/laravel-frontend/references/`** — `LIVEWIRE_LOADING_STATES.md`, `BLADE_FRAGMENTS_HTMX.md` (the Django-twin adapter), `FLUX_LICENSE_GATING.md` (fresh — CI auth-token hazard), `INERTIA_PARTIAL_RELOADS.md`. `mv-frontend` + `mv-documentation`.
5. **Symlink registration** — re-run `scripts/setup-claude-code-symlinks.sh`; confirm `~/.claude/skills/laravel` + `laravel-frontend` resolve. `mv-devops`.
6. **(Conditional) `persona-dispatch.md` touch** — only if step 7's dry-run reveals a resolution gap (Open Q4). NON-agent edit.
7. **Verification log** — `2026-06-07-phase2-verification-log.md` in the archive dir: (a) `git diff --stat origin/main...HEAD -- agents/` output (must be empty); (b) grep showing all 10 heading strings resolve as `###` in the new skills **AND the non-stub assertion** (each section has a code fence + ≥8 non-blank lines before the next `###`, R3); (c) **content-resolution dispatch dry-run** — for each of the 10 headings, record the **one-line actionable rule a generic agent extracts** from the resolved section (e.g. `ORM eager-loading` → "enforce `with()` on every looped relation + `preventLazyLoading` in dev/CI"), NOT mere heading presence (architect MUST-FIX 2 — this is what converts the gate from a string-match tautology into an actual portability proof); (d) body line counts; (e) **explicit content-correctness residual statement** — the gate proves the contract resolves to actionable content, NOT that every Laravel idiom is correct (the live-repo dogfood, post-v5, closes that); list any inline `unverified` markers carried from step 0 so v5 does not over-claim. `mv-test-engineer` / `mv-curator`.
8. **Docs (via `/wrap`, not in `/work`)** — CHANGELOG `## v5` section, README v5 banner + Laravel-pair mention, ideas-index move to References-Implemented, IDEA-014 frontmatter `status: complete` + `completed:` + `phase_2_completed:`. Listed for traceability; `/wrap` owns it.

## Verification

Run before opening the PR for review (the proof gate):

```bash
cd ~/projects/mind-vault
# R4 — THE PROOF: zero agent-profile edits
git diff --stat origin/main...HEAD -- agents/            # MUST be empty

# R1/R2 — all 10 contract headings resolve as literal ### sections
for h in "ORM eager-loading" "Input-validation boundary" "Background jobs" \
         "Data isolation / scoping boundary" "Permissions/authorization" "Testing conventions"; do
  grep -q "^### $h" skills/laravel/SKILL.md && echo "OK backend: $h" || echo "MISSING: $h"
done
for h in "Reactivity model" "Partial/fragment response" "Component system" "Form-submission lock"; do
  grep -q "^### $h" skills/laravel-frontend/SKILL.md && echo "OK frontend: $h" || echo "MISSING: $h"
done

# R3 — ANTI-TAUTOLOGY: each contract heading has a non-stub body, not just a title.
#   For every "### " section, assert it contains a code fence AND >=8 non-blank lines
#   before the next "### ". A heading string alone (which the grep above would pass)
#   must FAIL here. (architect MUST-FIX 1.)
awk '
  /^### /{ if(h!=""){ printf "%-42s lines=%d fence=%d %s\n", h, n, f, (n>=8&&f>=1?"OK":"STUB!") } h=substr($0,5); n=0; f=0; next }
  /^```/{ f++ }
  /[^[:space:]]/{ if(h!="")n++ }
  END{ if(h!=""){ printf "%-42s lines=%d fence=%d %s\n", h, n, f, (n>=8&&f>=1?"OK":"STUB!") } }
' skills/laravel/SKILL.md skills/laravel-frontend/SKILL.md   # zero STUB! lines required

# R8 — lean bodies
wc -l skills/laravel/SKILL.md skills/laravel-frontend/SKILL.md   # each < 500

# R6 — license scrub: attribution footers present, no unverified-source copying
grep -rl "Sources:" skills/laravel/references/                  # paraphrased refs cite sources
# manual: confirm no text lifted from noartem/skills

# symlinks resolve (R5 prerequisite)
ls -l ~/.claude/skills/laravel ~/.claude/skills/laravel-frontend
```

- **Dispatch dry-run (R5/R7):** with a notional `stack: laravel` pin, walk `mv-backend`'s Stack-adapter table — every heading it names (ORM eager-loading, Input-validation boundary, Background jobs, Permissions/authorization, Data isolation) resolves to a real `###` section in `skills/laravel/SKILL.md`; same for `mv-frontend` against `skills/laravel-frontend`. Record the mapping in the verification log.
- **Markdown lint:** manual pass (mdformat not installed) — fenced code langs, no broken relative links.
- **Fresh-session smoke (post-merge):** restart a session, confirm `skills/laravel` loads and its description matches the trigger.

## Architect review

**Verdict: 🟢 ARCHITECTURALLY SOUND** (mv-architect, 2026-06-07) — core architecture correct, zero-`agents/`-diff constraint genuinely load-bearing, contract floor honored without forced empty slots, `laravel-frontend`-as-one-skill cut endorsed. The plan correctly *surfaces* the Data-isolation Django↔Laravel stress point rather than hiding it (the proof working as designed).

The review's central catch: the original verification gate was a **tautology** — `grep "^### heading"` passes on hollow headings, leaving R3 (non-stub content) mechanically unchecked. All 5 findings folded in:

1. ✅ MUST-FIX 1 — non-stub assertion (code fence + ≥8 non-blank lines per heading) added to Verification.
2. ✅ MUST-FIX 2 — Step 7(c) dry-run re-spec'd to record the extracted one-line *rule* per heading (content-resolution, not string-match).
3. ✅ Residual — Step 0 added (resolve the 2 unverified frontend idioms pre-authoring or mark inline); content-correctness residual stated in the log so v5 doesn't over-claim.
4. ✅ PASS 1 — Decision 1 now states heading strings are verbatim-identical to Django's; only scaffolding differs.
5. ✅ PASS 2 — Open Q3 default hardened to "include Translation workflow" (the omit branch leaves an `AGENT_curator` anchor unresolved).
