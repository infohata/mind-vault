---
stage: plan
slug: split-wrap-land
created: 2026-06-06
source: ./IDEA-015-split-wrap-into-wrap-and-land.md
status: ready
project: mind-vault
---

# Split /wrap into /wrap (docs) + /land (merge + teardown)

## Context

`/wrap` carries two structurally different jobs under one trigger: **documentation finalization** (Steps 1–4b, 6, 6b, 7) and **merge/teardown operations** (Step 5 teardown, Step 8 atomic merge, the `--integration` batch teardown). They differ in timing (pre-merge docs vs the destructive post-merge moment), in HITL gate (none vs the protected-branch merge boundary), and in blast radius. The coupling manifests as a ~900-word frontmatter `description` loaded every session, a `--scope=full` enum value whose only purpose is to glue merge onto the docs pass, and a 420-line SKILL.md mixing idempotent docs guards with destructive operations. Splitting along the seam gives two focused skills and lets the documented workflow name its final merge stage (`/land`) instead of hiding it behind a scope flag.

## Problem Frame

- A bare `/wrap` and `/wrap --scope=full` are the same skill doing very different things; the operator has to remember which scope merges. IDEA-008 already made `docs` the safe default, but merge is still a wrap responsibility.
- The frontmatter description is the single largest always-loaded block among the skills; roughly half of it is merge/teardown/scope-enum prose.
- The canonical workflow chain (`/idea → /plan → /work → review → /wrap → review → /compound`) has no named *merge* stage — merge is an implicit `--scope=full` re-run, which reads as a footnote rather than a step.
- `sprint-auto/references/escalation-policy.md` already references a `/wrap-docs` name that does not exist (lines 11, 57) — a dangling pointer that confirms prior intent for this split.

## Requirements Trace

- **R1.** A new `/land` skill owns Step 8 atomic merge, Step 5 worktree/volume teardown, and the `--integration <batch-iso>` batch teardown, with the `ATOMIC_MERGE.md` + `WORKTREE_TEARDOWN.md` references relocated under it.
- **R2.** `/land NNN` pre-merge performs the atomic merge (non-protected target) and, since the merge unblocks teardown, proceeds to teardown in the same pass; `/land NNN` post-merge does teardown only; `/land --integration <batch-iso>` does batch teardown only. Protected target → no merge, hand back PR URL (RULE_git-safety preserved).
- **R2a. (post-merge handoff — architect finding 2).** The post-merge moment is split: `/wrap NNN` on an already-merged PR runs the **docs fallback only** (it no longer tears down — teardown left with `/land`), and MUST end its hand-back with the explicit line "now run `/land NNN` to tear down the worktree." Symmetric with R5's redirect. Commit 3 must also rewrite `skills/wrap/SKILL.md:82`'s load-bearing note ("Do not phrase `docs` as cannot reach teardown") — under the split, `docs` (and every `/wrap` mode) **never** reaches teardown, so that sentence inverts.
- **R3.** `/land`'s **precondition guard** runs **only in the pre-merge merge branch** of `/land NNN`: verify IDEA frontmatter is `complete`, the devlog/CHANGELOG entry exists, and the ideas-index entry has moved — refuse to merge (pointing at `/wrap NNN`) when docs are not finalized. It replaces the old `--scope=full` idempotent docs re-run. **Post-merge teardown and `--integration` batch teardown SKIP the guard** (nothing to merge) — critically, `--integration` operates on a sprint-auto batch whose per-IDEA devlog entries are *deliberately deferred* to the S11.7 batch wrap, so a devlog-existence check there would false-refuse every batch (architect finding 3). This mirrors wrap's existing mode-gating (Step 5 was mode-gated, not scope-gated).
- **R4.** `/wrap` retains only the docs steps (1, 2, 3, 4, 4b, 6, 6b, 7) + the post-merge docs fallback (per R2a, fallback no longer tears down); Step 5, Step 8, and the `--integration` mode are removed from it. Its References list drops the two relocated entries, and the stale `/wrap-docs` + missing-`/land` chain string at `skills/wrap/SKILL.md:419` is fixed in the same Commit-3 pass (architect finding 6).
- **R5.** `--scope=full` is **deprecated, not removed**: invoking it emits a one-time deprecation notice, runs the docs steps as `docs`, and at the end (where Step 8 used to fire) prints guidance to run `/land NNN` — it never auto-merges. The notice MUST be loud and actionable: emit the exact `/land NNN` command string AND state explicitly "this did NOT merge (it did under the old `--scope=full`)" — a non-protected-target caller previously got an atomic merge here, so the no-merge is a real behavioral regression that must not be silent (architect finding 4). `--scope=docs` (default) and `--scope=idea-only` are unchanged.
- **R6.** The canonical workflow chain is reconciled across every live surface to `/idea → /plan → /work → /review-loop (deliverables) → /wrap (docs) → /review-loop (docs) → /land (merge) → /compound`.
- **R7.** sprint-auto call sites updated: S11.13 teardown `/wrap --integration` → `/land --integration`; the stale `/wrap-docs` refs fixed to `/wrap`. sprint-auto's own S11 integration-merge logic is untouched (it never used `/wrap --scope=full`).
- **R8.** No `commands/land.md` wrapper (wrap has none; both resolve as skills). No edits to frozen `docs/archive/**` or `docs/plans/**`.

## Scope Boundaries

**In scope:**

- New `skills/land/SKILL.md` + `skills/land/references/{ATOMIC_MERGE.md,WORKTREE_TEARDOWN.md}` (relocated via `git mv`).
- `skills/wrap/SKILL.md` — strip Step 5/8/`--integration`, collapse the scope table's `full` column to the deprecation redirect, trim frontmatter, fix References list.
- Workflow-chain depictions: `README.md` (incl. the **distinct sprint-auto chain at L109** whose `teardown` token is now `/land`'s job — architect finding 1), `docs/guides/SPRINT_WORKFLOW.md` (incl. **L46** per-IDEA sprint-auto chain ending in `pre-merge container teardown`), `docs/guides/ONBOARDING.md`, `docs/ideas/README.md` (mermaid).
- Skills naming the chain or wrap-merge: `work`, `review-loop` (+`references/engine-claude.md`), `sprint-auto` (SKILL + `integration-stage`, `post-pr-sequence`, `worktree-lifecycle`, `safety-gates`, `integration-conflict-resolutions`, `escalation-policy`, `assets/auto-run-log-template`), `plan` (specifically **`references/batching-for-sprint-auto.md:129`** — the chain lives in the reference, not the SKILL — architect finding 1), `ideate`, `idea/references/IDEAS_LOCATION_STATUS.md`, `django-frontend`, and `skills/wrap/SKILL.md:419` (its own stale `wrap-docs` chain string).
- **Denominator-closing grep (run FIRST, before Commit 2):** `grep -rn "→ /wrap\|/wrap →\|wrap (docs)\|wrap (pre-merge)\|wrap-docs\|teardown\|--scope=full" skills/ docs/ README.md | grep -v archive` — pin every hit into a line-anchored edit list. The surface names above are the parents; the grep is the authoritative denominator (the Verification "every depiction identical" check is unenforceable until it's closed).
- `CHANGELOG.md` + version bump at this IDEA's own `/wrap`.

**Out of scope:**

- Behavioural change to merge or teardown mechanics — this is a relocation + rename, not a redesign of how merge/teardown work.
- sprint-auto's integration-stage merge logic (S11.x) — unchanged.
- Any `commands/` wrapper for `/land`.

**Explicit non-goals:**

- NOT renaming the docs skill — it stays `/wrap`.
- NOT removing `--scope=full` outright — it deprecates gracefully for one cycle.
- NOT editing historical archive/plan docs to rewrite their workflow chains.

## Context & Research

### Existing code and patterns to reuse

- `skills/wrap/SKILL.md:324-338` — Step 5 teardown + `--integration` mode prose (moves verbatim to `/land`).
- `skills/wrap/SKILL.md:386-390` — Step 8 atomic merge prose (moves to `/land`).
- `skills/wrap/SKILL.md:48-85` — the `--scope` detection block + per-scope step table (the `full` column collapses to the deprecation redirect).
- `skills/wrap/references/ATOMIC_MERGE.md`, `skills/wrap/references/WORKTREE_TEARDOWN.md` — relocate under `skills/land/references/`; fix inbound links.
- `skills/wrap/SKILL.md:87-115` — mode detection (pre-merge / post-merge / `--integration`); `/land` reuses the same mode-detection shape for its merge-vs-teardown branch.
- `skills/sprint-auto/SKILL.md:173`, `references/worktree-lifecycle.md:176`, `references/post-pr-sequence.md:135,212` — the `/wrap --integration` teardown call sites → `/land --integration`.

### Institutional learnings

- `rules/RULE_rename-before-drop.md` — this is a symbol-rename-then-drop refactor across many files; renames (add `/land`, rewire callers) land green before the drop (`--scope=full` behaviour + Step 5/8 prose) in its own commit, then re-verify. The "test pass" gate here is a consistency grep sweep (docs, no runtime tests).
- `rules/RULE_self-sweep-before-push.md` trigger 5 (doc-consistency) — every commit is doc-heavy; sweep frontmatter/body symmetry, chain-string consistency, and link resolution each cycle.
- `skills/idea/references/IDEAS_LOCATION_STATUS.md` — the in-progress move already performed for this IDEA.
- IDEA-013 (`docs/ideas/README.md` ✅ section) — established the two-pass chain as canonical across the headline surfaces; this plan extends that same surface set with the `/land` stage.

### External references

- None — entirely internal skill/doc refactor.

## Key Technical Decisions

- **`/land` is one skill spanning merge + teardown, mode-detected.** Pre-merge → merge (+ teardown if it unblocks); post-merge → teardown; `--integration` → batch teardown. Mirrors wrap's existing mode-detection so the mental model transfers.
- **Precondition guard replaces the idempotent docs re-run.** `/land` checks docs are finalized and refuses otherwise, rather than silently re-running wrap's steps — cleaner separation, and surfaces a forgotten `/wrap` loudly.
- **`--scope=full` deprecates via redirect, never auto-merges.** A deprecated flag silently performing a destructive merge is the wrong failure mode; notice + guidance is the graceful path (per user direction).
- **Keep the three-value `--scope` spelling.** Avoids a hard break for muscle-memory/scripts; `full` becomes the deprecation shim.
- **rename-before-drop commit sequence.** Add `/land` (additive) → rewire callers → consistency-verify → drop legacy from `/wrap` → re-verify → version/CHANGELOG.

## Open Questions

- **Q1. Does `/land NNN` pre-merge auto-proceed to teardown in the same pass, or stop after merge?**
  - **Default:** Auto-proceed (merge then teardown), mirroring wrap's current "Step 8 unblocks Step 5 in the same pass" note.
  - **Trade-off:** One-command convenience vs a brief window where a just-merged worktree is gone before the operator inspects it; `WRAP_KEEP_STACK=1`/`--keep-stack` already guards that, so default-proceed is safe.
- **Q2. `--scope=full` deprecation: notice-and-stop, or notice-and-run-docs-then-stop?**
  - **Default:** Run the docs steps (it IS a wrap), then stop with `/land` guidance — so an operator who typed the old two-pass command still gets docs finalized, just not the merge.
  - **Trade-off:** Does the useful half of the old behaviour vs a stricter "do nothing, re-run correctly" stance. Default favours not punishing muscle-memory.
- **Q3. Precondition-guard strictness — refuse vs warn-and-proceed when docs aren't finalized?**
  - **Default:** Refuse (hard block, point at `/wrap NNN`), with no override flag in v1.
  - **Trade-off:** Safety (never merge un-wrapped work) vs flexibility; refusing is reversible (run `/wrap`, re-run `/land`), so strict is the safe default.

## Execution Sequence

1. **Commit 1 — add `/land` (additive, non-breaking).** Create `skills/land/SKILL.md` (frontmatter + mode detection + **pre-merge-only** precondition guard per R3 + merge + teardown + `--integration`, References pointing at the relocated docs). `git mv skills/wrap/references/{ATOMIC_MERGE,WORKTREE_TEARDOWN}.md skills/land/references/`; in the SAME commit update `skills/wrap/SKILL.md`'s Step 5/8 inline links to the new `../../land/references/` paths so all links resolve. wrap still behaves as today (bridge state). Verify: every link in both skills resolves; `/land` reads coherently; **AND wrap still reads coherently at this HEAD** — Step 5/8 prose + References framing intact, just repointed (the RULE_rename-before-drop "intermediate commit is consistent" gate — architect finding 5).
2. **Commit 2 — rewire callers to the new chain.** FIRST run the denominator-closing grep (Scope Boundaries) and build the line-anchored edit list. Then update every chain depiction to insert `/land`: README mermaid + glyphs **+ the L109 sprint-auto chain** (replace bare `teardown` with `/land`), SPRINT_WORKFLOW stages **+ L46**, ONBOARDING, ideas/README mermaid, `skills/plan/references/batching-for-sprint-auto.md:129`. Update `skills/work/SKILL.md` hand-off, `review-loop` + `engine-claude.md`, and the sprint-auto surfaces: S11.13 `/wrap --integration` → `/land --integration`; fix `/wrap-docs` → `/wrap` in `escalation-policy.md`. Verify: `grep -rn "/wrap --integration"` returns zero in live files; every `/land` reference resolves; the chain string is identical across all headline surfaces (denominator from the grep).
3. **Commit 3 — drop legacy from `/wrap`.** Remove Step 5, Step 8, and the `--integration` mode prose; collapse the scope table's `full` column into the deprecation redirect (loud notice per R5 + run-docs + `/land` guidance); add the `--scope=full` deprecation branch to the scope-detection block; **add the post-merge-fallback "now run `/land NNN`" hand-back line (R2a)**; **rewrite the `SKILL.md:82` teardown note** (docs no longer "still tears down" — no `/wrap` mode reaches teardown); trim the frontmatter description (remove merge/teardown/scope=full sentences); fix wrap's References list (drop the two relocated entries, repoint/​drop the Step-8 sprint-auto derivation note) **and fix the stale `wrap-docs`+missing-`/land` chain string at `SKILL.md:419`**. Verify: `grep -rn "Step 8\|atomic merge\|scope=full"` in `skills/wrap/SKILL.md` only hits the deprecation shim; `grep -rn "/wrap-docs" skills/ docs/` returns zero; wrap SKILL.md line count dropped; frontmatter materially smaller.
4. **Commit 4 — consistency re-sweep + fixups.** Full grep sweep for dangling `--scope=full` (non-deprecation), orphaned links, chain-string drift across all live surfaces. Fix any stragglers.
5. **At `/wrap` of this IDEA (separate, post-review):** CHANGELOG entry + version bump (judge by adopter magnitude per the version-bump-adopter-magnitude learning — this is a workflow-surface change adopters will feel, likely a minor bump, not major).

## Verification

- `grep -rn "/wrap --integration" skills/ docs/ README.md | grep -v archive` → zero hits (all migrated to `/land`).
- `grep -rn "/wrap-docs" skills/ docs/` → zero hits (stale name fixed — incl. `skills/wrap/SKILL.md:419` and `escalation-policy.md:11,57`).
- The denominator grep (`→ /wrap|wrap (docs)|wrap (pre-merge)|teardown|--scope=full`, archive-excluded) has every hit either edited to the new chain or confirmed irrelevant — no chain depiction left on the old ordering (closes architect finding 1).
- Post-merge `/wrap NNN` fallback hand-back contains the literal "run `/land NNN`" teardown pointer (R2a); `/wrap` no longer claims to tear down anywhere (architect finding 2).
- `--scope=full` deprecation notice contains the exact `/land NNN` string and the "did NOT merge" statement (R5 / architect finding 4); confirm no live caller invokes `--scope=full` expecting a merge (`grep -rn "scope=full" skills/sprint-auto/ skills/work/` → only doc mentions, no automation dependency).
- `grep -rn "Step 8\|atomic-merge\|scope=full" skills/wrap/SKILL.md` → hits only inside the deprecation-shim paragraph.
- `ls skills/land/references/` → `ATOMIC_MERGE.md`, `WORKTREE_TEARDOWN.md`; `ls skills/wrap/references/` → those two absent.
- Every workflow-chain depiction (README ×N, SPRINT_WORKFLOW, ONBOARDING, ideas/README mermaid) shows the identical `… → /wrap (docs) → /review-loop (docs) → /land (merge) → /compound` ordering.
- `wc -l skills/wrap/SKILL.md` materially lower than 420; wrap frontmatter description materially shorter.
- Link-resolution sweep: no broken relative links in `skills/wrap/SKILL.md`, `skills/land/SKILL.md`, or the rewired sprint-auto refs.
- Architect review verdict folded (mandatory for this large, cross-cutting plan).

---

**Status:** ready — architect-reviewed 🟡 REQUIRES ABSTRACTION (6 findings, all folded: R2a post-merge handoff, R3 guard scoping, R5 loud deprecation, surface-map under-count + denominator grep, Commit-1 bridge-state check, `SKILL.md:419` + L109/L46/batching surfaces). Core split validated; R7 (sprint-auto S11 never used `--scope=full`) verified true.
