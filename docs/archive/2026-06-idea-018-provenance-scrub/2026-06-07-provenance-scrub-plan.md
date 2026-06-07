---
stage: plan
slug: provenance-scrub
created: 2026-06-07
source: ./IDEA-018-scrub-prior-project-provenance-identifiers.md
status: shipped
project: mind-vault
---

# IDEA-018: Scrub prior-project provenance identifiers + establish a repeatable scrub runbook

## Context

mind-vault has accumulated a pervasive prior-project identifier — `teisutis` — across **21 tracked files** (architect F2: actual count is **99 hits** today, of which 7 are the legitimately-whitelisted IDEA-018 self-references → **~92 to scrub**; recompute exactly at execution and write the precise number into the runbook's run-log, never the rounded "~90"), built up organically over months of `/compound` provenance bullets. The repo's own `/compound` customer-data scrub gate is explicit that mind-vault must be **public-repo-safe** ("private today, public tomorrow") and even names a `teisutis`-style ref as an example to drop — yet the identifier is woven throughout, including the scrub gate's own example text. Surfaced 2026-06-07 while scrubbing a *different* client leak (`BookingRobot-M`) during compound PR #184; that sprint's identifiers were cleaned in-PR, but the `teisutis` class is too large to ride a compound.

Two things make this more than a one-off `sed`:

1. **It recurs.** This is "not the first and not the last" time mind-vault needs this tidy-up — `/compound` runs land several times a day and each can re-introduce provenance drift. So the durable deliverable is not just *this* scrub but (a) a sharpened **prevention instruction** at the compound gate and (b) a **repeatable, maintained runbook** homed in this IDEA's archive dir, so future recurrences are a logged routine, not a fresh IDEA each quarter.
2. **The prevention must not become the leak.** A hard-coded name denylist in a tracked file re-creates exactly the leak we're scrubbing. Per the user's direction, the guard is **instruction-only** — a well-written gate instruction that teaches the model to recognise the *category* of prior-project identifier, not a brittle regex/blacklist (whose false-positive cost outweighs its value, and which ages badly as models improve).

## Problem Frame

- `git grep -i teisutis` returns ~90 hits across 21 tracked files: 47 in `CHANGELOG.md`, both `skills/{compound,idea}/SKILL.md` bodies, 3 tool-script **comments**, `docs/guides/` (×2), `README.md` (×2), `docs/ideas/README.md` (×2), and 10 archive IDEA/plan/session-note docs.
- The compound scrub gate (`skills/compound/SKILL.md` step 5) relies on a hand-maintained inline grep pattern + "remember to also grep brand names" — which is exactly what let `teisutis` accumulate. The enforcement model needs to shift from "operator remembers an expanding name list" to "instruction makes the agent recognise the class."
- Until this clears, mind-vault cannot safely go public, and there is no captured procedure for the next time drift accumulates.

## Requirements Trace

- **R1.** Every `teisutis` occurrence in tracked files is generalised to neutral framing (drop the project tag, keep the lesson) — **except** the IDEA-018 archive dir + its live ideas-index entry, which are deliberately whitelisted (Q2 answer) so the IDEA stays self-explanatory.
- **R2.** The 3 tool-script hits (`tools/find_copilot_comments.sh` ×2, `tools/find_claude_comments.sh` ×1) are edited and both scripts still parse (`bash -n` clean). *(Research already confirmed all 3 are comments, no functional defaults — see Context & Research.)*
- **R3.** The `/compound` scrub gate instruction (`skills/compound/SKILL.md` step 5) is rewritten to teach the agent to recognise the **category** of prior-project/repo/client identifier by understanding — no mechanical denylist, no new tracked name list, no `tools/` script. **The rewrite must add a forcing function** (architect F3): a *produce-a-classification* step the agent cannot skip silently — before commit, list every proper-noun token in the staged diff and classify each `{mind-vault-own | foreign → scrub | generic}`, emitting the classification. A guard satisfiable without emitting anything observable is decorative and fails this requirement.
- **R4.** A repeatable **provenance-scrub runbook** is created and homed in this IDEA's archive dir, carrying the procedure (inventory → categorise → generalise → verify) plus a dated run-log; this scrub is its first logged entry.
- **R5.** Generalisation phrasing is consistent and decided once per category (see Key Technical Decisions), not improvised per file.
- **R6.** Real project names live **only** in local memory (`~/.claude`) + git history + commit messages — never re-introduced into tracked file bodies.
- **R7.** Verification gate (architect F1 — positive count-assertion, not a brittle content-exclusion): outside the whitelisted IDEA-018 archive dir, `git grep -i teisutis` returns **zero** hits — verified by count. (Originally this was `1`, allowing the ideas-index In-Progress line; the `/wrap` pass then moved that line to References-Implemented in clean framing, dropping it to `0`. The archive dir is the sole whitelist.) Any non-zero count blocks merge.

## Scope Boundaries

**In scope:**

- All 21 tracked files containing `teisutis` (full inventory in Context & Research).
- The compound scrub-gate instruction rewrite (R3).
- The archive-homed runbook + first run-log entry (R4).
- An opportunistic grep for *other* stray prior-project/client names while in here (e.g. confirm `BookingRobot-M`/`br-*` stayed clean post-#184).

**Out of scope:**

- Git history rewriting. Commit messages and historical commits keep their refs (acknowledged-noisy per the scrub gate). Only **current file bodies** must be clean.
- Local memory (`~/.claude`) — the correct, untracked home for real names; untouched.
- IDEA-016 / IDEA-017 work.

**Explicit non-goals:**

- NOT a mechanical denylist/blacklist of any kind, tracked or local (explicit user direction — instruction-only guard).
- NOT a rewrite of the compounded *lessons*; provenance generalisation only — the knowledge stays intact.
- NOT a full "audit every conceivable identifier forever" sweep beyond `teisutis` + a quick stray-name check.

## Context & Research

### Findings from the /plan research pass (2026-06-07)

- **Tool-script hits are comment-only — the IDEA's central risk is void.** All 3 occurrences are narrative comments (`# … PR #474 (teisutis)`, `# … (teisutis #516)`); `grep -nE "(REPO|OWNER|DEFAULT|repo|owner)=.*teisutis|teisutis/"` returns nothing, and `bash -n` passes on both scripts. There is **no functional default** to parameterise — the frontmatter `auto_safe_reason` has been corrected to reflect this. The "behavioural test pass" the IDEA worried about collapses to a `bash -n` smoke check.
- **The scrub gate uses `teisutis` as its own example** (`skills/compound/SKILL.md:143`: `(Teisutis) IDEA-178`, `teisutis PR #475`). Generalising it is mildly meta — replace the example token, keep the teaching.
- **Full inventory (tracked-only):** `CHANGELOG.md` (47) · `docs/archive/2026-06-idea-012-claude-code-review-engine/IDEA-012-…md` (8) · 2 session-notes (7 each) · `docs/archive/2026-06-idea-012-…/…-plan.md` (4) · `docs/archive/2026-05-idea-001-playwright-plumbing/ROADMAP.md` (3) · `README.md` (2) · `docs/ideas/README.md` (2) · `docs/archive/2026-05-idea-001-…/IDEA-001-…md` (2) · `tools/find_copilot_comments.sh` (2) · `tools/find_claude_comments.sh` (1) · `skills/idea/SKILL.md` (1) · `skills/compound/SKILL.md` (1) · `docs/guides/AGENT_PORTABILITY.md` (1) · `docs/guides/SKILL_AUTHORING_WALKTHROUGH.md` (1) · 4 more archive IDEA/plan docs (1 each).

### Existing code and patterns to reuse

- `skills/compound/SKILL.md` step 5 (§ Mind-vault promotion → customer-data scrub gate) — the instruction being hardened (R3). The "would this be safe in a public repo today?" test stays as the gate's spine.
- `git grep -i <token>` — the right inventory/verification tool: tracked-files-only, ignores `.git/`, respects pathspec exclusions for the whitelist.
- The two SKILL bodies / guides already model placeholder conventions (`~/projects/<project>`, "illustrative fences") — reuse that style for example slots.

### Institutional learnings

- `skills/compound/SKILL.md` THIS-MACHINE-ONLY routing — real names belong in `~/.claude`, not tracked mind-vault. This scrub is that rule applied retroactively.
- `RULE_self-sweep-before-push` trigger 5 (doc-consistency sweep) — this is a doc-heavy PR; run the consistency pass before push.

## Key Technical Decisions

- **Instruction-only guard (no denylist).** Per user direction: a name blacklist's false-positive cost outweighs its value and ages badly; a well-written instruction wins long-term as models improve. R3 rewrites the gate prose to define the *class* (any proper-noun project/repo/client name that isn't mind-vault's own; provenance tags like `(X) IDEA-N` / `X PR #N`; project-rooted paths `~/projects/X`), the *why* (public-repo-safety), and the *transform* (drop tag, keep lesson) with before/after examples. The existing generic-pattern grep stays only as an optional cheap aid, explicitly **not** the enforcement mechanism.
- **Keep IDEA-018 self-references (Q2).** The IDEA-018 archive dir legitimately names the scrub target for legibility; it is the sole whitelist. (Q2 originally also kept the ideas-index In-Progress line, but `/wrap` moved that entry to References-Implemented in clean framing — so the live index no longer names the target and the outside-archive count is `0`.)
- **Archive-homed, maintained runbook (Q-runbook).** The repeatable procedure + run-log lives at `docs/archive/2026-06-idea-018-provenance-scrub/PROVENANCE_SCRUB_RUNBOOK.md`. Future recurrences run it and append a log entry rather than spawning a new IDEA — the archive dir is the canonical home per user direction ("maintain its knowledge in archive"). The compound gate instruction (R3) points at it **by IDEA id** ("the provenance-scrub runbook in the IDEA-018 archive"), **not** by hard-coding the dated path (architect F4 — avoids a stale dead-link if Q2's escape hatch ever promotes it to `docs/maintenance/`).
- **Generalisation conventions (decided once, R5):**
  - *Prose example name* → "a consuming project" / "an external project".
  - *Name-shaped token genuinely needed* (e.g. idea SKILL numbering example "teisutis IDEA-166") → obviously-fake placeholder `project-x` (lowercase, unmistakable).
  - *Path / command* (`~/projects/teisutis`) → `~/projects/<project>`.
  - *Provenance tag in CHANGELOG/archive* (`(teisutis)`, `teisutis IDEA-N`, `teisutis PR #N`) → **drop the tag**, keep the lesson; if a bare unresolvable `IDEA-N` remains, drop it or qualify `(external)`.
- **Commit sequence by risk-category** (clean review surface; no symbol coupling so `RULE_rename-before-drop` doesn't bind): guard+runbook → tool scripts → SKILL/guides/READMEs → CHANGELOG+archive bulk → final verify.

## Open Questions

- **Q1. Placeholder for name-shaped slots — `project-x` vs a worded descriptor everywhere?**
  - **Default:** Use worded descriptors in prose ("a consuming project") and reserve `project-x` only where the sentence structurally needs a name token. Resolved unless you prefer a single uniform token.
  - **Trade-off:** Worded reads more naturally; a uniform fake token is more greppable but can itself look like a real name.
- **Q2. Runbook home — IDEA-018 archive dir (chosen) vs a stable `docs/maintenance/` path?**
  - **Default:** IDEA-018 archive dir, per your "maintain its knowledge in archive" direction. If recurrences feel awkward referencing a dated `idea-018` dir, a follow-up can promote it to `docs/maintenance/PROVENANCE_SCRUB.md` with a back-pointer.
  - **Trade-off:** Archive keeps the run-history co-located with origin; a stable path is more discoverable for routine maintenance.
- **Q3. The `docs/ideas/README.md:53` IDEA-012 entry says "teisutis IDEA-214" (deferred-validation ref) — drop or generalise?**
  - **Default:** Generalise to "a consuming project's later IDEA" (keep the deferral meaning, drop the foreign tag). This line is NOT a whitelisted IDEA-018 self-ref, so it must clear.
  - **Trade-off:** Loses the exact cross-project tracking number (still in git history); gains a clean public surface.

## Execution Sequence

1. ✅ `6c1cce9` **Guard + runbook (commit 1).**
   - Rewrite `skills/compound/SKILL.md` step 5 scrub-gate instruction per R3 (define class / why / transform + examples; demote the grep to an optional aid; point at the runbook). This commit also generalises that file's own `teisutis` example (`:143`).
   - Create `docs/archive/2026-06-idea-018-provenance-scrub/PROVENANCE_SCRUB_RUNBOOK.md`: procedure (inventory `git grep` → categorise by risk → generalise per conventions → verify gate) + a "Run log" section with this scrub as entry #1 (date, exact counts, PR ref).
2. ✅ `829d5fa` **Tool scripts (commit 2).** Generalised the 3 comments in `tools/find_copilot_comments.sh` + `tools/find_claude_comments.sh`; `bash -n` clean on both. *(Confirmed all 3 were comments — no functional default.)*
3. ✅ `7f5f187` **SKILL bodies + guides + READMEs (commit 3).** `skills/idea/SKILL.md`; `docs/guides/AGENT_PORTABILITY.md`; `docs/guides/SKILL_AUTHORING_WALKTHROUGH.md`; `README.md` ×2; `docs/ideas/README.md` IDEA-012 entry (Q3). *(The IDEA-018 In-Progress index line is whitelisted — left in place.)*
4. ✅ `0abca11` **CHANGELOG + archive bulk (commit 4).** `CHANGELOG.md` (47) + 11 archive IDEA/plan/session-note docs (83 hits total) — uniform drop-the-tag generalisation via `mv-documentation`. *(IDEA-018 archive dir whitelisted.)*
5. ✅ **Final verify + self-sweep — GATE PASS.** F1 positive-count gate ran: outside-whitelist count == **0** (the `/wrap` index rewording dropped the last self-reference; archive dir is the sole whitelist). `bash -n` clean; stray-name grep (`bookingrobot|br-internal`) clean. Zero stragglers.

## Verification

```bash
# R7 — positive count-assertion (architect F1): outside the whitelisted archive
# dir, ZERO hits must remain. (The ideas-index entry was generalised to clean
# framing during /wrap, so the archive dir is the sole whitelist.) Any hit blocks merge.
n=$(git grep -i teisutis -- ':!docs/archive/2026-06-idea-018-provenance-scrub' | wc -l)
echo "outside-archive teisutis hits: $n (expect 0)"
git grep -i teisutis -- ':!docs/archive/2026-06-idea-018-provenance-scrub'   # eyeball: must be empty
test "$n" -eq 0 && echo "GATE PASS" || echo "GATE FAIL — investigate"

# R2 — tool scripts still parse:
bash -n tools/find_copilot_comments.sh && bash -n tools/find_claude_comments.sh && echo "scripts OK"

# Stray-name check (should already be clean post-#184):
git grep -iE 'bookingrobot|br-internal' || echo "no stray client names"

# R4 — runbook exists with a run-log:
test -f docs/archive/2026-06-idea-018-provenance-scrub/PROVENANCE_SCRUB_RUNBOOK.md && echo "runbook present"
```

---

**Status:** ready — architect-reviewed 2026-06-07 (🟡 REQUIRES ABSTRACTION → all 5 findings folded: F1 positive-count gate, F2 exact-count run-log, F3 forcing-function guard, F4 id-based pointer, F5 mandatory blocking gate). Awaiting user approval before `/work`.
