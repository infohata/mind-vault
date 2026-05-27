# engine-bugbot — Cursor Bugbot adapter

Adapter specification for the Cursor Bugbot review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## § Identity

- Vendor: Cursor (`cursor.sh`).
- GitHub user logins:
  - `cursor[bot]` on `/reviews` and `/comments`.
- Phase 1's comment fetcher filters on this login.

## § Tool invocations

- `./tools/find_bugbot_comments.sh <PR_NUMBER>` — fetches reviews + inline findings from cursor[bot], emits the contract-shape stream (`BUGBOT_LATEST_REVIEW=...`, `BUGBOT_CLEAN_SIGNAL=...` if applicable, then findings, plus optional `BUGBOT_CHECKRUN=...` informational marker — surfaces the Cursor check-suite's status/conclusion on the PR head, used by the stall-detection failure mode below).
- `./tools/bugbot_retrigger.sh <PR_NUMBER>` — posts the literal comment `bugbot run` on the PR. Hard-coded body so the script can be pre-approved in `~/.claude/settings.json`. Equivalent to `gh pr comment <PR> -b "bugbot run"`.

## § Clean detection

**Clean is structural** — see § Review-state gate: check-run `DONE` AND zero active findings matching `BUGBOT_LATEST_REVIEW`. `find_bugbot_comments.sh` may still emit a legacy `BUGBOT_CLEAN_SIGNAL` (body-text "found no new issues" match, or check-run synthesis); treat it as corroboration only. For bugbot, check-run-success aligns fairly well with "no findings" (Cursor's check-suite turns neutral/non-success when bugbot finds issues) — but the active-finding count is still authoritative. Always count active findings explicitly before claiming CLEAN. The check-run synthesis is now gated by the review-pending guard (§ Race-condition caveats) so it can't fire a clean in the check-run-before-review window.

## § Staleness rule

Uses the orchestrator's default `pull_request_review_id` filter — a finding is active iff its `review <rid>` matches `BUGBOT_LATEST_REVIEW`.

**Why bugbot specifically needs this**: GitHub UI does not auto-resolve cursor[bot] inline comments when bugbot's next review verdict supersedes them — they remain visible in `/comments` until a human clicks "Resolve conversation". Without the staleness filter, the loop processes every unresolved comment as if it were active, including findings from reviews against pre-fix SHAs. Empirical evidence: PR #80's compound observed cycles 11, 14, 17, 18 all spent on findings bugbot had already cleared from current HEAD.

## § Race-condition caveats

Bugbot review latency: typically 1–10 min between trigger and review post.

The `BUGBOT_CLEAN_SIGNAL` `COMMIT` field is the **trigger-anchor** SHA, not the reviewed SHA. During the review window, a docs / wrap / no-content commit may land on the branch. The clean signal's `COMMIT` reflects trigger time; bugbot's diff scanner reads the PR's current diff vs base at review-firing time, which may already include post-trigger commits.

**Heuristic when strict `COMMIT === last_push_sha` fails**: if intervening commits since the signal's `COMMIT` are docs-only / markdown-only / comments-only, skip the re-trigger and accept the clean signal. Bugbot doesn't review prose-only diffs.

**Check-run-completes-before-review (review-pending guard).** Bugbot's check-run can flip to `completed` before its review + inline comments post, the same race that produced a false CLEAN on copilot (PR #148). Bugbot's window is narrower — Cursor's check-suite turns non-success when it finds issues, so a `completed`+`success` check-run correlates with "no findings" better than copilot's does — but the orchestrator's structural clean reads the active-finding count, not `CONCLUSION`, so the gap is still exploitable. `find_bugbot_comments.sh` therefore applies the engine-general guard ([`engine-adapter-contract.md`](engine-adapter-contract.md) § Review-state gate): a `completed`+`success` check-run is trusted as DONE only once a `cursor[bot]` review for the head SHA has posted; until then `STATUS` is downgraded to `in_progress` and a `BUGBOT_REVIEW_PENDING` marker is emitted. `BUGBOT_REVIEW_SETTLE_SECONDS` (default 600) trusts a review-less check-run after the window elapses.

**Line-number drift is NOT a new-finding signal**. GitHub line-anchored comments track code position across commits. Example from PR #55: after a fix push, bugbot's unresolved comment 3119819571 shifted from `install-gcloud-cli.sh:88` to `:97`, and comment 3119819578 from `:135` to `:144`. Title and file stayed identical; only the line moved. The `comment id` is the identity for staleness comparison.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| Bugbot stalled / hung | `BUGBOT_CHECKRUN STATUS=in_progress` for >15 min on `last_push_sha` (well past 1-10 min normal range) | Proceed with other engines' findings if any; retrigger bugbot post-push. Surface in hand-back if bugbot doesn't recover within the idle-poll budget. |
| Cursor service degraded | Bugbot reviews stop posting entirely for multiple PRs | Manual hand-back; no in-loop recovery. |
| Bugbot self-withdraws a finding | A previously-active finding's `review <rid>` is no longer LATEST | Already handled by staleness filter — finding becomes stale, dropped from active triage. |

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). Bugbot's catalogue is the empirically-validated baseline (multi-tenant Django SaaS PRs); no bugbot-specific deltas at present.

## § Review-state gate

Bugbot posts a check-run on the PR head (the `cursor[bot]` app — matched by app-slug `cursor` / name `bugbot`). `find_bugbot_comments.sh` surfaces it as `BUGBOT_CHECKRUN ... STATUS=<status>`: `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**. The orchestrator retriggers only after a push or from the zero-activity bootstrap and never while a check-run is RUNNING, so there is no retrigger interval to enforce.

**Clean for bugbot**: check-run DONE AND zero active findings matching `BUGBOT_LATEST_REVIEW`. Bugbot also posts an explicit clean review on `/reviews`; treat that as corroboration, but the active-finding count is authoritative.
