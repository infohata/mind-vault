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

**Retrigger semantics — empirically confirmed**: Copilot self-removes from `requested_reviewers` after posting each review. Bare `--add-reviewer @copilot` therefore IS the canonical retrigger for the in-loop case (Copilot has posted a review and self-removed; we re-add to request another). The earlier "bare `--add` is a no-op" observation applies only to the *still-pending* reviewer state (review never posted) — for which the commented-out `remove+add` fallback exists.

## § Clean detection

**Clean is structural** — see § Review-state gate: Copilot's check-run `STATUS=completed` (DONE) AND zero active findings matching `COPILOT_LATEST_REVIEW`. Copilot's review state is always `COMMENTED` (never `APPROVED`), so APPROVED-state matching is not applicable, and `CONCLUSION=success` means "Copilot ran", not "code is clean" — never read a verdict off it.

`find_copilot_comments.sh` may still emit a legacy `COPILOT_CLEAN_SIGNAL` line (body-text "found no new issues" match, or check-run synthesis); the orchestrator does **not** consume it for the verdict. Always count active findings explicitly.

**Anti-pattern observed during IDEA-005 dogfood (PR #131 cycle 2)**: the agent parroted the script's `COPILOT_CLEAN_SIGNAL` line as a verdict without checking active-findings count. That's exactly why clean is now structural — the finding count is the verdict.

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

## § Stale-context findings — when to bail

**Pattern**: Copilot's review prompt window includes prior review summaries / context, not just the current file state. When a fix lands that resolves a finding category at the root, Copilot may still flag the same category on an *adjacent surface* in the next cycle — arguing about the original broken-state geometry rather than the post-fix geometry. The agent's first instinct is "fix the new angle too", which triggers another cycle, and the pattern repeats.

**Detection**: the orchestrator's no-progress map (per-engine, per-category) tracks this. If `copilot.<category>` hits ≥3 attempts and copilot's next review still flags the category — even on a different file/line — the loop is in a stale-context loop, NOT making real progress.

**Hand-back rule**: when the per-engine no-progress counter for a category hits 3, **stop attempting that category**. Route the next same-category finding to Tier 3 with note `copilot reasoning from stale review-context, not current file state`. Surface in hand-back as: *"Open finding `<comment-id>` is a false positive — references state already resolved in commit `<sha>`. Resolve conversation on the PR."*

**Why this rule is per-engine**: bugbot's review prompt appears to focus on current diff state more strictly (empirically less prone to this) — the rule doesn't fire as often for bugbot. Copilot's prompt includes more historical context, hence the higher no-progress trip rate.

**Field-observed example** (PR #133, 2026-05-21):
1. Cycle 4 (rules-rationale category attempt 1): forward link `rule → rationale` broken under host-symlink layout. Fix: add `docs/rules` symlink to claude-code/cursor/opencode setup scripts.
2. Cycle 8 (attempt 2): same category re-flagged on VS Code Copilot host (different symlink layout). Fix: also symlink `docs/rules` under VS Code user dir.
3. Cycle 9 (attempt 3): same category re-flagged on the REVERSE link (rationale → rule backlinks broken in VS Code's flat instructions/ layout). Root-cut fix: drop the backlink line from all 4 rationale files.
4. Cycle 10 (attempt 4): copilot STILL flagged the category on `scripts/setup-vscode-copilot-symlinks.sh`, arguing rationale backlinks "still break VS Code Copilot" — but the backlinks had been removed in cycle 9. Pure stale-context false positive. **No-progress detector tripped; loop handed back with the finding as Tier 3.**

**The compound rule**: counter ≥3 → next same-category finding is Tier 3 regardless of whether the finding text *looks* legitimate. The pattern is the signal, not the individual finding's apparent validity. Save the cycle.

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No copilot-specific deltas at present; copilot's behavioural quirks live in § Stale-context findings and § Clean detection above.

## § Review-state gate

Copilot posts a `copilot-pull-request-reviewer` check-run on the PR head. `find_copilot_comments.sh` surfaces it as `COPILOT_CHECKRUN ... STATUS=<status>`: `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**. Corroborating signal: Copilot adds itself to `requested_reviewers` when assigned and self-removes when done (present = pending, absent = done).

`CONCLUSION` is **not** a verdict — Copilot's check-run concludes `success` even when it posted inline findings. **Clean for copilot**: check-run DONE AND zero active findings matching `COPILOT_LATEST_REVIEW`. The orchestrator retriggers only after a push or from the zero-activity bootstrap and never while a check-run is RUNNING, so there is no retrigger interval to enforce.

## § Notes on first-run calibration

The 2026-05-18 calibration run + 2026-05-20 IDEA-005 dogfood (PR #131) established the following confirmed state:
- ✅ Dual user.login identity (Copilot + copilot-pull-request-reviewer[bot]).
- ✅ Plain `--add-reviewer @copilot` retrigger after Copilot has self-removed post-review. Remove+add fallback exists for the still-pending state.
- ✅ Service-error failure mode pattern.
- ✅ Review-state gate: `copilot-pull-request-reviewer` check-run `STATUS` (RUNNING/DONE) + `requested_reviewers` self-removal. Clean is structural — DONE + zero active findings — never `CONCLUSION` (`success` ≠ "no findings") or review-body prose.

If the loop misbehaves on first use against a new Copilot deployment, inspect `gh api repos/.../pulls/<N>/reviews --jq '.[].user.login'` to confirm the bot login, and adjust constants in the tool scripts accordingly.
