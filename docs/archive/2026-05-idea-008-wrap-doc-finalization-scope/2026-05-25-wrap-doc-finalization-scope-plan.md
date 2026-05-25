---
stage: plan
slug: wrap-doc-finalization-scope
created: 2026-05-25
source: ./IDEA-008-wrap-doc-finalization-scope.md
status: ready
project: mind-vault
---

# Separate wrap's doc-finalization phase from its merge phase — `--scope` enum, `docs` default

## Context

The wrap-before-review pattern shipped in v4.3.1 (PR #141) established a two-pass model for doc-heavy PRs: finalize docs *before* `/review-loop` (so doc-reviewing engines see docs at shipped state), then merge *after* review clears. But `/wrap` today is a single invocation whose no-arg default runs **all** steps including Step 8 (atomic merge on non-protected targets) and post-merge Step 5 (destructive teardown). On a non-protected target the pre-review pass therefore falls through toward Step 8, whose `ATOMIC_MERGE.md` gate requires a clean review signal at HEAD — which doesn't exist pre-review, so the pass blocks (`exit 1`) or aborts. v4.3.1 papered over this with an operational instruction ("run wrap, stop before Step 8") that relies on operator/agent discipline. This IDEA replaces that footgun with structure.

The user's design directive at `/plan` time sharpened the original IDEA: rather than add a `docs` mode alongside the existing `full` default, **make `docs` the default and demote merge to an explicit opt-in (`--scope=full`)** — because a no-arg `/wrap` that auto-merges and tears down is too destructive to be the default. This is a deliberate, safe-by-default reversal of the atomic-merge-as-default behaviour that the atomic-merge feature recently introduced; merge remains available, but you ask for it.

## Problem Frame

1. **Footgun on every doc-heavy PR.** With wrap-before-review now the recommended chain, every doc-heavy PR runs a pre-review wrap. On a non-protected target, bare `/wrap` heads for Step 8 and either blocks on the missing clean signal or (worse, if an operator forces past it) merges before review ran. The only thing preventing a premature merge is a human remembering to "stop before Step 8."
2. **`--scope=idea-only` is the wrong tool for the pre-review pass.** It exists for sprint-auto's parallel branches and *skips* Steps 3 (ideas-index) and 4 (devlog) — exactly the steps a pre-review pass wants finalized so reviewers see them.
3. **Destructive default.** Bare `/wrap` reaching atomic-merge + teardown means the safest-sounding invocation is the most destructive one. The default should be the safe subset.

## Requirements Trace

- **R1.** A bare `/wrap NNN` (no scope flag) finalizes docs and **structurally cannot reach Step 8 (atomic merge)** — making the wrap-before-review pass-1 a single clean invocation with no "remember to stop" instruction. Step 8 is the *sole* structural exclusion for `docs` scope; Step 5 (teardown) stays mode-gated (post-merge), so a `docs`-scope invocation on an already-merged PR (post-merge fallback) still tears down. (Architect 2a: do NOT phrase `docs` as "cannot reach Step 5" — it can, via the post-merge fallback.)
- **R2.** Atomic merge (Step 8) remains reachable, but **only under an explicit opt-in** (`/wrap --scope=full NNN`). The protected-branch HITL gate is unchanged — `full` on a protected target still hands back the PR URL.
- **R3.** The existing `--scope=idea-only` behaviour and its sprint-auto S5 contract are **unchanged** — `docs` does not replace it (see non-goals).
- **R4.** The post-review pass-2 (merge) is `/wrap --scope=full NNN`, run idempotently after `/review-loop` clears; its doc-finalization steps are no-op guards, and `ATOMIC_MERGE.md` re-clearance correctly accounts for the moved HEAD.
- **R5.** Every doc surface that currently describes "bare `/wrap` concludes atomically / merges by default" is updated to the new default, with no stale forward-reference to IDEA-008 left in `WRAP_BEFORE_REVIEW.md`.

## Scope Boundaries

**In scope:**

- `skills/wrap/SKILL.md` — scope detection (boolean → enum), per-scope step-set table, Step 5 / Step 8 gating, description frontmatter, opening "Default is pre-merge / Concludes atomically" framing, Step 8 firing conditions, interaction rules.
- `skills/wrap/references/ATOMIC_MERGE.md` — "When this fires" now also requires `scope=full`.
- `skills/wrap/references/WRAP_BEFORE_REVIEW.md` — pass-1 = bare `/wrap` (default docs, footgun gone); pass-2 = `/wrap --scope=full`; drop the "tracked as IDEA-008" forward-reference (resolved here).
- `docs/guides/SPRINT_WORKFLOW.md` — the stage-4.5 wrap row outcome (no longer "Merged PR" by default).

**Out of scope:**

- Reworking `--scope=idea-only`'s sprint-auto S5 semantics (stays as-is).
- Any change to `RULE_git-safety` or the protected-branch merge gate.
- A dedicated merge-only `--scope=merge` mode (rejected — re-running `--scope=full` idempotently is the simpler path; see Key Decisions).

**Explicit non-goals:**

- **Do NOT migrate sprint-auto S5 to `--scope=docs`.** `docs` *includes* Steps 3/4, which would re-introduce the exact N-way line-conflict on `DEVELOPMENT_LOG.md` / `ideas/README.md` that `idea-only` exists to avoid.
- **Do NOT remove atomic-merge from wrap.** It stays, behind `--scope=full`.
- **Do NOT change Step 5's post-merge timing.** Teardown stays mode-gated (post-merge only).

## Context & Research

### Existing code and patterns to reuse

- `skills/wrap/SKILL.md:45-69` — current scope-detection block sets a boolean `SCOPE_IDEA_ONLY` and enumerates the idea-only step-set. This becomes the `SCOPE` enum dispatch.
- `skills/wrap/SKILL.md:43` — the "Nine steps, several conditional" preamble; Step 5 (post-merge), Step 7 (frontmatter-gated), Step 8 (non-protected target) are already conditional. The work adds scope as a second gating axis on Steps 3/4/4b/8.
- `skills/wrap/references/ATOMIC_MERGE.md:11-34,45-59` — protected-branch detection + the `clean_sha == head_sha` re-clearance gate. The re-clearance logic already handles a moved HEAD; pass-2 needs no new mechanism, only a `scope=full` precondition.
- `skills/wrap/SKILL.md:58-67` — the `SCOPE_IDEA_ONLY=true` per-step RUN/SKIP list is the exact shape the new per-scope table generalises.

### Institutional learnings

- `skills/wrap/references/WRAP_BEFORE_REVIEW.md` — the two-pass model this IDEA makes structural. Its §"The merge doesn't move" prose currently documents the operational workaround.
- `rules/RULE_rename-before-drop.md` — the boolean→enum change renames an internal mechanism and changes a default; sequence the enum introduction + default flip as one coherent change (the boolean has a single consumer — SKILL.md itself — so the multi-caller rename ceremony doesn't apply, but the default-flip is the risky moment and gets explicit verification).
- `skills/sprint-auto/SKILL.md:123` + `references/integration-stage.md` — the S5 `--scope=idea-only` caller that must stay untouched; verifies R3.

### External references

- None. This is a self-contained prose/control-flow change to a mind-vault skill.

## Key Technical Decisions

- **`--scope` becomes a three-value enum, `docs` is the default.** Values: `docs` (default) | `full` | `idea-only`. Replaces the `SCOPE_IDEA_ONLY` boolean. Confirmed with the user; `full` is opt-in because auto-merge-by-default is too destructive.
- **Step-set per scope** (the canonical table the SKILL.md will carry):

  | Step | `docs` (default) | `full` (opt-in) | `idea-only` (sprint-auto) |
  |---|---|---|---|
  | 1 Resolve idea | RUN | RUN | RUN |
  | 2 Frontmatter flip (+ body status sub-step) | RUN | RUN | RUN |
  | 3 Re-sort ideas index | RUN | RUN | SKIP |
  | 4 Devlog entry | RUN | RUN | SKIP |
  | 4b Version-bump | conditional | conditional | SKIP |
  | 5 Worktree teardown | mode-gated (post-merge) | mode-gated (post-merge) | mode-gated (post-merge) |
  | 6 Downstream-docs scan | RUN | RUN | RUN |
  | 7 Eval-gate emission | conditional | conditional | conditional |
  | 8 Atomic merge | **SKIP** | conditional (non-protected, pre-merge) | SKIP |

- **Step 5 (teardown) stays mode-gated, orthogonal to scope.** This refines the IDEA's "docs cannot reach Step 5" framing: teardown is already post-merge-only, so in the pre-review/pre-merge context it never fires regardless of scope. Keeping Step 5 mode-gated (not scope-gated) preserves post-merge-fallback teardown: a bare `/wrap NNN` on an already-merged PR still tears down. The defining property of `docs` is therefore **skips Step 8**, not "skips Step 5."
- **Post-review pass-2 = re-run `/wrap --scope=full NNN`, not a new merge-only mode.** Doc-finalization steps are idempotent guards (Step 2 short-circuits on `status: complete`; Steps 3/4 detect existing entries; Step 6 re-greps as a fresh audit). `full` naturally reaches Step 8, whose existing `clean_sha == head_sha` gate handles the HEAD that review-loop moved. This matches the v4.3.1 `WRAP_BEFORE_REVIEW.md` pass-2 description ("re-run `/wrap` after `/review-loop` clears") — only the scope flag is now explicit. A `--scope=merge` mode was considered and rejected: it adds surface for no gain and would skip the Step 6 re-audit that catches docs drifting from review fix-commits.
- **sprint-auto S5 stays `--scope=idea-only`.** Unchanged; documented as a non-goal. `docs` would re-introduce the parallel-branch conflict.
- **`auto_safe` / `sensitive_paths_cleared` stay `false`.** This is a control-flow change to a core skill every project's release flow depends on; it warrants a human eyeball and is not a candidate for unattended sprint-auto. (Gate fields remain `false` in the IDEA frontmatter.)

## Open Questions

- **Q1. Should `--scope=full` print a one-line banner naming what it will do (merge + teardown) before Step 8 fires?**
  - **Default:** Yes — a single "scope=full: will atomic-merge non-protected target after review re-clearance" line at invocation, so the destructive opt-in is self-announcing. Cheap, and reinforces why it's not the default.
  - **Trade-off:** Marginal verbosity vs. clearer intent on the destructive path.
- **Q2. Architect-review verdict** — **🟢 ARCHITECTURALLY SOUND** (2026-05-25). Five findings, all integrated above: 2a (R1 drop "or Step 5"), 2b (Step 4b enum predicate → exec 1b), 3b (Step 3/4 idempotency guards → exec 4b), 3c/Major (ATOMIC_MERGE rationale reframe → exec 5(b)), 4 (`docs` parallel-branch callout → exec 1). No re-review required — core design (three-value enum, `docs` default, Step 5 orthogonal to scope, pass-2 idempotent re-run) confirmed sound.

## Execution Sequence

1. **`skills/wrap/SKILL.md` — scope detection (§ lines ~45-69).** Replace the `SCOPE_IDEA_ONLY` boolean parse with a `SCOPE` enum parse: `--scope=docs|full|idea-only` (default `docs`); retain `--no-batch-writes` as the `idea-only` alias. Emit the per-scope step-set table (above) in place of the single idea-only RUN/SKIP list. **Add a one-line callout to the `docs` scope description** that it runs Steps 3/4 and is therefore unsafe for parallel-branch invocations — the same constraint `idea-only` was designed to avoid (architect finding 4).
   - **1b. Step 4b predicate (SKILL.md line ~242).** Step 4b currently gates on the `SCOPE_IDEA_ONLY=false` boolean prose; update to the enum comparison (`scope != idea-only` — i.e. fires under both `docs` and `full`). Don't miss this when replacing the boolean (architect finding 2b).
2. **`skills/wrap/SKILL.md` — default-behaviour framing.** Reword the description frontmatter (line 3) and the opening "Default is pre-merge" / "Concludes atomically for non-protected targets" paragraphs: bare `/wrap` now finalizes docs and stops; atomic merge is `--scope=full`. Keep the protected-branch HITL invariant prominent.
3. **`skills/wrap/SKILL.md` — Step 8 firing conditions (§ line ~332).** Add `scope == full` to the firing predicate (currently "pre-merge mode AND non-protected target").
4. **`skills/wrap/SKILL.md` — interaction rules + sprint-auto note.** Update the "Atomic merge for non-protected targets" bullet and confirm the sprint-auto bullet still reads `--scope=idea-only`.
4b. **`skills/wrap/SKILL.md` — Step 3 + Step 4 idempotency guards (architect 3b, advisory-but-mandatory-here).** The institutionalised two-pass pattern (pass-1 `docs` + pass-2 `--scope=full`) now re-runs Steps 3/4 on every doc-heavy PR. Current Step 4 prose (lines ~207-238) only says "append"; add an existing-entry guard: before appending the devlog entry, `grep -n "IDEA-NNN\|PR #<N>" <devlog-file>` and skip if a matching entry exists. Same guard for Step 3's `### IDEA-NNN:` index heading (skip insert if the heading already sits in `## ✅ References — Implemented`). Without these, pass-2 double-writes the devlog/index on every wrapped doc-heavy PR.
5. **`skills/wrap/references/ATOMIC_MERGE.md` — precondition AND rationale (§ lines 1-9).** (a) Add the `scope=full` precondition to "When this fires". (b) **Reframe the "Why this exists" rationale (lines 7-9)** — it currently argues the old "wrap then hand back PR URL for human to click merge" default "split the shipping moment for no safety reason," which now *describes the new `docs` default* and reads as self-deprecating. Reframe: atomic-merge is available via `--scope=full`; the `docs` default is the conservative pre-review path; the two-pass model (docs → review → `full`) is the new standard, not an antipattern. The re-clearance *mechanics* (the `clean_sha == head_sha` gate) are unchanged (architect finding 3c — Major).
6. **`skills/wrap/references/WRAP_BEFORE_REVIEW.md`.** Rewrite the two-pass prose: pass-1 = bare `/wrap` (default `docs`, no "stop before Step 8" instruction); pass-2 = `/wrap --scope=full`. Delete the "tracked as IDEA-008" forward-reference (resolved). Keep the body-prose status-line sub-step guidance intact.
7. **`docs/guides/SPRINT_WORKFLOW.md` (line 36).** Adjust the stage-4.5 wrap-row outcome so it no longer implies auto-merge by default.
8. **Self-sweep + doc-consistency pass** (RULE_self-sweep-before-push trigger 5): every `--scope` mention across the four files agrees on the enum values and the default; no orphaned `SCOPE_IDEA_ONLY` references; cross-reference symmetry (SKILL ↔ ATOMIC_MERGE ↔ WRAP_BEFORE_REVIEW).
9. **Dogfood:** this IDEA's own wrap uses the new default — `/wrap 008` (docs) pre-review, then `/wrap --scope=full 008` post-review-clear (target is non-protected `idea/...` branch → exercises the opt-in merge path end-to-end).

## Verification

- **Scope parse trace.** Manually trace the enum dispatch for each of `/wrap NNN`, `/wrap --scope=full NNN`, `/wrap --scope=idea-only NNN`, `/wrap --no-batch-writes NNN` against the step-set table; confirm bare invocation resolves to `docs` and never reaches Step 8.
- **Footgun gone.** Confirm no path from a bare `/wrap` on a non-protected target reaches the `ATOMIC_MERGE.md` `exit 1` block (Step 8 is scope-skipped before the clean-signal check).
- **idea-only unchanged.** Diff the effective `idea-only` step-set before/after — must be identical (Steps 1,2,6,7-cond RUN; 3,4,4b,8 SKIP; 5 post-merge).
- **No stale references.** `grep -rn "SCOPE_IDEA_ONLY\|scope=docs\|scope=full\|scope=idea-only\|tracked as IDEA-008" skills/ docs/` returns only intended occurrences; the IDEA-008 forward-ref is gone from `WRAP_BEFORE_REVIEW.md`.
- **sprint-auto intact.** `grep -n "scope=idea-only" skills/sprint-auto/` still shows S5 on `idea-only`.
- **Idempotency.** After pass-1 then pass-2 (`--scope=full`) on a test IDEA, the devlog has exactly one entry for the PR and the ideas-index has exactly one `### IDEA-NNN:` heading — no double-writes (guards from exec 4b).
- **End-to-end dogfood:** pass-1 `/wrap 008` produces docs-only commits and stops; after review clears, `/wrap --scope=full 008` reaches Step 8 and atomic-merges the non-protected branch.

---

**Status:** ready — architect-reviewed (🟢 SOUND, findings integrated) 2026-05-25. Ready for `/work`.
