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

## § Clean-signal parsing

`find_bugbot_comments.sh` emits `BUGBOT_CLEAN_SIGNAL=<review-id> COMMIT=<sha> AT=<ts>` in two cases:

1. **Body-text match** — the latest bugbot review body contains "found no new issues".
2. **Check-run synthesis** — when no body-text match exists, the script synthesizes from a successful bugbot check-run. For bugbot specifically, check-run-success aligns more closely with "no findings" than for Copilot (Cursor's check-suite turns neutral/non-success when bugbot finds issues), but the synthesis remains a best-effort fallback.

**Phase 4 ordering supersedes synthesis errors**: the new-findings branch runs before the clean-signal branch, so any active findings (review `<rid>` == `BUGBOT_LATEST_REVIEW`) override a synthesized CLEAN. Always count active findings explicitly before claiming CLEAN.

## § Staleness rule

Uses the orchestrator's default `pull_request_review_id` filter — a finding is active iff its `review <rid>` matches `BUGBOT_LATEST_REVIEW`.

**Why bugbot specifically needs this**: GitHub UI does not auto-resolve cursor[bot] inline comments when bugbot's next review verdict supersedes them — they remain visible in `/comments` until a human clicks "Resolve conversation". Without the staleness filter, the loop processes every unresolved comment as if it were active, including findings from reviews against pre-fix SHAs. Empirical evidence: PR #80's compound observed cycles 11, 14, 17, 18 all spent on findings bugbot had already cleared from current HEAD.

## § Race-condition caveats

Bugbot review latency: typically 1–10 min between trigger and review post.

The `BUGBOT_CLEAN_SIGNAL` `COMMIT` field is the **trigger-anchor** SHA, not the reviewed SHA. During the review window, a docs / wrap / no-content commit may land on the branch. The clean signal's `COMMIT` reflects trigger time; bugbot's diff scanner reads the PR's current diff vs base at review-firing time, which may already include post-trigger commits.

**Heuristic when strict `COMMIT === last_push_sha` fails**: if intervening commits since the signal's `COMMIT` are docs-only / markdown-only / comments-only, skip the re-trigger and accept the clean signal. Bugbot doesn't review prose-only diffs.

**Line-number drift is NOT a new-finding signal**. GitHub line-anchored comments track code position across commits. Example from PR #55: after a fix push, bugbot's unresolved comment 3119819571 shifted from `install-gcloud-cli.sh:88` to `:97`, and comment 3119819578 from `:135` to `:144`. Title and file stayed identical; only the line moved. The `comment id` is the identity for staleness comparison.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| Bugbot stalled / hung | `BUGBOT_CHECKRUN status=in_progress` for >15 min on `last_push_sha` (well past 1-10 min normal range) | Proceed with other engines' findings if any; retrigger bugbot post-push. Surface in hand-back if bugbot doesn't recover within the idle-poll budget. |
| Cursor service degraded | Bugbot reviews stop posting entirely for multiple PRs | Manual hand-back; no in-loop recovery. |
| Bugbot self-withdraws a finding | A previously-active finding's `review <rid>` is no longer LATEST | Already handled by staleness filter — finding becomes stale, dropped from active triage. |

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). Bugbot's catalogue is the empirically-validated baseline (multi-tenant Django SaaS PRs); no bugbot-specific deltas at present.

## § Spacing rule

≥5 minutes between same-engine retriggers **against the same SHA** (post-push retriggers on a new SHA are exempt — see below). Field-observed degradation: 4 retriggers in 10 minutes stretched per-review latency from ~1-10 min (typical) to ~16 min as Cursor's check-suite queue worked through superseded entries.

The rule is **per-engine** — under multi-engine mode bugbot+copilot back-to-back is fine (different queues). Only same-engine retriggers **against the same SHA** within 5 min violate the spacing; a retrigger after a fresh push is exempt (SKILL.md Phase 3 § new-push exemption).
