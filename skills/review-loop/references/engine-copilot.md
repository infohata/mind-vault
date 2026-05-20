# engine-copilot — GitHub Copilot adapter

Adapter specification for the GitHub Copilot review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## § Identity

- Vendor: GitHub Copilot.
- GitHub user logins — **dual identity**:
  - `Copilot` (single-token) on `/pulls/<N>/requested_reviewers`.
  - `copilot-pull-request-reviewer[bot]` (bracketed) on `/pulls/<N>/reviews`.
- Phase 1's comment fetcher filters on BOTH logins to capture review-requests + actual review posts.

## § Tool invocations

- `./tools/find_copilot_comments.sh <PR_NUMBER>` — fetches reviews + inline findings from copilot-pull-request-reviewer[bot], emits the contract-shape stream (`COPILOT_LATEST_REVIEW=...`, `COPILOT_CLEAN_SIGNAL=...` if applicable, then findings).
- `./tools/copilot_retrigger.sh <PR_NUMBER>` — wraps the empirically-confirmed `gh pr edit <PR> --remove-reviewer @copilot && sleep 1 && gh pr edit <PR> --add-reviewer @copilot` sequence (requires `gh` ≥ 2.88). Pre-approvable in `~/.claude/settings.json`.

**Critical retrigger quirk**: bare `gh pr edit --add-reviewer @copilot` against an already-requested reviewer is a **no-op**. The GET still shows `Copilot` in `requested_reviewers` but the reviewer-processor never re-fires. The `remove+add` sequence is mandatory — bypass attempts will silently fail to trigger a new review.

## § Clean-signal parsing

`find_copilot_comments.sh` parses Copilot review bodies. The exact clean-signal phrasing is **TBD pending empirical observation** — the 2026-05-18 calibration run only observed inline findings OR service-error bodies, never a "clean" review.

When the clean phrasing is observed in the wild, update `find_copilot_comments.sh` to detect it and emit `COPILOT_CLEAN_SIGNAL=<review-id> COMMIT=<sha> AT=<ts>` accordingly. Until then, Copilot clean-signal detection falls back to "no inline findings AND no recent service-error review" — best-effort, conservative.

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

**Not yet codified.** No `AGENT_copilot.md` exists yet. As Copilot loop usage accumulates, patterns it surfaces repeatedly should be promoted into a Common Copilot Patterns block here (or in a future `AGENT_copilot.md`).

Until codified, all Copilot findings default to Tier 2 (requires explicit fix-direction approval per finding) or Tier 3 (escalate). Auto-mode + agent judgement can short-cut to Tier 2 batch-approval as a session-level decision, but no individual finding has the "matches §N codified pattern" justification yet.

## § Spacing rule

≥5 minutes between same-engine retriggers — same as bugbot. The mechanism is different (reviewer-request churn vs comment post) but the queueing behaviour is analogous. Rate-limit cost is more visible on Copilot (billed per-review on GitHub Copilot Business / Enterprise).

The rule is **per-engine** — under multi-engine mode bugbot+copilot back-to-back is fine (different queues). Only same-engine retriggers within 5 min violate the spacing.

## § Notes on first-run calibration

The 2026-05-18 calibration run partially confirmed the adapter:
- ✅ Dual user.login identity (Copilot + copilot-pull-request-reviewer[bot]).
- ✅ `remove+add` retrigger sequence required (bare `--add` is a no-op).
- ✅ Service-error failure mode pattern.
- ⏳ Clean-signal phrasing — still TBD.

If the loop misbehaves on first use against a new Copilot deployment, inspect `gh api repos/.../pulls/<N>/reviews --jq '.[].user.login'` to confirm the bot login, and adjust constants in the tool scripts accordingly.
