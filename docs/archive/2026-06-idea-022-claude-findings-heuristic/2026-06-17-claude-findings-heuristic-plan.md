---
stage: plan
slug: claude-findings-heuristic-false-positive
created: 2026-06-17
source: ./IDEA-022-claude-findings-heuristic-false-positive.md
status: ready
project: mind-vault
---

# Claude adapter HAS_FINDINGS false-positive on resolved-recap summaries

## Context

The IDEA-021 dogfood (PR #207) surfaced that `tools/find_claude_comments.sh` classifies a **clean** claude summary as findings-bearing when that summary is a *"previous findings — all resolved / ready to merge"* recap. The adapter raised a spurious dual-verdict-masking **STILL_FINDING**; the loop only stayed correct because the agent adversarially read the full verdict and overrode. Left unfixed, this blocks `/review-loop` from ever declaring CLEAN on any multi-cycle claude review — exactly the iterate-to-clean workflow the claude engine exists for.

## Problem Frame

The adapter's clean test is **`clean ⇔ a positive clean-phrase (CLAUDE_CLEAN_PATTERNS) AND zero finding-markers (CLAUDE_FINDING_MARKERS)`**; a posted summary that is **not provably clean** defaults to *findings* (the deliberately-safe direction — never false-CLEAN). Two over-flag sources:

1. **`CLAUDE_CLEAN_PATTERNS` is too narrow** — `no issues found|no bugs found|no problems found|no security issues`. The dogfood's clean verdict (summary `4729548936`) used *"The PR is clean", "no new issues", "no open issues", "ready to merge", "all findings … resolved"* — **none** match, so it failed the positive-clean-phrase test → defaulted to findings.
2. **`CLAUDE_FINDING_MARKERS` may false-trip on resolved-recap structure** — markers include `### \``, `#### `, `\bmissing\b`, `\bviolation\b`, `❌`, count-lines. A *"### Previous findings — all resolved ✅"* recap, or prose like "no docstrings missing", could match a marker even though nothing is open.

The invariant that must NOT break: **false-CLEAN is the dangerous direction** (a missed real finding). The current `clean-phrase AND zero-markers` gate is what prevents a mixed body ("Bugs: clean, but Security: SQLi found") from reading clean. Any broadening of clean phrases is only safe *because* the zero-markers conjunct still has to hold.

## Requirements Trace

- **R1.** A clean claude verdict using the common alternative phrasings claude actually emits ("the PR is clean", "no new/open issues", "ready to merge", "all findings resolved", "LGTM"-class) is classified **CLEAN** — no spurious STILL_FINDING. (IDEA body; dogfood F-dogfood-5.)
- **R2.** The never-false-CLEAN invariant holds: a mixed or genuinely-findings-bearing body still reads **findings**. The `positive-clean-phrase AND zero-finding-markers` conjunction is preserved (broadening touches the clean-phrase arm only, never relaxes the markers arm). (IDEA non-goal: don't weaken detection.)
- **R6 (the architect's critical catch — the false-CLEAN vector broadening introduces).** Broadening the clean-phrase arm **removes the accidental safety margin** the narrow patterns provided: under the old narrow set, a marker-less genuine finding that happened to contain a clean-ish phrase ("ready to merge once X is fixed", "clean apart from the SQLi on line 40") still fell through to the safe `findings` default because the narrow phrase didn't match. After broadening, that body matches a clean phrase, emits no structural marker, and would **false-CLEAN**. The catch-everything calibration (`find_claude_comments.sh:461-468`) explicitly documents that markers are non-deterministic — so "every real finding emits a marker" is NOT a guarantee. Mitigation: the clean-phrase match must be **suppressed when an adversative/open-concern connector co-occurs** (`apart from` / `except` / `but` / `one concern` / `once … is fixed` / `aside from`), so a "clean-but-X" body never reads clean. This guard is itself locked by fixture 5 (R5).
- **R3.** A resolved-recap structure (checked-off "previous findings — all resolved", ✅ lists) does not by itself trip `CLAUDE_FINDING_MARKERS`. If it does today, refine the markers to exclude resolved-recap shape without losing genuine finding-marker coverage.
- **R4.** Dual-substantive-verdict detection (two same-SHA verdicts that genuinely disagree, one carrying a real open finding → STILL_FINDING) is preserved **and tested through the Pass-2b `CLAUDE_HAS_FINDINGS` aggregation path** — NOT only the single-verdict `CLAUDE_SUMMARY_LINE`. The dual-verdict union is **not** an independent safety net: Pass-2b (`:521`) and the classify pass (`:460`) share the same `is_clean` predicate, so the union inherits the same false-CLEAN exposure. R4 holds end-to-end only once R6's guard is proven at the aggregation layer too. (IDEA non-goal + architect must-fix #2.)
- **R5.** Behaviour is locked by a **five**-fixture suite (architect must-fix #1 — three is insufficient; the original three all carry markers in their dirty cases so none can catch a marker-less-prose regression):
  1. clean-recap (captured artifact `4729548936`) → CLEAN
  2. genuine-finding *with* a structural marker → FINDINGS
  3. mixed (clean section + marker'd dirty section) → FINDINGS
  4. resolved-recap **+ new open finding WITH a marker** → FINDINGS (dual-verdict-shaped; run through Pass-2b)
  5. resolved-recap **+ new open finding as marker-less PROSE** → FINDINGS (the R6 invariant guard; run through Pass-2b). If fixture 5 cannot pass without over-narrowing the allowlist, that *is* the finding that gates allowlist width — constrain via the R6 adversative-connector guard.

## Scope Boundaries

**In scope:**

- `tools/find_claude_comments.sh` — `CLAUDE_CLEAN_PATTERNS` (broaden, justified per phrase), `CLAUDE_FINDING_MARKERS` (refine only if R3 testing shows a false-trip), and the classify pass if the gate logic itself needs adjusting.
- A **test fixture + harness** for the claude clean/findings classifier (captured bodies in, expected verdict out) — co-located per the repo's `tests/` convention (cf. `tests/test_release_extraction.sh`).
- `skills/review-loop/references/engine-claude.md` — calibration-notes update documenting the broadened clean set + the dogfood provenance.

**Out of scope:**

- The Monitor accelerator and any IDEA-021 surface (already shipped).
- Other engine adapters (`find_bugbot_comments.sh`, `find_copilot_comments.sh`).
- The engine-adapter contract / orchestrator SKILL.md decision tree — this is a claude-adapter parse-layer fix only.
- Re-architecting claude clean-detection away from posted-signal (the A6 "clean requires a positive posted signal, never zero-inline alone" calibration stays — see Decisions).

**Explicit non-goals:**

- Trusting zero-inline-comments alone as clean (reintroduces the A6 false-clean vector).
- Loosening clean detection to a degree that a mixed review reads clean (R2).

## Context & Research

### Existing code and patterns to reuse

- `tools/find_claude_comments.sh:281-300` — `CLAUDE_CLEAN_SUBSTRING` / `CLAUDE_CLEAN_PATTERNS` / `CLAUDE_FINDING_MARKERS` definitions + the extensive in-file calibration comments (lines ~242-299) documenting why each pattern exists and the false-clean-is-dangerous bias. The fix edits these constants; the rationale comments must be updated in lockstep.
- `tools/find_claude_comments.sh` classify pass + Pass-1 dual-verdict aggregation (lines ~314-345) — the `HEAD_VERDICTS` / `HAS_FINDINGS` synthesis to leave untouched in behaviour (R4).
- `skills/review-loop/references/engine-claude.md` § dual substantive verdicts + § calibration — the authoritative narrative; update alongside.
- `tests/test_release_extraction.sh` — the repo's bash test-harness shape to mirror for the new classifier fixture test.

### Institutional learnings

- The in-file calibration history (PR #167 / #169 dogfoods) already encodes the "catch-everything, false-clean is the one direction we must never fail" principle — this fix must stay inside that principle (broaden clean only under the zero-markers guard).
- mind-vault memory: *retroactive audit over-flags → always adversarially refute*. The same over-flag bias is what this fixes at the adapter level so the human/agent override isn't load-bearing.

### External references

- None — self-contained bash/python parsing change; the captured GitHub comment bodies are the spec.

## Key Technical Decisions

- **Broaden the clean-phrase arm with a curated allowlist, not a loose regex.** Add the specific clean phrasings claude has been observed to emit (curated, each justified in-comment) rather than a permissive catch-all — keeps the false-clean surface minimal. Rationale: a loose "clean|resolved|merge" regex would match mixed-review prose.
- **Guard the broadened clean match with an adversative-connector veto (R6).** A clean phrase co-occurring with `apart from` / `except` / `but` / `one concern` / `once … is fixed` / `aside from` does **not** read clean — this is what replaces the accidental safety margin the narrow patterns gave for free. The architect's must-fix: the "broaden clean-phrase only ⇒ no false-CLEAN" claim is **only** true with this veto, because the file's own calibration says a genuine finding may emit no structural marker. The veto + fixture 5 convert the claim from asserted to tested.
- **Keep the `clean-phrase AND zero-finding-markers` conjunction.** The markers arm stays the primary safety net; touch it only to *remove* a confirmed resolved-recap false-trip (R3), never to weaken genuine coverage. The R6 connector-veto is a *second* guard layered on the clean-phrase arm, not a relaxation of the markers arm.
- **One `is_clean` predicate, two call sites — assert both.** The predicate is duplicated inline at `find_claude_comments.sh:460` (classify pass) and `:521` (Pass-2b aggregation), sharing the env constants but not the code. The broadening reaches both via the shared constants, but the fixture suite must assert **both** layers so a future edit can't desync the surface verdict from the dual-verdict masking math (architect should-fix #3). Consider extracting the predicate to a single helper if cheap; at minimum, test both.
- **Keep A6 (clean requires a positive posted signal).** Don't pivot to "zero inline = clean." The fix makes the *positive-signal* recogniser broader/smarter, not absent.
- **Fixtures are the regression contract.** Lock the captured clean-recap, a genuine-finding body, and a mixed body so a future calibration edit can't silently re-introduce either failure direction.

## Open Questions

- **Q1. Which gate actually fired on `4729548936` — the clean-phrase miss, a finding-marker false-trip, or both?**
  - **Default:** Determine empirically as execution step 1 (run the captured body through the current `CLAUDE_CLEAN_PATTERNS` + `CLAUDE_FINDING_MARKERS`). Hypothesis: clean-phrase miss is primary; marker refinement only if a false-trip is confirmed.
  - **Trade-off:** Front-loading the empirical check avoids speculatively editing the markers (regression risk) when only the clean patterns need broadening.

- **Q2. How wide should the clean allowlist be?**
  - **Default:** Seed from observed phrasings ("the PR is clean", "no new issues", "no open issues", "no issues remain", "ready to merge", "all findings … resolved"); add only phrases seen in real claude output, each with an inline justification.
  - **Trade-off:** Narrower = more false-FINDINGs (annoying, safe); wider = creeps toward false-CLEAN (dangerous). The zero-markers guard mitigates, but keep the allowlist evidence-based.

## Execution Sequence

1. **Reproduce + localise (Q1).** Fetch the captured clean-recap body (`gh api .../comments` for summary `4729548936`, or save a fixture from PR #207) and run it through the current `CLAUDE_CLEAN_PATTERNS` and `CLAUDE_FINDING_MARKERS`. Record which gate failed. Capture/synthesize the other four fixtures (R5) — genuine-finding-with-marker, mixed, resolved-recap+marker'd-finding, **resolved-recap+marker-less-prose-finding**.
2. **Author the five-fixture harness FIRST** (R5; test-first so the safety guard is proven, not assumed) — `tests/test_claude_findings_classifier.sh`, mirroring `tests/test_release_extraction.sh`. Each fixture asserts the classifier verdict at **both** layers: the single-verdict classify path (`CLAUDE_SUMMARY_LINE`) **and** the Pass-2b aggregation path (`CLAUDE_HAS_FINDINGS`) — fixtures 4 + 5 specifically through Pass-2b (R4, architect must-fix #2). Fixtures 1-3 will pass on broadening; 4-5 are expected to fail until step 4's guard lands.
3. **Broaden `CLAUDE_CLEAN_PATTERNS`** (R1) with the curated allowlist (Q2), updating the adjacent calibration comment to list the new phrasings + cite the IDEA-021 dogfood provenance. Fixtures 1-3 now green; fixture 5 will go RED (the regression the broadening introduces) — that's the point.
4. **Add the R6 adversative-connector veto** so a "clean-but-X" body does not read clean — fixture 5 must go green **without** narrowing the allowlist back to uselessness. If the veto can't make fixture 5 pass while keeping fixture 1 green, narrow the allowlist (the width is gated by the fixtures, per R5).
5. **Refine `CLAUDE_FINDING_MARKERS` only if step 1 confirmed a resolved-recap false-trip** (R3) — exclude the recap shape (e.g. don't let a `### …resolved` / ✅-list header count as a finding marker) without dropping genuine markers.
6. **Update `engine-claude.md` — named edits** (architect should-fix #4): **line ~178** (§ findings live in SUMMARY BODY) inline-enumerates the OLD narrow clean family (`no issues/bugs/problems found`) — update it to the broadened set + the connector-veto, or it becomes a lie; **lines ~208-217** (§ dual substantive verdicts / masking rule) — add the note that the clean set was widened and the never-false-CLEAN invariant was re-validated against the marker-less-prose case (fixture 5); **cross-reference line ~197** (clean summary ≠ zero inline findings) so the widened summary-detection isn't misread as "claude is now a sole clean gate" (nice-to-have #5).
7. **Self-sweep** (`RULE_self-sweep-before-push`): shellcheck/pyflakes on the touched script, markdownlint on docs.
8. **Architect reviewer pass** — DONE 2026-06-17 (🟡 REQUIRES ABSTRACTION → must-fix #1 + #2 folded as R6/R4/fixtures 4-5; should-fix #3 + #4 + nice-to-have #5 folded). Re-review not required for the doc-only fold.

## Verification

- **All five fixtures pass at BOTH layers** (single-verdict `CLAUDE_SUMMARY_LINE` + Pass-2b `CLAUDE_HAS_FINDINGS`): 1→CLEAN, 2/3/4/5→FINDINGS. Fixture 5 (resolved-recap + marker-less-prose finding → FINDINGS via Pass-2b) is the load-bearing gate — it proves the broadening did not open a false-CLEAN.
- `./tools/find_claude_comments.sh` re-run against PR #207's head (or the saved fixture) now reports claude **CLEAN** (no dual-verdict-masking STILL_FINDING) — the original false-positive is gone. (Corroboration only; the fixtures are the authority — Decision 4.)
- The `CLAUDE_FINDING_MARKERS` arm is unchanged OR narrowed-only for recap-shape (never broadened); the only *broadening* is on the clean-phrase arm, gated by the R6 connector-veto.
- `engine-claude.md` lines ~178 + ~208-217 updated (no stale narrow-clean-family enumeration left); `bash tools/validate-skills.sh review-loop` ✅; markdownlint clean on touched docs.

---

**Status:** ready — architect-reviewed 2026-06-17 (🟡 REQUIRES ABSTRACTION → must-fix #1 false-CLEAN fixture + #2 Pass-2b assertion folded as R6/R4/fixtures 4-5; should-fix #3 dual-predicate + #4 named engine-claude.md edits + nice-to-have #5 folded). Awaiting user approval before `/work`.
