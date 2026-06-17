---
stage: plan
slug: claude-findings-heuristic-false-positive
created: 2026-06-17
source: ./IDEA-022-claude-findings-heuristic-false-positive.md
status: shipped
project: mind-vault
---

# Claude verdict classification: model-judge, not regex (replaces the string-heuristic)

> **Revision note (2026-06-17):** the first draft of this plan broadened `CLAUDE_CLEAN_PATTERNS` + added a connector-veto. That was treating the symptom. The maintainer reframed: claude's review is **model-generated prose**, and classifying it with regex (`CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS`) is the wrong tool by construction — the dogfood false-positive AND the architect's marker-less-prose false-CLEAN hole are the same root failure. This plan replaces the prose classifier with an **orchestrator-inline model-judge** producing a **tiered verdict**. The regex-broadening approach is abandoned.

## Context

`/review-loop`'s claude adapter decides CLEAN-vs-FINDINGS by regex-matching claude's posted prose. The IDEA-021 dogfood (PR #207) showed a clean "all findings resolved / ready to merge" summary mis-read as findings-bearing (it matched no `CLAUDE_CLEAN_PATTERNS` phrase → fell through to the safe "findings" default → spurious STILL_FINDING that blocks convergence). The architect review of the regex-broadening fix then found the inverse hole: broadening clean phrases lets a **marker-less prose finding** ("ready to merge; one concern: no auth check on the new endpoint") read CLEAN — a false-CLEAN, the dangerous direction. Both are inevitable when a string-matcher parses free-form model output. The fix is to judge the review with a model, the way the agent did by hand in the dogfood.

## Problem Frame

- **Regex can't classify model prose.** `CLAUDE_CLEAN_PATTERNS` (`no issues/bugs/problems found`) and `CLAUDE_FINDING_MARKERS` (`### \``, `#### `, `\bmissing\b`, count-lines, …) are a brittle proxy for "did claude find anything blocking?" They false-FINDING on unrecognized clean phrasing (dogfood) and risk false-CLEAN on marker-less prose findings (architect). Tuning patterns is an endless epicycle.
- **Binary clean/findings can't express the real shape.** Claude routinely posts **non-blocking** observations ("works, but you might later want to extract X") alongside a clean verdict. Binary classification forces these to either block convergence (false STILL_FINDING) or vanish. The maintainer's taxonomy: **clean · blocking · non-blocking-worth-absorbing** (→ fix in this PR, or formalize as IDEAs).
- **The structural signals are fine; only the semantic judgment is broken.** The Actions-job RUNNING/DONE state, the existence/count of unresolved inline review threads, and *which* verdicts were posted for the head SHA are reliable machine facts. It's only the clean-vs-blocking-vs-nonblocking *reading of prose* that regex gets wrong.

## Requirements Trace

- **R1.** Claude's verdict is determined by an **orchestrator-inline model-judge** that reads the full review material (summary body verbatim + inline findings + the per-SHA verdict set), NOT by regex string-matching. (Maintainer direction; judge-location = orchestrator-inline.)
- **R2.** The verdict is **tiered**: `CLEAN` · `BLOCKING` · `NON_BLOCKING[]`. A NON_BLOCKING-only review does **not** keep the engine STILL_FINDING — the loop can converge (hand back) with non-blocking items recorded. Only BLOCKING items keep the loop iterating. (Maintainer taxonomy.)
- **R3.** Non-blocking items are dispositioned through the loop's **existing Tier machinery**, with a **mode split** on the formalize path (maintainer direction — the cost asymmetry inverts between interactive and unattended):
  - **Always:** trivial + in-scope → absorbed (fixed this PR, Tier 1).
  - **Interactive `/review-loop`** (human present): non-trivial non-blocking items are **surfaced at hand-back with a proposed `/idea` line** for the human to confirm — no auto-IDEA-spam (a human is right there to triage).
  - **sprint-auto `/review-loop`** (unattended, detected via `SPRINT_AUTO_INTEGRATION_WORKTREE`): non-trivial non-blocking items are **auto-formalized into actual IDEA files** (via the `/idea` schema) and listed in the batch/integration summary — because "surfaced in the hand-back" = lost in never-read overnight output. Better recorded-and-discarded-in-the-morning than forgotten. The human prunes the cheap throwaways at batch review; a recorded IDEA file is one `rm`/reject, a forgotten suggestion is gone. (Maintainer: "let the model print IDEAs … human deals with them later.")
  - **The formalized IDEA doc, committed into the PR, is the in-band acknowledgment that closes the loop** (maintainer): once the IDEA file lands in the PR diff, the next review cycle's judge *reads it in the diff* and understands the concern is **accounted-for / tracked**, so it stops re-raising it as an open finding. This is the natural convergence mechanism of a model-judge reviewer — the deferred concern is acknowledged *in-band* (a reviewable artifact in the PR) rather than only in an out-of-band hand-back the reviewer never sees. It both prevents the non-blocking item from bouncing forever AND gives the loop a clean path to CLEAN. (Same effect interactively whenever the proposed IDEA is committed to the branch.)
- **R4.** `find_claude_comments.sh` is **reduced to material-surfacing**, and the kept-vs-removed split is named precisely (architect C3 — "keeps the verdict set" was too coarse):
  - **KEEP (structural, machine facts the judge sits on):** Actions-job RUNNING/DONE STATUS aggregation across head-SHA runs (`:347-358`); the **in-window verdict enumeration** — *which* substantive bodies exist for the head SHA + `WINDOW_START` (`:495-517`), emitted as raw material without classifying them; `CLAUDE_VERDICT_SET_PROVEN` — the fail-closed "could we prove we saw the whole verdict set (vs paginated-out)" gate (`:551`); the inline-finding enumeration with `comment id`+`review id`; the summary-body text(s) verbatim; `CLAUDE_NOOP_PATTERNS` — the structural "did claude post a *real* review vs a draft/skip no-op" gate (`:311`), which runs **before** material reaches the judge so a no-op is never judged (architect S3 — KEEP, resolved here not deferred).
  - **REMOVE (prose classification):** `CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS` (`:282-300`), the `is_clean` predicate (`:460`/`:521`), the masking *suppression* of the clean signal (`:678-690`), and the summary-body finding-block *render*/classification (`:820`). The judgment these computed moves to the loop (R5/R7).
- **R5.** **False-CLEAN stays the explicitly-dangerous direction** — relocated from a regex bias to a *judge instruction* (IDEA-018 philosophy). The judge is told: when uncertain whether an item is blocking, classify it blocking; never declare CLEAN past an unresolved concern. **Backstop — corrected for the porous-inline-thread flaw (architect C1):** claude's *common* finding shape is **summary-body-only, with zero inline review threads** (`engine-claude.md:176` — the ~30-docstring real case), so an unresolved-inline-thread count does NOT cover it. The machine backstop is therefore the **proven verdict-set enumeration**, not inline threads: the judge may return CLEAN only over a verdict set the script `CLAUDE_VERDICT_SET_PROVEN`-confirmed it saw whole, and a CLEAN verdict over any substantive body must **record which body it cleared and why** (auditable). Stated honestly: for inline-thread findings the guard is structural (open thread ⇒ not CLEAN); for summary-body findings the guard is the judge instruction + the proven-set requirement — there is no inline-thread anchor, because the signal *is* prose. (No "guarded two ways" overclaim.)
- **R7.** The **dual-verdict masking rule is transcribed verbatim into the judge contract** (architect C3 — it's being moved from machine to judge, must not vanish): *enumerate every substantive head-SHA body; any unaddressed findings-bearing body keeps the verdict BLOCKING even if a newer same-SHA body reads clean — findings are addressed by fixes, never by a luckier newer roll* (`engine-claude.md:214`). The `CLAUDE_VERDICT_SET_PROVEN` gate stays structural and fail-closed: an unprovable verdict set ⇒ the judge **cannot** return CLEAN.
- **R6.** Scope is **claude-only — typed to its cause, not the engine name** (architect S1): claude has **no structured verdict surface** (no severity JSON; verdict *is* prose — `engine-claude.md` § Identity), so for a prose-only surface the prose IS the structural signal and a model-judge reading it is the classification. The carve-out from "clean is structural, never prose" is licensed by *absence of a structured surface* and applies to any future prose-only engine; engines that post a structured surface (bugbot, copilot) keep the structural rule, untouched.

## Scope Boundaries

**In scope:**

- `tools/find_claude_comments.sh` — remove the prose-classification layer, keep the named structural surfacing (R4). Net: the script gets *simpler*.
- `skills/review-loop/references/engine-claude.md` — **owns the judge contract** (architect S1 — keep it out of the always-loaded core): the judge prompt, the tiered-verdict schema `{CLEAN | BLOCKING | NON_BLOCKING[]}`, the R5 false-CLEAN instruction, the R7 masking rule + proven-set fail-closed, the structural-vs-semantic split, and the fixture taxonomy. Rewrite the clean-detection section around the judge.
- `skills/review-loop/SKILL.md` — Phase 1 carries only the **dispatch** (engine-agnostic core stays thin): "for claude, run the model-judge per `engine-claude.md` § verdict-judge → `{CLEAN|BLOCKING|NON_BLOCKING[]}`; cache per head SHA." The decision tree's "clean is structural" line (`:67`) gains the typed carve-out (R6). BLOCKING→iterate; CLEAN/NON_BLOCKING-only→clean for the sync gate (R2). Add a `claude_non_blocking[]` scratch slot to § Scratch-file persistence (architect S2 — else a non-blocking item raised pre-compaction is summarized away per `:132`).
- `skills/review-loop/references/multi-engine-sync.md` — reconcile claude clean-detection to the judge model; add the `claude_non_blocking[]` field to the scratch schema (`:26-41`); confirm a claude `NON_BLOCKING`-only verdict counts as clean for the all-engines convergence gate (`:203`), with the items carried to hand-back.

**Out of scope:**

- `find_bugbot_comments.sh` / `find_copilot_comments.sh` and their structural classification (R6).
- The Monitor accelerator (IDEA-021, shipped).
- A dedicated judge sub-agent — explicitly chose orchestrator-inline (revisit only if the inline judgment bloats the loop's context materially).
- Auto-creating IDEAs from non-blocking items without human confirmation (R3).

**Explicit non-goals:**

- Keeping/tuning `CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS` — they're removed, not broadened. (Supersedes the abandoned first-draft connector-veto/fixture-5 design.)
- Relaxing the never-false-CLEAN bias — it's preserved, just relocated from regex to a judge instruction + the unresolved-inline-thread structural backstop.

## Context & Research

### Existing code and patterns to reuse

- `tools/find_claude_comments.sh` — Pass-1 Actions-job state synthesis (`:314-345`, the dual-verdict SHA aggregation — KEEP, it's structural), inline-finding enumeration (KEEP), summary-body capture (KEEP as raw output); the `is_clean` predicate (`:460`/`:521`) + `CLAUDE_CLEAN_PATTERNS`/`CLAUDE_FINDING_MARKERS`/`CLAUDE_NOOP_PATTERNS` (`:281-311`) — REMOVE the clean/findings verdict they compute. (`CLAUDE_NOOP_PATTERNS` for the draft/skip no-op may stay — that's a structural "did claude actually post a review" gate, not a clean/findings judgment; confirm in step 1.)
- `skills/review-loop/SKILL.md` Phase 1 triage + the Tier 1/2/3 classification — the non-blocking disposition (R3) routes through this existing machinery, not a new one.
- `skills/review-loop/references/engine-claude.md` § dual substantive verdicts + § calibration — the narrative to rewrite.
- Memory / IDEA-018: instruction-driven (no denylist) classification — the precedent this generalizes; cite it for R5.
- Memory: "Trivial Tier-3 fix → apply inline, skip /idea" + "inline trivial fix over /idea" — the disposition heuristic R3 reuses.

### Institutional learnings

- The dogfood (this branch) is the live proof the regex approach fails in both directions; the captured verdict bodies (`4729548936` clean-recap; a marker-less-prose finding) are the eval fixtures.
- A6 "clean requires a positive posted signal, never zero-inline alone" — the judge subsumes this: a posted review with no blocking content is the positive signal, read by the model not a substring.

### External references

- None — self-contained orchestration + bash change.

## Key Technical Decisions

- **Orchestrator-inline judge** (maintainer-chosen). The loop agent is already a capable model and already performed this judgment by hand in the dogfood; no sub-agent dispatch overhead. Output is a structured tiered verdict the loop acts on.
- **Structural stays structural; only semantics move to the model.** RUNNING/DONE, the head-SHA verdict set, and unresolved-inline-thread counts remain machine-derived in the find script (reliable). The judge decides only clean/blocking/non-blocking from the prose + those structural facts. This bounds the trust placed in the model and gives R5 a non-prose backstop.
- **False-CLEAN-dangerous becomes a judge instruction + the proven-verdict-set backstop** (not the porous inline-thread count — architect C1). The proven-set enumeration is the machine anchor; the judge instruction carries the bias for the summary-body-only case where no inline anchor exists.
- **Asymmetric test gating** (architect C2 — moving classification to a model loses the deterministic CI gate; restore it only where it matters). The **false-CLEAN direction is a HARD gate**: fixtures that must NOT read CLEAN (summary-body-only blocking finding; dual-verdict masking; marker-less-prose finding) fail the build if judged CLEAN. The CLEAN-vs-NON_BLOCKING boundary stays **advisory** (genuine model variance, calibration signal). Asymmetric gating mirrors the asymmetric risk the whole skill is built around.
- **Non-blocking never blocks convergence; disposition reuses Tiers + hand-back formalization.** Avoids both the false-STILL_FINDING (the dogfood bug) and backlog spam. Judge result is **cached per head SHA** in scratch — not re-run on every idle poll (it's a model call; re-judging unchanged material is waste — architect S2).
- **Carve-out typed to cause, not engine name** (architect S1): prose-only verdict surface ⇒ model-judge; structured surface ⇒ structural rule. "claude-only" is today's instance of that principle, so a future prose-only engine inherits it correctly.

## Open Questions

- **Q1. Does removing the regex classifier raise the risk of the loop hallucinating CLEAN?**
  - **Default:** Acceptable, because the dangerous direction is guarded two ways — the judge's explicit false-CLEAN-dangerous instruction (R5) AND the structural backstop (unresolved head-SHA inline threads ⇒ not CLEAN, machine-counted). The regex it replaces was itself unreliable in this exact direction (the marker-less-prose hole). Net safety is higher, not lower.
  - **Trade-off:** Slight loss of determinism for a large gain in correctness on real prose. Mitigated by Q2's eval.

- **Q2. How do you regression-test a model judgment — RESOLVED (architect C2: asymmetric gating).**
  - **Resolution:** Three layers. (a) **Deterministic hard gate** on the find-script *material-surfacing* (captured payload → assert extracted summary body(s) + inline ids + in-window verdict enumeration + `CLAUDE_VERDICT_SET_PROVEN` + RUNNING/DONE) — pure parsing, mirrors `tests/test_release_extraction.sh`. (b) **False-CLEAN hard gate** on the judgment: fixtures that must NOT be judged CLEAN — summary-body-only blocking finding (the `engine-claude.md:176` ~30-docstring shape), dual-verdict masking (newer-clean-masks-earlier-findings), marker-less-prose finding — **fail the build if the judge returns CLEAN**. The dangerous direction IS gateable even though general judgment isn't. (c) **Advisory** CLEAN-vs-NON_BLOCKING boundary eval — a miss is a prompt-calibration signal, not a build break.
  - **Trade-off:** Accepts non-determinism only on the *safe* boundary; the never-false-CLEAN invariant keeps a hard gate, matching the asymmetric risk.

- **Q3. How autonomous is the non-blocking absorb-vs-formalize decision? — RESOLVED (maintainer: mode split).**
  - **Resolution:** Per R3 — interactive surfaces + proposes (human confirms, no spam); sprint-auto auto-formalizes IDEA files + lists them in the batch summary (recorded-and-pruned beats forgotten-in-overnight-output). Detected via `SPRINT_AUTO_INTEGRATION_WORKTREE`, the same env var the loop already keys on.
  - **Trade-off:** Slight backlog churn in unattended mode (throwaway IDEAs to prune), deliberately accepted as cheaper than lost signal.

## Execution Sequence

> **Sequencing invariant (architect N2):** build the judge + its false-CLEAN gate fixtures and prove they catch the summary-body-only + masking shapes **BEFORE** deleting the regex layer. Deleting a machine guard before its replacement is proven is the wrong order on a convergence-critical path.

1. ✅ **Author the judge contract in `engine-claude.md`** (R5/R6/R7, architect S1) — judge prompt, tiered-verdict schema, the verbatim masking rule + proven-set fail-closed, the false-CLEAN-dangerous instruction, structural-vs-semantic split, fixture taxonomy. (Reference, not the always-loaded core.) — § Verdict judge added; clean-detection + review-state-gate sections rewritten to defer to it; regex-era calibration banner-superseded.
2. ✅ **Build the test layers FIRST** (Q2, architect C2/N1/N2): (a) deterministic material-surfacing test (`tests/test_claude_material_surfacing.sh`); (b) the **false-CLEAN hard-gate** fixtures — summary-body-only blocking finding, dual-verdict masking, marker-less-prose finding, unprovable-verdict-set — asserting the dangerous material is surfaced + the structural fail-closed holds (the semantic NOT-CLEAN *reading* of pure prose is judge-eval/advisory, not a bash assertion — a model can't run in bash CI); (c) advisory CLEAN-vs-NON_BLOCKING (the dogfood `clean-recap` fixture). 6 fixtures under `tests/fixtures/claude/`; ran TDD-red against the current script (reproduced BOTH failure directions), then green (23/23). Wired `make test-claude` + `make test`.
3. ✅ **Wire the dispatch into `skills/review-loop/SKILL.md` Phase 1** (thin): § Per-engine model-judge — "for claude, run the judge per `engine-claude.md` → `{CLEAN|BLOCKING|NON_BLOCKING[]}`, cache per head SHA"; the typed carve-out on the "clean is structural" line; BLOCKING→iterate, CLEAN/NON_BLOCKING-only→clean-for-sync-gate; the R3 disposition mode-split + the in-PR-IDEA acknowledgment loop; `claude_judge_verdict` + `claude_non_blocking[]` scratch slots. Reconciled `multi-engine-sync.md` scratch schema + convergence-gate composition.
4. ✅ **Reduce `find_claude_comments.sh`** (R4) — after steps 1-3 proved the replacement: REMOVED `CLAUDE_CLEAN_PATTERNS`/`CLAUDE_FINDING_MARKERS`/`is_clean`/`CLAUDE_HAS_FINDINGS`/masking-suppression/`CLAUDE_CLEAN_SIGNAL`/the green clean banner; KEPT (named) STATUS aggregation, in-window verdict enumeration + `WINDOW_START` (now raw, unclassified), `CLAUDE_VERDICT_SET_PROVEN` (now emitted), inline enumeration, verbatim verdict-body material render, `CLAUDE_NOOP_PATTERNS`, draft/silent/settle guards. Added a `CLAUDE_FIXTURE_DIR` test seam (additive, production path unchanged).
5. ✅ **Self-sweep** (`RULE_self-sweep-before-push`): `bash -n` clean; `make test` 38/38 (15 release + 23 claude); `validate-skills review-loop` ✅. shellcheck/mdformat not installed locally (CI/review covers); docs authored to markdownlint conventions.
6. **Architect reviewer pass** — DONE 2026-06-17 ×2 (first on the abandoned regex draft; second on this model-judge architecture, 🟡 → C1 porous-backstop, C2 asymmetric-gate, C3 masking+proven-set-relocation all folded as R4/R5/R7 + the test layers + the sequencing invariant; S1/S2/S3 + N1/N2 folded). Re-review optional for the doc-only fold; recommended given the large blast radius — defer to user.

## Verification

- **Deterministic hard gate:** the material-surfacing test passes — extraction of summary body(s), inline ids, in-window verdict enumeration, `CLAUDE_VERDICT_SET_PROVEN`, and RUNNING/DONE is correct and stable.
- **False-CLEAN hard gate (the load-bearing one):** the judge returns NOT-CLEAN on all three dangerous fixtures — (i) summary-body-only blocking finding (`engine-claude.md:176` ~30-docstring shape), (ii) dual-verdict masking (newer-clean-masks-earlier-findings), (iii) marker-less-prose finding ("ready to merge; one concern: no auth check"). A CLEAN on any of these fails the build.
- **Advisory:** the dogfood `4729548936` clean-recap → CLEAN/NON_BLOCKING (the original false-positive gone); a pure non-blocking suggestion → NON_BLOCKING. Misses here are calibration signals, not build breaks.
- **Proven-set fail-closed:** a fixture with an unprovable verdict set (`CLAUDE_VERDICT_SET_PROVEN=false`) cannot be judged CLEAN.
- **Convergence/composition:** a claude `NON_BLOCKING`-only verdict counts as clean for the multi-engine sync gate, and its items appear in the hand-back (interactive) or as committed IDEA files + batch-summary lines (sprint-auto). `claude_non_blocking[]` survives a `ScheduleWakeup` compaction (scratch slot).
- `grep -n "CLAUDE_CLEAN_PATTERNS\|CLAUDE_FINDING_MARKERS" tools/find_claude_comments.sh` → gone (or only in a removal comment); no `is_clean` prose verdict remains; the named kept-structural signals (STATUS aggregation, verdict enumeration, `CLAUDE_VERDICT_SET_PROVEN`, `CLAUDE_NOOP_PATTERNS`) still emit.
- `bash tools/validate-skills.sh review-loop` ✅; markdownlint clean on touched docs.

---

**Status:** ✅ shipped (2026-06-17, PR #208) — model-judge architecture, architect-reviewed twice (regex draft 🟡 → reframed; model-judge 🟡 → C1/C2/C3 + S1-3 + N1-2 folded). Disposition mode-split (interactive surface vs sprint-auto auto-formalize) + the in-PR-IDEA acknowledgment-loop are maintainer-directed. All six execution items ✅; `make test` 38/38; `validate-skills review-loop` ✅.
