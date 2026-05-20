# engine-copilot — GitHub Copilot adapter

Adapter specification for the GitHub Copilot review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## § Identity

- Vendor: GitHub Copilot.
- GitHub user logins — **dual identity**:
  - `Copilot` (single-token) on `/pulls/<N>/requested_reviewers`.
  - `copilot-pull-request-reviewer[bot]` (bracketed) on `/pulls/<N>/reviews`.
- Phase 1's comment fetcher filters on BOTH logins to capture review-requests + actual review posts.

## § Tool invocations

- `./tools/find_copilot_comments.sh <PR_NUMBER>` — fetches reviews + inline findings from BOTH Copilot logins (`Copilot` on `/pulls/<N>/requested_reviewers` and `copilot-pull-request-reviewer[bot]` on `/pulls/<N>/reviews` — see § Identity above), emits the contract-shape stream (`COPILOT_LATEST_REVIEW=...`, `COPILOT_CLEAN_SIGNAL=...` if applicable, then findings, plus optional `COPILOT_CHECKRUN=...` informational marker).
- `./tools/copilot_retrigger.sh <PR_NUMBER>` — runs `gh pr edit <PR> --add-reviewer @copilot` (requires `gh` ≥ 2.88). Pre-approvable in `~/.claude/settings.json`. A `remove+add` fallback is commented in the script body for projects where Copilot has NOT self-removed after a prior review (rare; the bare `--add` works for the typical post-review re-trigger case).

**Retrigger semantics — empirically confirmed (per [`AGENT_copilot.md`](../../../agents/AGENT_copilot.md))**: Copilot self-removes from `requested_reviewers` after posting each review. Bare `--add-reviewer @copilot` therefore IS the canonical retrigger for the in-loop case (Copilot has posted a review and self-removed; we re-add to request another). The earlier "bare `--add` is a no-op" observation applies only to the *still-pending* reviewer state (review never posted) — for which the commented-out `remove+add` fallback exists.

## § Clean-signal parsing

Per [`AGENT_copilot.md`](../../../agents/AGENT_copilot.md): **clean ≡ no new inline comments on the latest review**. Copilot's review state is always `COMMENTED` (never `APPROVED`), so APPROVED-state matching is not applicable.

`find_copilot_comments.sh` emits `COPILOT_CLEAN_SIGNAL=<review-id> COMMIT=<sha> AT=<ts>` in two cases:

1. **Body-text match** — the latest review body contains "found no new issues" (the original signal source).
2. **Check-run synthesis** — when no body-text match exists, the script synthesizes a CLEAN signal from a successful Copilot check-run. **This is a best-effort fallback that produces false positives**: Copilot's check-run `success` conclusion means "Copilot ran", not "code is clean". The check-run passes regardless of whether Copilot generated comments.

**The orchestrator's Phase 4 ordering is what makes this safe**: the new-findings branch evaluates BEFORE the clean-signal branch. Any active inline findings (those whose `review <rid>` matches `COPILOT_LATEST_REVIEW`) override a synthesized CLEAN signal — the loop re-triages instead of handing back. If Phase 4 reaches the clean-signal branch with synthesized CLEAN AND zero active findings, it's safe to treat as CLEAN.

**Anti-pattern observed during IDEA-005 dogfood (PR #131 cycle 2)**: the agent parroted the script's `COPILOT_CLEAN_SIGNAL` line as a verdict without checking active-findings count. The script's CLEAN line is **input**, not **output** — Phase 4 collapses it with the findings count. Always count active findings explicitly before claiming CLEAN.

## § Staleness rule

Uses the orchestrator's default `pull_request_review_id` filter — a finding is active iff its `review <rid>` matches `COPILOT_LATEST_REVIEW`.

Copilot's GitHub UI behaviour matches bugbot's: persistent threads linger until manually resolved. The default filter handles this correctly.

## § Race-condition caveats

Copilot review latency: ~30 seconds between trigger and review post — much faster than bugbot's 1-10 min. The race window is correspondingly narrower but still real (the timestamp tiebreaker in the orchestrator still applies).

**Heuristic when strict `COMMIT === last_push_sha` fails**: same as bugbot — if intervening commits since signal's `COMMIT` are docs-only, accept the clean signal. Empirically calibrate whether Copilot reviews prose-only diffs (initial assumption: no).

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| Copilot service error | Review `state: COMMENTED` with body literally `"Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."` and zero inline comments | First occurrence: count toward consecutive-error tally. |
| Copilot service-errored 2× consecutive | Two consecutive HEAD SHAs produce service-error reviews | Stop retriggering Copilot this cycle (additional remove+add compounds the failure). Proceed with other engines' findings if any. |
| Copilot service-errored 3× consecutive | Third consecutive error | Durable service issue. Hand back to user with the offending review ids + SHAs so they can retry from UI, wait for recovery, or merge without Copilot's verdict. |
| Copilot stalled (no review at all) | Review never posts within ~10× normal latency (~5 min) on `last_push_sha` | Proceed with other engines; surface in hand-back if Copilot doesn't recover within the idle-poll budget. |

## § Common patterns (codified Tier 1)

Defer to [`agents/AGENT_copilot.md`](../../../agents/AGENT_copilot.md) § Common Review Findings for the codified Tier 1 catalogue. Triage rule: if a finding matches one of those patterns AND touches ≤1 file AND has an existing targeted test, classify Tier 1 (auto-fix without per-finding approval prompt).

## § Spacing rule

≥5 minutes between same-engine retriggers — same as bugbot. The mechanism is different (reviewer-request churn vs comment post) but the queueing behaviour is analogous. Rate-limit cost is more visible on Copilot (billed per-review on GitHub Copilot Business / Enterprise).

The rule is **per-engine** — under multi-engine mode bugbot+copilot back-to-back is fine (different queues). Only same-engine retriggers within 5 min violate the spacing.

## § Notes on first-run calibration

The 2026-05-18 calibration run + 2026-05-20 IDEA-005 dogfood (PR #131) established the following confirmed state:
- ✅ Dual user.login identity (Copilot + copilot-pull-request-reviewer[bot]).
- ✅ Plain `--add-reviewer @copilot` retrigger after Copilot has self-removed post-review. Remove+add fallback exists for the still-pending state.
- ✅ Service-error failure mode pattern.
- ✅ Clean-signal detection: body-text match on "found no new issues" + check-run synthesis fallback. The synthesis is known to false-positive (Copilot's check-run `success` ≠ "no findings"); Phase 4's new-findings-precedes-CLEAN ordering correctly supersedes false synthesized signals.

If the loop misbehaves on first use against a new Copilot deployment, inspect `gh api repos/.../pulls/<N>/reviews --jq '.[].user.login'` to confirm the bot login, and adjust constants in the tool scripts accordingly.
