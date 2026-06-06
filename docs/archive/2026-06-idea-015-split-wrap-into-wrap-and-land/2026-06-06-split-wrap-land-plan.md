---
stage: plan
slug: split-wrap-land
created: 2026-06-06
source: ./IDEA-015-split-wrap-into-wrap-and-land.md
status: shipped
project: mind-vault
---

# Split /wrap into /wrap (docs) + /land (merge + teardown) + retire the double-review

## Context

The finish of the sprint workflow has two coupled problems. (1) `/wrap` fuses **documentation finalization** (Steps 1–4b, 6, 6b, 7) with **merge/teardown operations** (Step 5 teardown, Step 8 atomic merge, `--integration` batch teardown) under one trigger — different timing, different HITL gate, different blast radius, a ~900-word frontmatter, and a `--scope=full` value that exists only to glue merge onto the docs pass. (2) The canonical chain runs a **double review**: `work → review (deliverables) → wrap (docs) → review (docs) → compound` — a code-only review before docs are finalized, then a second review of the docs. Since review engines expect docs already in order and `/review-loop` already iterates on every fix push, the first pass is premature and the second is ceremony.

This plan splits `/wrap` → `/wrap` (docs) + `/land` (merge+teardown), **collapses the double review into one post-wrap review**, and reconciles every workflow-chain depiction to the single canonical chain: `/idea → /plan → /work → /wrap (docs) → /review-loop → /land (merge) → /compound`.

## Problem Frame

- A bare `/wrap` and `/wrap --scope=full` are the same skill doing very different things; merge is an implicit `--scope=full` re-run rather than a named stage.
- The frontmatter description is the single largest always-loaded block among the skills; ~half is merge/teardown/scope-enum prose.
- **The double-review ceremony is redundant.** Reviewing deliverables before docs are finalized means the engine sees an incomplete PR; the work then needs a second review after wrap. `/review-loop` already loops to clean on every push, so one review over the wrapped (complete) PR absorbs both code and doc findings. The two-pass model is encoded in `WRAP_BEFORE_REVIEW.md` (built entirely around it), wrap's pass-1/pass-2 language, and sprint-auto's S3–S7 state machine (separate deliverables/docs passes, split 20/5 caps).
- The canonical chain has no named *merge* stage — merge hides behind `--scope=full`.
- `sprint-auto/references/escalation-policy.md` references a `/wrap-docs` name that does not exist (L11, L57).

## Requirements Trace

- **R1.** A new `/land` skill owns Step 8 atomic merge, Step 5 worktree/volume teardown, and `--integration <batch-iso>` batch teardown, with `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md` relocated under it.
- **R2.** `/land NNN` pre-merge performs the atomic merge (non-protected target) and, since the merge unblocks teardown, proceeds to teardown in the same pass; `/land NNN` post-merge does teardown only; `/land --integration <batch-iso>` does batch teardown only. Protected target → no merge, hand back PR URL (RULE_git-safety preserved).
- **R2a. (post-merge handoff — architect finding 2).** `/wrap NNN` on an already-merged PR runs the **docs fallback only** (no teardown — that moved to `/land`) and MUST end its hand-back with "now run `/land NNN` to tear down the worktree." Commit 3 must rewrite `skills/wrap/SKILL.md:82`'s note — under the split, no `/wrap` mode reaches teardown.
- **R3.** `/land`'s **precondition guard** runs **only in the pre-merge merge branch**: verify IDEA frontmatter `complete`, devlog/CHANGELOG entry exists, ideas-index entry moved — refuse to merge (point at `/wrap NNN`) when docs aren't finalized. Replaces the old `--scope=full` idempotent docs re-run. Post-merge teardown and `--integration` SKIP the guard — `--integration` runs on a batch whose per-IDEA devlogs are *deliberately deferred* to S11.7, so a devlog check there would false-refuse every batch (architect finding 3).
- **R4.** `/wrap` retains only docs steps (1, 2, 3, 4, 4b, 6, 6b, 7) + the post-merge docs fallback (no teardown, per R2a). Step 5, Step 8, `--integration` removed. References list drops the two relocated entries; the stale `/wrap-docs`+missing-`/land` chain at `SKILL.md:419` fixed in the same pass (architect finding 6).
- **R5.** `--scope=full` is **deprecated, not removed**: emits a loud notice, runs docs as `docs`, prints the exact `/land NNN` command + "this did NOT merge (it did under the old `--scope=full`)", never auto-merges (architect finding 4). `--scope=docs` / `--scope=idea-only` unchanged.
- **R6.** The canonical chain is reconciled across every live surface to the **single-review** form: `/idea → /plan → /work → /wrap (docs) → /review-loop → /land (merge) → /compound`. No review-before-wrap pass.
- **R7.** sprint-auto teardown call `/wrap --integration` → `/land --integration`; stale `/wrap-docs` → `/wrap`. sprint-auto's S11 integration *merge* logic untouched (verified: S11.6 is bare `git merge --no-ff`, S11.7 is bespoke batch-wrap prose — neither used `/wrap --scope=full`).
- **R8.** No `commands/land.md` wrapper. No edits to frozen `docs/archive/**` / `docs/plans/**`.
- **R9. (retire double-review — manual path).** Collapse the manual chain from two review passes to one post-wrap review. Rewrite `WRAP_BEFORE_REVIEW.md` from the two-pass model (`work → review → wrap → review → full`) to single-pass (`work → wrap → review → land`). Update `review-loop`'s pre-flight (wrap-first guidance stays; "second docs pass" framing goes), wrap's pass-1/pass-2 language, and `ATOMIC_MERGE.md`'s two-pass framing. Reviewing more than once stays *allowed* (mid-`/work` Claude pass for early signal); only the mandatory ceremonial second pass is retired.
- **R10. (retire double-review — sprint-auto, Phase B).** Collapse sprint-auto's per-IDEA S3–S7 into a single post-wrap review pass: today S3 (deliverables review) + S4 (deliverables escalation) run *before* S5 wrap, then S6 (docs review) + S7 (docs escalation) after. New order: S5 wrap (`--scope=idea-only`) FIRST, then ONE review+escalation pass over the wrapped per-IDEA PR. **Merged escalation cap = 20** (NOT 5, NOT 25 — architect finding 1): the single pass now reviews code+docs together, so it must be sized for the **code long tail** that the old "Why 20 deliverables" rationale documented (migration/model/test triads, type-refactor propagation = 4–6 attempts), not the doc-finding short tail; doc findings that won't converge are caught by `/review-loop`'s own `no_progress_map`, not by a tighter sprint-auto cap. Fold the deleted "Why 20"/"Why 5" sections of `escalation-policy.md` into a one-line rationale on the merged cap. The state-machine diagram in `post-pr-sequence.md` must **delete S3/S4** (not insert S5 before a surviving S3) so the flow reads S5 wrap → [single review+escalation] → S9 (architect finding 2). Integration-state review (S11.10) is unchanged (deliverables-class review of the integrated branch, its own cap 20, orthogonal to the per-IDEA cadence).

## Scope Boundaries

**In scope (one PR — wrap/land split + single-review collapse + full chain reconcile):**

- New `skills/land/SKILL.md` + `skills/land/references/{ATOMIC_MERGE.md,WORKTREE_TEARDOWN.md}` (`git mv`).
- `skills/wrap/SKILL.md` — strip Step 5/8/`--integration`, deprecation-shim the `full` scope, R2a hand-back, rewrite L82 + L419 + L178, trim frontmatter, fix References + pass-1/pass-2 language, rewire teardown call → `/land --integration`.
- `skills/wrap/references/WRAP_BEFORE_REVIEW.md` — rewrite two-pass → single-pass (R9). **No forward-pointer** — sprint-auto goes single-pass in the same PR (the architect's bridge-state finding only applied to the two-PR split, now dropped).
- `skills/review-loop/SKILL.md` (+`references/engine-claude.md`) — pre-flight wrap-first guidance kept, second-docs-pass framing removed.
- **All** chain depictions (manual + sprint-auto, one PR): `README.md` **L19, L38, L71, L109**, `docs/guides/SPRINT_WORKFLOW.md` **L46 + manual chain ~L156**, `docs/guides/ONBOARDING.md` **L250**, `docs/ideas/README.md` (mermaid), `skills/plan/references/batching-for-sprint-auto.md:129`, `skills/work/SKILL.md`, `skills/ideate`, `skills/idea/references/IDEAS_LOCATION_STATUS.md`, `skills/django-frontend`.
- **sprint-auto cadence (R10):** `skills/sprint-auto/SKILL.md` — S3–S7 state-machine collapse, caps tuple (`20/5/10/10/20/5` → merged per-IDEA cap **20**), description chain, hand-back examples (`:204-205` "deliverables clean / docs clean" → single verdict). `skills/sprint-auto/references/{post-pr-sequence.md,escalation-policy.md,integration-stage.md,safety-gates.md}` + `assets/auto-run-log-template.md` — sequence diagrams (delete S3/S4), cap definitions (fold "Why 20"/"Why 5" → merged-cap rationale), deliverables/docs-pass language.
- **Denominator-closing grep (run FIRST):** `grep -rn "→ /wrap\|/wrap →\|wrap (docs)\|wrap (pre-merge)\|wrap-docs\|teardown\|--scope=full\|two-pass\|two review\|review (deliverables)\|review (docs)\|deliverables pass\|docs pass\|pass 1\|pass 2" skills/ docs/ README.md | grep -v archive` — pin every hit into a line-anchored edit list. Single PR → every hit is in scope (no phase tagging); the authoritative denominator for the C5 green gate.

**Out of scope:**

- Merge/teardown *mechanics* — relocation + rename, not redesign.
- sprint-auto integration-stage merge logic (S11.6/S11.7/S11.10).
- Any `commands/` wrapper for `/land`.

**Explicit non-goals:**

- NOT renaming the docs skill — stays `/wrap`.
- NOT removing `--scope=full` outright — graceful deprecation for one cycle.
- NOT removing the *option* to review more than once (mid-`/work` Claude pass stays) — only the mandatory ceremonial second pass is retired.
- NOT editing historical archive/plan docs.

## Context & Research

### Existing code and patterns to reuse

- `skills/wrap/SKILL.md` — L48-85 scope table; L87-115 mode detection (`/land` reuses the shape); L324-338 Step 5 + `--integration`; L386-390 Step 8; L82 teardown note; L178 two-pass idempotency guard; L411/413/419 References; L34 "S3+S4 … S6+S7" trigger bullet.
- `skills/wrap/references/{ATOMIC_MERGE,WORKTREE_TEARDOWN,WRAP_BEFORE_REVIEW}.md` — first two relocate; WRAP_BEFORE_REVIEW rewrites.
- `skills/sprint-auto/SKILL.md:118` (S3 deliverables review), `:135` (S6 docs review), `:269` (two-pass review-loop per IDEA), `:276` (caps tuple `20/5/10/10/20/5`), `:306` ("called twice per IDEA") — the S3–S7 collapse sites.
- `skills/sprint-auto/references/integration-stage.md:90-122` — verifies S11.6/S11.7 use no `--scope=full` (R7).

### Institutional learnings

- `rules/RULE_rename-before-drop.md` — add `/land` + rewire (green) before dropping `--scope=full`/Step 5/8 (own commit), then re-verify. "Test pass" = consistency grep sweep.
- `rules/RULE_self-sweep-before-push.md` trigger 5 — every commit doc-heavy; sweep symmetry, chain-string consistency, link resolution.
- `feedback_version_bump_adopter_magnitude` (memory) — size the bump by adopter impact: this changes the review cadence every adopter runs, so it's a significant minor at least; coordinate with IDEA-014's claimed v5 if they land close (decide at `/wrap`).
- README's sprint-auto **UNSTABLE** banner — reason Phase B (sprint-auto) phases behind Phase A; sprint-auto isn't battle-tested post-v3.2, so its cadence collapse should land as its own reviewable phase.

### External references

- None — internal skill/doc refactor.

## Key Technical Decisions

- **`/land` is one skill spanning merge + teardown, mode-detected** (pre-merge → merge[+teardown]; post-merge → teardown; `--integration` → batch teardown). Mirrors wrap's mode detection.
- **Single review after wrap.** `work → wrap → review → land`. The review-loop's existing fix-iteration absorbs both code and doc findings, so a second ceremonial pass adds no signal. Reviewing more than once stays optional.
- **Precondition guard replaces the idempotent docs re-run, scoped to the merge branch only.**
- **`--scope=full` deprecates via loud redirect, never auto-merges.**
- **Phase the work.** Phase A = manual path (split + single-review + WRAP_BEFORE_REVIEW). Phase B = sprint-auto S3–S7 collapse. Phase A is independently shippable and reviewable; Phase B carries the sprint-auto blast radius and lands behind it.
- **rename-before-drop commit sequence** within each phase.

## Open Questions

- **Q1. `/land NNN` pre-merge auto-proceeds to teardown in the same pass?** Default: yes (mirrors wrap's "Step 8 unblocks Step 5"); `--keep-stack`/`WRAP_KEEP_STACK=1` already guards inspection needs.
- **Q2. `--scope=full` deprecation — run-docs-then-stop vs do-nothing?** Default: run docs, then stop with loud `/land` guidance (don't punish muscle-memory; still finalizes the useful half).
- **Q3. Precondition-guard strictness — refuse vs warn?** Default: refuse (point at `/wrap NNN`), no override flag in v1; reversible (run `/wrap`, re-run `/land`).
- **Q4. One PR or two? — RESOLVED: one PR** (user decision, reduce ceremony). Everything lands atomically, which *dissolves* the architect's phase-boundary finding (README L71/L109 + sprint-auto behaviour flip in the same merge — no doc/behaviour contradiction window on `main`) and removes the need for the `WRAP_BEFORE_REVIEW` forward-pointer (no shipped bridge state). `RULE_rename-before-drop` still applies as **commit ordering within the one PR** (add `/land` → rewire → drop legacy), keeping the branch bisectable. Trade-off: a larger single review surface (~20 files) — the review-loop's `LARGE_PR_INDEPENDENT_REVIEW` escalation may trigger at hand-back; accept it. **Sequencing note:** land `/work` on this PR *after* tonight's sprint-auto stability run (which exercises the current two-pass cadence on `main`), so the cadence change is made against a proven-stable baseline rather than concurrently with proving it.

## Execution Sequence

One PR, `RULE_rename-before-drop` enforced as commit ordering (add `/land` → rewire everything → drop legacy → re-sweep). All chain surfaces — manual AND sprint-auto — land in this one PR, so there is no on-`main` contradiction window and no shipped bridge state.

1. ✅ `3f5937f` **C1 — add `/land` (additive, non-breaking).** Create `skills/land/SKILL.md` (mode detection + pre-merge-only precondition guard + merge + teardown + `--integration`; References → relocated docs). `git mv skills/wrap/references/{ATOMIC_MERGE,WORKTREE_TEARDOWN}.md skills/land/references/`; same commit repoints `skills/wrap/SKILL.md`'s Step 5/8 inline links. Verify: all links resolve; `/land` coherent; **wrap still reads coherently at this HEAD** (bridge state — Step 5/8 prose + References framing intact, just repointed; architect R1 finding 5).
2. ✅ `f91699d` **C2 — collapse sprint-auto cadence (behaviour) (R10).** Reorder sprint-auto's per-IDEA loop: S5 wrap (`--scope=idea-only`) first, then ONE review+escalation pass. Edit `sprint-auto/SKILL.md` state machine + `:118`/`:135`/`:269`/`:306` + hand-back examples `:204-205`; set the merged per-IDEA review cap to **20** at `:276` + `escalation-policy.md` (fold "Why 20"/"Why 5" → one merged-cap rationale; 20 sized for the code long tail — architect R2 finding 1); **delete S3/S4 from** `post-pr-sequence.md`'s state diagram (~L54-77) so it reads S5 → [single review+escalation] → S9 (not S5-before-surviving-S3 — architect R2 finding 2); update `integration-stage.md` + `auto-run-log-template.md`. Leave S11.10 integration review untouched. (Behaviour first so the docs in C3 describe a reality that already exists on the branch.)
3. ✅ `d9b3eb9` **C3 — reconcile ALL chain depictions to single-review + insert `/land`.** Run the denominator grep; edit every hit (manual AND sprint-auto, since it's one PR): README (mermaid, glyphs, **L19**, **L38**, **L71**, **L109**), SPRINT_WORKFLOW (**L46** + manual chain ~L156), ONBOARDING (**L250**), ideas/README mermaid, `batching-for-sprint-auto.md:129`, `work/SKILL.md` hand-off, `review-loop/SKILL.md` + `engine-claude.md` pre-flight. Rewrite `WRAP_BEFORE_REVIEW.md` two-pass → single-pass (R9) — **no forward-pointer needed** (sprint-auto already single-pass as of C2). Verify: every chain depiction (manual + sprint-auto) shows the single canonical chain.
4. ✅ `b9da985` **C4 — drop legacy from `/wrap`.** Remove Step 5/8/`--integration`; deprecation-shim `--scope=full` (loud, R5); add R2a post-merge hand-back; rewrite L82 + L419 + L178 (two-pass idempotency rationale → single-run); rewire the teardown call `/wrap --integration` → `/land --integration` across sprint-auto (depends on `/land` from C1); trim frontmatter; fix References list. Verify: `grep "Step 8\|atomic merge\|scope=full" skills/wrap/SKILL.md` only hits the shim; `grep -rn "/wrap-docs" skills/ docs/` → zero; `grep -rn "/wrap --integration" | grep -v archive` → zero; wrap line count + frontmatter materially smaller.
5. ✅ **C5 — consistency re-sweep (post-drop green gate).** Re-run the full denominator grep; assert NO live surface (outside frozen archive / `IDEA_integration_branch.md`) describes the two-pass flow or `--scope=full`-as-merge; fix stragglers. This is the post-drop green gate for the PR.
6. **Closeout (at this IDEA's own `/wrap` + `/land`, post-review):** CHANGELOG + version bump (size by adopter magnitude — review-cadence change is adopter-visible; likely a significant minor, coordinate with IDEA-014's v5).

## Verification

- `grep -rn "/wrap --integration" skills/ docs/ README.md | grep -v archive` → zero (migrated to `/land`).
- `grep -rn "/wrap-docs" skills/ docs/` → zero (incl. `SKILL.md:419`, `escalation-policy.md:11,57`).
- `grep -rn "Step 8\|atomic-merge\|scope=full" skills/wrap/SKILL.md` → hits only in the deprecation shim.
- `ls skills/land/references/` → `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md`; absent from `skills/wrap/references/`.
- **Single-review denominator closed (whole PR):** `grep -rn "deliverables pass\|docs pass\|two-pass\|two review\|called twice\|20/5\|review (deliverables)\|review (docs)" skills/ docs/ README.md | grep -v -e archive -e IDEA_integration_branch` → zero in live cadence-describing prose (frozen archive + `IDEA_integration_branch.md` v3.1 design record excepted). `WRAP_BEFORE_REVIEW.md` describes `work → wrap → review → land` (no forward-pointer — sprint-auto is single-pass in the same PR). README L19/L38/L71/L109 all single-review. `escalation-policy.md` + SKILL `:276` show the merged cap **20** (not `20/5`); `post-pr-sequence.md` diagram has no S3/S4.
- Post-merge `/wrap NNN` fallback hand-back contains the literal "run `/land NNN`" pointer (R2a); `/wrap` no longer claims to tear down anywhere.
- `--scope=full` deprecation notice contains the exact `/land NNN` string + "did NOT merge" statement; `grep -rn "scope=full" skills/sprint-auto/ skills/work/` → no automation dependency on its merge behavior.
- `wc -l skills/wrap/SKILL.md` materially below 420; wrap frontmatter description materially shorter.
- Link-resolution sweep clean across `wrap`, `land`, `WRAP_BEFORE_REVIEW.md`, rewired sprint-auto refs.
- Architect re-review verdict folded (mandatory — scope expanded since first review).

---

**Status:** ready — architect-reviewed twice (🟡 → 🟡, all findings folded). Round 1 (split): R2a post-merge handoff, R3 guard scoping, R5 loud deprecation, denominator/surface-map, A1 bridge-state, SKILL.md:419. Round 2 (double-review retirement): merged cap **20** sized for code long tail (R10), delete-S3/S4 diagram, README L71/L109 → Phase B (phase-boundary fix), WRAP_BEFORE_REVIEW forward-pointer bridge state. Single-review collapse + S5-first reorder validated SOUND; R7 (sprint-auto S11 never used `--scope=full`) verified true. **Ships as ONE PR** (user decision) — `RULE_rename-before-drop` enforced as commit ordering (C1–C5); the one-PR atomicity dissolved the architect's two-PR phase-boundary + forward-pointer findings.
