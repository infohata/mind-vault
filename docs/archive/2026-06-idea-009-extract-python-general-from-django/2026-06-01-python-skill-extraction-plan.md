---
stage: plan
slug: python-skill-extraction
created: 2026-06-01
refreshed: 2026-06-06   # rebased onto post-v4.7 main; deepened for IDEA-014 craft/stack alignment
source: ./IDEA-009-extract-python-general-from-django.md
status: ready
project: mind-vault
---

# IDEA-009: Extract Python-general patterns from the django skill into a python skill

## Context

`skills/django/` is currently the **only** Python home in the vault. Python-general patterns — ones an agent on a non-django Python project would want — default there by gravity and never load outside a django task. The v4.3.7 forced-atomic dedup (PR #148) made the smell concrete: a cross-stage rule (`RULE_rename-before-drop`) now points *into* `skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md` for a Python-general sequencing wrinkle. This plan stands up `skills/python/` as the **deliberate base Python layer** beneath `django`/`django-frontend` and lifts the two genuinely Python-general references into it, generalizing django-isms to fenced examples.

## Problem Frame

- **Misfile by gravity.** Python-general content lives under `skills/django/references/`, so it's invisible to a non-django Python task and every future Python-general pattern inherits the wrong home.
- **Cross-stage rule points into a domain skill.** `RULE_rename-before-drop-rationale.md` links into a django reference for a Python-general recipe — the link reads as the wrong home and confirms the misfile.
- **No base layer to land Python content.** Without `skills/python/`, there's nowhere correct to put `MODULE_SPLIT` / `ENV_DRIVEN_ALLOWLISTS`, so the next Python-general addition repeats the mistake.

## Requirements Trace

- **R1.** A new `skills/python/SKILL.md` exists as a recognized skill (name `python`, valid frontmatter, body \<500 lines) — the deliberate base Python layer (IDEA "Proposal"; user decision: proceed as base layer).
- **R2.** `MODULE_SPLIT_AST_EXTRACTION.md` and `ENV_DRIVEN_ALLOWLISTS.md` are lifted to `skills/python/references/` (user decision: lift both).
- **R3.** django-specific verification/examples inside the lifted refs are **fenced as clearly-marked examples** per skill-writer's cross-project-portability rule — no behaviour change to the recipes (IDEA "Generalize django-isms"; non-goal "no behavior change").
- **R4.** django consumers still discover the lifted recipes: `skills/django/SKILL.md` keeps pointers (the env-driven body firing-stub + both References entries — currently L349/L566/L571 on post-v4.7 main, but **grep the filenames, don't trust the pins**) repointed at `../python/references/…`.
- **R5.** `docs/rules/RULE_rename-before-drop-rationale.md:25` repoints from the django path to the new `skills/python/references/MODULE_SPLIT_AST_EXTRACTION.md`.
- **R6.** The move follows **rename-before-drop**: add new + repoint all references + green link-audit gate, THEN drop the django copies in a dedicated commit, THEN re-audit (IDEA "Sequence as rename-before-drop"; `RULE_rename-before-drop`).

## Scope Boundaries

**In scope:**

- New `skills/python/SKILL.md` + `skills/python/references/{MODULE_SPLIT_AST_EXTRACTION,ENV_DRIVEN_ALLOWLISTS}.md`.
- Repoint: `skills/django/SKILL.md` (body stub + 2 References entries — grep `ENV_DRIVEN_ALLOWLISTS`/`MODULE_SPLIT_AST_EXTRACTION`, currently ~L349/L566/L571) + `docs/rules/RULE_rename-before-drop-rationale.md` (L25).
- `docs/README.md` skills inventory if it enumerates skills (verify in step 1).
- The `~/.claude/skills` symlink already exposes `skills/*` — new skill is picked up automatically, no symlink change.

**Out of scope:**

- Lifting any other django reference (the audit found only these 2 Python-general; the rest are ORM/tenant/HTMX/Celery/i18n-coupled and stay).
- Splitting or merging `django` / `django-frontend` (IDEA non-goal).
- Any recipe behaviour change (IDEA non-goal — pure relocation + example-fencing).

**Explicit non-goals:**

- No thin wrapper command (`commands/python.md`) — the skill is invocable as `/python` directly (skill-writer "no thin wrappers").
- Don't generalize the recipes' *substance* — only fence the framework-specific verification lines as examples.

## Context & Research

### Existing code and patterns to reuse

- `skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md` (103L) — django only in the `manage.py check` verify step; otherwise pure `ast`/`autopep8`/`pyflakes`. References-only (no django body stub) → cleanest lift.
- `skills/django/references/ENV_DRIVEN_ALLOWLISTS.md` (56L) — `frozenset`+env pattern; Python-general. **Has a django body firing-stub at `skills/django/SKILL.md:345-349`** that must be repointed (its examples — BLOCKED_UPLOAD_MIMES, settings.py — are django but the pattern is generic).
- `skills/skill-writer/SKILL.md` — frontmatter contract (name=folder, kebab, `description` \<200 chars noun-dense), body \<500L, **§ Cross-project portability** (fence framework-specific examples), **§ Skills vs commands** (no thin wrapper), minimal skeleton at L221.
- An existing small skill (e.g. `skills/deployment/` or `skills/surgical-tdd/`) as a body-shape anchor for the new SKILL.md.

### Institutional learnings

- `skills/django/references/` lift precedent: IDEA-002 (body→references debloat) + IDEA-007 (references-block consolidation) — same skill-curation lineage; this extends it across-skill.
- `rules/RULE_rename-before-drop.md` — the add→repoint→green→drop→re-test sequence is mandatory here (R6).
- mind-vault auto-memory `feedback_illustrative_examples_not_production` — when fencing the django verify step as an example, don't over-harden it.

### External references

- None — pure markdown relocation; no framework/SDK behaviour the plan is unsure of.

## Key Technical Decisions

- **`skills/python/` as a deliberate base layer (not a thin one-off).** User decision: the audit surface is thin now (2 refs), but `python` is committed as the intentional base beneath django/django-frontend that future Python-general patterns land in — stops the gravity-misfile permanently. The SKILL.md body frames it explicitly as the base layer so the intent survives.
- **Lift both `MODULE_SPLIT` + `ENV_DRIVEN_ALLOWLISTS`.** User decision — gives the new skill non-trivial surface and moves the env-driven body stub now rather than later.
- **Fence, don't rewrite.** The django verify step (`manage.py check`) in MODULE_SPLIT and the settings.py/BLOCKED_UPLOAD_MIMES examples in ENV_DRIVEN become clearly-marked "Example (Django):" blocks; the recipe prose generalizes to "your project's smoke check" / "your framework's settings module." No mechanic changes.
- **django keeps discovery pointers, not copies.** Post-drop, `skills/django/SKILL.md`'s env-driven body stub + both References entries point at `../python/references/…`. django consumers still find the recipes; the canonical home is `python`.
- **Single `git mv` commit — rename-before-drop *intent* honored without the two-commit ceremony** (architect-cleared 2026-06-01). The rule's add→green→drop split exists for *runtime* fall-through bisectability; these are markdown files with no executable importers — the only callers are 4 static links, and a dangling link is caught by the link-audit grep, not at runtime or by bisect. Copy-in-A / `git rm`-in-B would manufacture a transient **dual-canonical-copy window** — the exact misfile-by-gravity smell this IDEA exists to kill. `git mv` keeps one canonical home at every commit, so it's the *more correct* sequencing here, not a shortcut. Honor the rule's intent (never leave a dangling reference) via the green link-audit gate, and record a one-line deviation note in the commit body per the bidirectional-documentation contract.

## IDEA-014 alignment (craft/stack tiering)

Added on the 2026-06-06 refresh. [IDEA-014](../../ideas/IDEA-014-stack-agnostic-agents.md) splits each persona into a **craft core** (stays in the agent) + a **stack adapter** that points at the repo's active framework skill, where every backend skill exposes the same **contract headings** (*ORM eager-loading*, *Input-validation boundary*, *Background jobs*, *Multi-tenancy*, *Translation workflow*). 009 lands first to de-risk that contract — so the refresh pins exactly how `skills/python/` relates to it, to avoid authoring 009 in a way 014 then has to undo.

- **`skills/python/` is the language-base tier, NOT a framework-stack skill.** 014's contract headings are *framework* concepts (ORM, jobs, tenancy). A Python-language base has none of them — `MODULE_SPLIT` (ast-driven package split) and `ENV_DRIVEN_ALLOWLISTS` (`frozenset`+env) are language-general engineering recipes that sit **beneath** the framework skills, not alongside them. The vault tiering this establishes: **craft agent (014) → framework-stack skill (`django`, future `fastapi`/`flask`) → language-base skill (`python`)**. `django` already points *down* into `python/references/` (R4); 014 adds the craft agent pointing *down* into `django`. So 009 does **not** make `skills/python/` satisfy the 014 backend contract, and must **not** invent ORM/jobs/tenancy headings for it.
- **Reserved-heading caution.** `skills/python/SKILL.md`'s section headings must not collide with 014's reserved contract heading set. Collision risk is low (different concept spaces — python uses e.g. *Module/package structure*, *Config & env parsing*), but the author should sanity-check the final heading names against 014's list (in IDEA-014 § "Skill contract") so a future grep-by-heading dispatch doesn't bind a python section to a backend-contract slot. This authoring sanity-check is an **interim** gate: when 014 freezes its contract heading set, the reserved set should land as a deny-list assertion in `tools/validate-skills.sh` (or 014's own validator), migrating "author remembers to check" into a mechanical gate. 009 can only check against 014's current *draft* list today.
- **What 009 de-risks for 014 (the "land it first" payoff):**
  1. **Proves the down-pointer composition.** After extraction, `django/SKILL.md` keeps discovery pointers into `python/references/` rather than copies (R4) — the same skill→skill pointer mechanism 014's craft-agents use to reach stack skills. A clean 009 is a working miniature of 014's resolution model.
  2. **Cleaner 014 Phase-1 audit.** 014 Phase 1 step 1 moves *framework* rules **into** `django`/`django-frontend` under the contract headings. Doing 009 first means the language-general content is already lifted **out** — so 014's audit of "what's stack-specific in django" isn't muddied by python-general recipes, and 014 can't accidentally file a language-general pattern under a django contract heading.
- **Forward-compat the TRIGGER/SKIP hand-off (refines Execution 2a).** `python`'s SKIP arm must hand off to *the active framework stack skill* — phrase it stack-resolution-aware ("defer to the repo's framework skill — `django` today; `laravel`/etc. once IDEA-014's stack detection lands") rather than hard-coding `django`. This keeps 009's hand-off composable with 014's detection order (`.claude/dispatch.md` → `AGENTS.md` → auto-detect) instead of needing a rewrite when 014 ships.

This section is **alignment, not new scope** — no Requirement or Execution step changes substantively; 2a gains the forward-compat phrasing note. The extraction surface (2 refs), the rename-before-drop sequencing, and the green gates are unchanged.

## Open Questions

- **Q1. Does `docs/README.md` (or ONBOARDING) enumerate the skill roster and need a `python` entry?**
  - **Default:** Grep in step 1; if a skills inventory lists each skill, add `python` in the same commit A.
  - **Trade-off:** Missing it leaves the roster stale; trivial to catch.
- **Q2. SKILL.md body — how much inline vs references-only?**
  - **Default:** Thin body — base-layer framing + a firing-conditions stub per lifted pattern (≤5 lines each) + References. Full mechanics stay in the references (skill-writer references-first default).
  - **Trade-off:** A near-empty body risks reading as a stub-skill; the base-layer intro paragraph + 2 firing stubs is enough to justify it without bloat. Resolved: default chosen.

## Execution Sequence

1. **Pre-flight.** `grep -rn 'skills/python\|MODULE_SPLIT\|ENV_DRIVEN' docs/README.md docs/guides/` + confirm no live (non-archive) ref to the two files beyond the 4 known sites. Resolve Q1.
2. **Commit A — add + repoint (rename-before-drop "add new"):**
   a. Write `skills/python/SKILL.md` (name `python`, base-layer framing, 2 firing stubs, References pointing at the 2 refs). Anchor body shape on an existing small SKILL.md. **Include a TRIGGER/SKIP block** — `python` is the vault's maximal false-positive-activation surface (it will want to fire on every `.py` file); the SKIP arm must hand off to **the repo's active framework skill** when framework context is present, so it doesn't misfire + double-load on framework tasks — phrase it stack-resolution-aware (`django` today; `laravel`/etc. once IDEA-014's detection lands), NOT hard-coded to django, so it composes with 014 without a later rewrite (see § IDEA-014 alignment). Keep the base-layer intent paragraph (it's load-bearing — spare it from the skill-writer prose-density cut).
   b. `git mv skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md skills/python/references/` and same for `ENV_DRIVEN_ALLOWLISTS.md`. (Using `git mv` for the relocation; the django-side pointers — not file copies — are what "stay".)
   c. Fence the django-specific blocks in both refs as "Example (Django):" (R3) and generalize the surrounding prose.
   d. Repoint `skills/django/SKILL.md` L349 (env body stub), L566, L571 → `../python/references/…`. (Line numbers re-verified against post-v4.7 main on the 2026-06-06 refresh — MODULE_SPLIT entry drifted L570→L571; grep the two filenames rather than trusting line pins.)
   e. Repoint `docs/rules/RULE_rename-before-drop-rationale.md:25` → `../../skills/python/references/MODULE_SPLIT_AST_EXTRACTION.md`.
   f. Add `python` to `docs/README.md` skills inventory if Q1 found one.
   g. **Green gate:** run `./tools/validate-skills.sh python` (name=folder + frontmatter lint the repo already automates — don't hand-verify it) **and** the link-audit (Verification below); both clean. Self-sweep (doc-heavy). **Single commit**, with the rename-before-drop deviation note in the body (no executable surface → static link-audit is the gate; `git mv` preserves single-canonical-home): `feat(skills): IDEA-009 — add skills/python base layer, lift MODULE_SPLIT + ENV_DRIVEN_ALLOWLISTS`.
3. **Verification** (below), then PR. (No separate drop commit — `git mv` in 2b is atomic; the two-commit split is intentionally collapsed per the Key Technical Decisions deviation note.)

## Verification

- **Skill lint (named green gate).** `./tools/validate-skills.sh python` passes — enforces `name: python` = folder, name-format regex, frontmatter + description presence. This is the repo's own validator; invoke it by name rather than restating its checks by hand.
- **Link integrity, resolved-not-just-matched (green gate, R4/R5).** For every link to the two moved refs, **resolve the relative path against its source file's directory and `test -f` the result** — a string-match grep would pass a `../../skills/python/references/…` link even if the `../../` depth is wrong (the rule-rationale link at `docs/rules/` is two-up). Per-source resolution catches a greps-clean-but-renders-broken link. Then confirm zero links still point at the old `skills/django/references/` location.
- **No dangling django pointer.** `grep -rn 'django/references/\(MODULE_SPLIT\|ENV_DRIVEN\)' skills/ rules/ docs/` returns only archive docs (historical), no live skill/rule.
- **Skill registration.** Fresh-session `/python` (or `Skill python`) loads it; the TRIGGER/SKIP block hands off to the active framework skill on framework context (django today; no double-load on a django task).
- **Recipe parity.** `git diff` of the two moved refs shows only example-fencing + prose generalization — no change to the `ast`/`autopep8`/`pyflakes` or `frozenset` mechanics (R3 / non-goal).
- **django discovery intact.** From `skills/django/SKILL.md`, the env-driven body stub + both References entries resolve to the `python` refs.

______________________________________________________________________

## Architect review (2026-06-01)

Reviewed by **`mv-architect`** dispatched as a real recognized subagent (`Agent(subagent_type: "mv-architect")`) — the first live dispatch of the IDEA-011 schema, which also serves as IDEA-011's R1 fresh-session verification (it resolved + ran the full 4-pass persona).

**Verdict: 🟢 ARCHITECTURALLY SOUND** — dependency inversion is correct (`rule → python ← django`, uni-directional, no cycle); the genericity audit correctly rejects over-lifting; link-integrity-as-gate is the right load-bearing check. Four non-blocking tightenings folded in:

1. **Single `git mv` commit** — rename-before-drop's two-commit form is for runtime bisectability; markdown with static-only link-callers doesn't qualify, and copy/`git rm` would manufacture a transient dual-canonical window. Deviation note required in the commit body. *(folded into Key Technical Decisions + Execution step 2g/3.)*
2. **`./tools/validate-skills.sh python`** as a named green gate — don't hand-verify what the repo's validator owns. *(folded into step 2g + Verification.)*
3. **Resolve-not-just-match link audit** — resolve each relative path (esp. the `../../` rule-rationale link) against its source dir + `test -f`. *(folded into Verification.)*
4. **TRIGGER/SKIP block** in `skills/python/SKILL.md` — `python` is the vault's max false-positive surface; SKIP hands off to django on framework context. *(folded into step 2a.)*

Architect confirmed non-issues: no `docs/README.md` roster entry needed; django `## References` is already a single clean block (no consolidation side-quest); `~/.claude/skills` symlink auto-registers the new skill.

______________________________________________________________________

### Architect re-review — refresh delta (2026-06-06)

After the rebase onto post-v4.7 main + the IDEA-014 alignment deepening, `mv-architect` re-reviewed the **delta** (the `## IDEA-014 alignment` section + the forward-compat TRIGGER/SKIP refinement).

**Verdict: 🟢 ARCHITECTURALLY SOUND** — all four delta claims validated: (1) the python=language-base-tier framing is correct dependency inversion (`craft agent → django → python`, uni-directional, no cycle; 014 line 142 already calls 009 "a clean stack-layer skill"), and correctly declines to invent 014's framework-contract headings on a layer with no use for them; (2) reserved-heading caution disposition is right; (3) both de-risk claims (down-pointer miniature + cleaner 014 Phase-1 audit) are valid and correctly *scoped* (009 demonstrates the pointer composition, NOT stack detection); (4) the SKIP hand-off is a *named-slot* seam ("the active framework skill"), NOT a wired-resolver — looser coupling than hard-coding django, composes with 014's detection without rework. Three advisory findings folded:

- **MINOR** — reserved-heading enforcement is an *interim* authoring check; the durable gate migrates into `tools/validate-skills.sh` when 014 freezes its heading set. *(folded into § IDEA-014 alignment, Reserved-heading caution.)*
- **NIT-1** — R4 + Repoint-scope still carried stale `L566/L570` pins; replaced with "grep the filenames, don't trust pins" + current ~L349/L566/L571. *(folded into R4 + Scope.)*
- **NIT-2** — 014's `depends_on: []` is correctly a *soft* "land-009-first" ordering, not a hard gate; the plan's framing is consistent. No change needed; flagged so the two docs stay aligned if 009 ever becomes a true blocker.

**Status:** ready — architect-reviewed twice (🟢 sound 2026-06-01; 🟢 sound on the 2026-06-06 IDEA-014-alignment refresh, 3 advisories folded). Hand to `/work` with this plan path.
