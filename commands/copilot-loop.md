---
description: Semi-autonomous GitHub Copilot code-review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /copilot-loop

Drive a GitHub Copilot review-fix-rerun cycle on the current PR (or specified PR number) under the bounded-autonomy policy defined in `agents/AGENT_copilot.md`.

> **Engine sibling.** This is the GitHub-Copilot-engine fork of [`/bugbot-loop`](bugbot-loop.md) (Cursor Bugbot). The phase structure, dual-signal enumeration, staleness rules, and hard bounds are identical — only the bot user.login, trigger mechanism, and clean-signal phrase differ. For Cursor Bugbot, use `/bugbot-loop` instead.
>
> **First-run calibration — partially confirmed (2026-05-18 empirical run, PR #456 of a downstream project).**
> - Bot user.login: `Copilot` (single-token, no brackets) confirmed on `/pulls/<N>/requested_reviewers`; the bracketed form `copilot-pull-request-reviewer[bot]` confirmed on `/pulls/<N>/reviews`. Always filter on the **dual identity** as documented in Phase 1.
> - Retrigger: ✅ `remove+add IS required`. The bare `gh pr edit --add-reviewer @copilot` against an already-requested-or-completed reviewer is a no-op (the PR's GET shows `Copilot` still in `requested_reviewers` but Copilot's reviewer-processor never re-fires). The empirically-confirmed pattern is `gh pr edit --remove-reviewer @copilot && sleep 1 && gh pr edit --add-reviewer @copilot`. Ship `tools/copilot_retrigger.sh` (when first authored) with remove+add as the default.
> - Clean-signal phrasing: ⏳ still empirically TBD. The PR #456 run never observed Copilot post a "no issues found" review body — Copilot either posted reviews with inline findings OR posted reviews with the service-error body documented in § Failure modes below. The clean-signal phrasing remains a calibration gap until a Copilot-cleared review is observed in the wild.
>
> If the loop misbehaves on the first run, inspect `gh api repos/.../pulls/<N>/reviews --jq '.[].user.login'` to confirm the bot login, and adjust the constants in `tools/find_copilot_comments.sh` + `tools/copilot_retrigger.sh` accordingly.

> **Failure modes (2026-05-18 empirical observations).**
> - **Service-error review** — Copilot can post a review with `state: COMMENTED`, body literally equal to `"Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."`, and zero inline comments. Three consecutive errors on three consecutive HEAD SHAs against the same PR = durable service issue, not transient. The loop should detect this pattern (2 or 3 consecutive errored reviews from the same PR) and **hand back to the user** — additional remove+add retriggers compound the failure rather than resolving it. The hand-back report should call out the service-error reviews by id + SHA so the user can decide whether to retry from GitHub UI, wait for Copilot service to recover, or proceed without Copilot's verdict.
> - **Hung-CHECKRUN pattern (sibling-engine specific)** — when running Copilot in combined-with-bugbot mode (§ Dual-engine sync rule below), bugbot's CHECKRUN can stall in `STATUS=in_progress` for >15 min on a SHA. Different failure mode from Copilot's service-error; treat similarly per the dual-engine trade-off rule.

**Inputs**: optional PR number. Default: PR for current branch.

## Hard bounds (enforced by the loop)

- `max_commits_per_session = 20`
- `max_active_work_minutes = 180` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20` (consecutive wakes with no new Copilot comment AND no new push)
- Targeted tests only inside the loop; broader regression deferred to hand-back
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per Copilot review cycle into one commit, not one-per-finding
- **Commits**: standard `RULE_git-safety` applies — feature branches are the agent's sandbox, so the loop commits and pushes Tier 1 fixes autonomously. Tier 2 still needs explicit per-finding *fix-direction* approval (that is a content decision, not a commit approval). Protected-branch guardrails remain in force: never main, never merge into a protected branch, never force-push to protected, never `--no-verify`.

## Dual-engine sync rule (combined with `/bugbot-loop`)

When the user invokes both `/copilot-loop` AND `/bugbot-loop` on the same PR (the user's reasonable instinct — "two reviewers catch more than one"), the loops MUST sync each cycle to avoid double-pushes that invalidate each other's pending reviews. Each cycle waits for **the slowest engine** to either (a) post findings against `last_push_sha` OR (b) post a clean signal for `last_push_sha`, then BATCHES findings from both into ONE fix commit + pushes once + retriggers BOTH engines.

The rationale: each push invalidates pending reviews of the prior SHA. If copilot-loop commits a fix and pushes while bugbot-loop is still scanning the prior SHA, bugbot's pending review becomes stale (against a now-obsolete diff) and the engine has to re-scan from scratch. Compounding waste: bugbot scans SHA-A, copilot commits a fix → SHA-B, bugbot's review of SHA-A lands but is stale, bugbot now has to scan SHA-B from scratch. With sync, both engines scan SHA-A at once and the fix commit folds in both findings; bugbot's next scan is against SHA-B which actually has the fixes both bots wanted.

**Default cadence with sync**: each engine takes its own time on its review; the loop's idle-poll interval (270s cache-warm) is unchanged. Sync just defers Phase 3 commit-and-push until both engines' verdicts on `last_push_sha` are in hand.

**Trade-off escape hatch — proceed with one engine when the other stalls.** Hard "wait for slowest" risks blocking the loop indefinitely if one engine hangs. Trip-triggers for proceeding with the responsive engine:

| Trip | Trigger condition | Action |
|---|---|---|
| Bugbot stalled | `BUGBOT_CHECKRUN` status `in_progress` for >15 min on `last_push_sha` (well past the documented 1-10 min range) | Proceed with Copilot's findings if any; retrigger bugbot post-push. |
| Copilot service-errored 2× consecutive | See § Failure modes above — Copilot review body literally `"Copilot encountered an error..."` on two consecutive HEAD SHAs against the same PR | Proceed with bugbot's findings if any; do NOT retry Copilot in this cycle (compounds the failure). |
| Copilot service-errored 3× consecutive | Third consecutive service error | Hand back to user — loop can't resolve a durable Copilot service issue. |
| Bugbot returns CLEAN but Copilot still hung | `BUGBOT_CLEAN_SIGNAL` for `last_push_sha` + Copilot still queued/in-flight past idle-poll threshold | Wait for Copilot up to `max_idle_polls` × 270s; if still no Copilot verdict, hand back with bugbot's CLEAN status documented in the report. |

**Sync state — extra scratch-file fields when running in dual-engine mode.** Per-engine state needs separate keys so a stall in one engine doesn't desync the other's poll counters:

```yaml
last_seen_bugbot_review:  <id> @ <sha> CLEAN=<bool>
last_seen_copilot_review: <id> @ <sha> CLEAN=<bool>
last_seen_bugbot_comment_id:  <id>
last_seen_copilot_comment_id: <id>
no_progress_map:  # per-engine, per-finding-category
  bugbot:  { <category>: <count> }
  copilot: { <category>: <count> }
```

The per-engine `no_progress_map` keeps the no-progress detector accurate when bugbot and copilot independently raise different findings in the same category (different code paths, different fixes).

**Retrigger discipline — different per engine.** When Phase 3 fires after the dual-engine batch commit:
- Bugbot: post a `bugbot run` comment via `tools/bugbot_retrigger.sh <PR>`.
- Copilot: `remove+add` (per § First-run calibration above). Re-add alone is a no-op.

Both retriggers happen post-push, in that order. The bugbot comment is cheap; the copilot remove+add is the one that's been observed to be load-bearing.

**Hand-back when only one engine cleared.** A non-trivial fraction of PR runs end with one engine CLEAN and the other in a degraded state (service error, infrastructure hang, billing-rate-limit pause). The hand-back report MUST distinguish:
- `bugbot: CLEAN at <sha>` AND `copilot: errored / hung / unavailable` — the PR has ONE engine's verdict. Surface this prominently. User decides whether to merge on bugbot's verdict alone, retry copilot from GitHub UI, or proceed without copilot's verdict.
- Mirror for `copilot: CLEAN` AND `bugbot: hung`.
- `both: CLEAN at <sha>` — merge-ready.
- `both: still finding things` — loop continues.

## Phase 0: Worktree environment bootstrap

**Sprint-auto v3.1 mode (new) — short-circuit**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is set in the environment, **skip Phase 0 entirely**. Per-IDEA worktrees under sprint-auto v3.1 are pure code surfaces — no `.env`, no docker compose stack. copilot-loop's role in this mode narrows to (a) reading Copilot's findings via the GitHub API and (b) committing fixes to the per-IDEA branch. Neither activity needs a runtime in the per-IDEA worktree. When fix-verification runs in Phase 2 / Phase 3, it routes to the integration worktree (see Phase 2 § "v3.1 fix-verification routing"). See [`skills/sprint-auto/references/integration-stage.md`](../skills/sprint-auto/references/integration-stage.md) for the full env-var contract.

**Standalone mode (default)**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset, fall through to the existing worktree-bootstrap logic below.

If `git rev-parse --git-common-dir` differs from `.git` (i.e. running inside a worktree):

1. If `.env` already exists → skip to step 3 (containers only).
2. Else (`.env` missing):
   - If `.env.template` exists:
     - Copy template → `.env`.
     - Replace any `*_API_KEY=` / `*_TOKEN=` / `*_SECRET=` values with `test-not-a-real-key`.
     - Replace `SECRET_KEY=` with `test-$(openssl rand -hex 16)`.
     - Scope DB/Redis URLs to the worktree's docker compose project namespace.
   - If `.env.template` missing → escalate to user; do not proceed.
3. Spin up containers: `docker compose up -d`.
4. In primary working tree: skip this phase entirely.

This is the **only** authorised place to create `.env` — see exception clause in global `CLAUDE.md`.

## Phase 1: Triage

1. **Fetch Copilot state** for the PR:

   - Comments: `./tools/find_copilot_comments.sh [PR_NUMBER]` (preferred — includes the `COPILOT_CLEAN_SIGNAL` marker), or equivalent `gh api repos/.../pulls/<N>/comments` + `.../issues/<N>/comments` + `.../pulls/<N>/reviews`, filtering on the **dual identity** Copilot exposes across endpoints: `user.login in ('Copilot', 'copilot-pull-request-reviewer[bot]')`. The `Copilot` login appears on `/pulls/<N>/comments` and `/pulls/<N>/requested_reviewers`; the bracketed `copilot-pull-request-reviewer[bot]` form appears on `/pulls/<N>/reviews`. Filtering by just `"Copilot"` will silently miss every review entry and the script's `COPILOT_CLEAN_SIGNAL` will never fire through the fallback path.
   - Parse unresolved review comments on code lines (findings) separately from reviews (clean-signal source).
   - **Dual-signal enumeration — mandatory output shape every cycle.** Always present both signals explicitly in your cycle summary, even when one of them is absent. The two GitHub resources (`/reviews` for the Copilot review-body clean flag, `/comments` for inline line-anchored findings) are **independent and can coexist for the same commit** — Copilot may post an overall "found no new issues" review AND one or more inline LOW-severity style/structure hints on the same push. Inline comments from prior reviews also persist in `/comments` until a reviewer manually clicks "Resolve conversation" on GitHub, so a stale-by-fix finding can linger alongside a fresh clean signal. Required shape:

     ```
     - /reviews  : ✅ CLEAN signal <review-id> @ <sha> OR ❌ no signal for current head
     - /comments : <N> inline finding(s) [list them if > 0, with ids + L# ranges]
     ```

     Then apply Phase 4's decision tree to resolve these two enumerations into an action. **Never collapse the two signals into a single "is the PR clean?" conclusion at Phase 1 output time.** The Phase 4 decision tree will handle the collapse correctly (new-findings branch precedes clean-signal branch), but only if Phase 1's output surfaces both resources independently. Context-rot during `ScheduleWakeup` sleeps tends to re-merge the two signals into one; the explicit dual presentation is what survives compaction.

     Staleness rule — primary, by `pull_request_review_id`: `find_copilot_comments.sh` emits a `COPILOT_LATEST_REVIEW=<id> COMMIT=<sha> AT=<ts> CLEAN=<true|false>` marker for the most recent Copilot review, and tags each inline finding with `(comment id <cid>, review <rid>)`. **A finding is active iff its `review <rid>` matches the `COPILOT_LATEST_REVIEW` id.** Findings whose `rid` is older are stale persistent threads — GitHub keeps them visible in `/comments` until a human clicks "Resolve conversation" on the UI, but Copilot is no longer flagging them on the current code. This is the authoritative filter; it does not require any cross-reference to `last_seen_comment_id` or commit-id math.

     **Why this rule exists**: in the absence of `pull_request_review_id` filtering, the loop processes every unresolved comment on the PR as if it were active, including findings from reviews against pre-fix SHAs. PR #80's compound observed this: cycles 11, 14, 17, 18 all spent on findings that Copilot had already cleared from current HEAD, just because the GitHub UI didn't auto-resolve the threads. Comparing `review` ids against `COPILOT_LATEST_REVIEW` cuts that noise to zero.

     Legacy fallback (kept for the case where the tool isn't refreshed): a finding is genuinely stale only when **both** (a) Copilot's most-recent `/reviews` entry is clean AND (b) the finding's comment id is ≤ `last_seen_comment_id`. The `pull_request_review_id` rule above supersedes this — it doesn't require the `/reviews` clean-signal precondition.

     **Line-number drift is NOT a new-finding signal.** GitHub line-anchored review comments track code position across commits — the same inline comment id will reappear at *different* line numbers on each fetch as the file is edited around it. Example from mind-vault PR #55: after the fix push, Copilot's unresolved comment 3119819571 shifted from `install-gcloud-cli.sh:88` to `:97`, and comment 3119819578 from `:135` to `:144`. The finding title and file stayed identical; only the line moved. The `comment id` (not `file:line`) is the identity for the staleness comparison above. Never compare on title+line and conclude "still flagged" — compare the id.

2. **Zero Copilot activity for `last_push_sha`?** Either the PR was opened without `@copilot` as a reviewer, or auto-review isn't enabled for this repo. **Request a Copilot review once, then go to Phase 4** — do NOT fall through to "no findings, hand back":

   - `./tools/copilot_retrigger.sh [PR_NUMBER]` (preferred — hard-coded `gh pr edit --add-reviewer @copilot` invocation, pre-approved in settings).
   - Unlike Cursor Bugbot, Copilot trigger is **not** a PR comment — it's a reviewer assignment via the GitHub API. So there's no trigger-comment id to record; instead, advance `last_seen_comment_id` only when actual review/comment activity arrives.
   - Do **not** proceed to Phase 2/3 this cycle — there's nothing to fix yet.
   - **Guardrail**: only request the trigger when zero Copilot activity exists for the current push SHA. From June 1, 2026 Copilot reviews consume GitHub Actions minutes — each requested review is billed.

3. For each finding found, classify into a tier:

   - **Tier 1 — Auto-fix**: matches a codified pattern (see `AGENT_copilot.md` *Common Review Findings* §1-8), touches ≤1 file, targeted test exists.
   - **Tier 2 — Approve-then-fix**: actionable but uncodified, OR touches shared helper/mixin.
   - **Tier 3 — Escalate**: cross-file, architectural, conflicts with project convention, OR Copilot self-withdrew.

4. For every Tier 1 and Tier 2 finding, write a one-sentence justification: *why is this actually a bug?* If the explanation is hand-wavy or just paraphrases the bot → drop to Tier 3.

5. Persist to `~/.claude/memory/projects/<project-slug>/copilot-pr-<N>.md` so the next wake cycle can reload state without re-reading summaries (mitigates context rot). The scratch file must checkpoint **every** piece of state that a hard bound depends on, after every mutation:

   - `commits_this_session` (int, /20 — matches `max_commits_per_session`)
   - `active_work_minutes` (int, /180 — matches `max_active_work_minutes`; best-effort, updated each cycle)
   - `idle_polls` (int, /20 — matches `max_idle_polls`)
   - `last_seen_comment_id` (GitHub comment id; used by Phase 4 to detect truly-new comments)
   - `last_push_sha` (SHA of the last feature-branch push)
   - `no_progress_map` (per-finding-category count of cycles where a commit attempted that category — used by the no-progress detector)
   - Plus the per-cycle triage table (findings + tier + justification + outcome).

   If any of these live only in conversation context, they will be summarised away across `ScheduleWakeup` boundaries and the hard bounds become unenforceable.

## Phase 2: Execute

For each Tier 1 finding (no prompt) and each Tier 2 finding (after explicit `yes` from user):

1. Apply the edit.
2. **Audit newly-reachable code** when the edit REMOVES a short-circuit (empty-state guard inserted, early return deleted, missing `init()`/`open()`/`register()` call inserted, async resolution fixed, type-gate relaxed). The fix may have unmasked latent bugs downstream — what was invisible because the path never fired is now visibly wrong. See [`skills/work/references/AUDIT_NEWLY_REACHABLE_CODE.md`](../skills/work/references/AUDIT_NEWLY_REACHABLE_CODE.md) for the audit procedure + 3-response decision tree. Fold any same-file / tightly-coupled latents into the same Phase 3 commit; cross-file latents land as a follow-on commit on the same branch.
3. Run targeted test (`make test-fresh ARGS="app.tests.ClassName"` or project equivalent) — class scope only. **Verification routing — see § "v3.1 fix-verification routing" below for the env-var-driven mode.**
4. If test fails: revert edit, log to scratch file, move to next finding (do not retry-fix in the same cycle).

Tier 3 findings: skip the fix, log to the scratch file, and continue processing other findings in this cycle. List all Tier 3 escalations in the final hand-back for human decision. This is a *per-finding* escalation, not a whole-loop abort.

### v3.1 fix-verification routing

Under sprint-auto v3.1 (`SPRINT_AUTO_INTEGRATION_WORKTREE` is set), step 2's targeted test does NOT run in the per-IDEA worktree (which is code-surface only with no `.env` or docker stack). Only the **test command's location** changes — the edit-then-test contract per finding is unchanged, and Phase 3's "one commit per Copilot review cycle" batching still applies (the v3.1 routing affects WHERE the test runs, NOT WHEN the commit happens).

```bash
if [[ -n "${SPRINT_AUTO_INTEGRATION_WORKTREE:-}" ]]; then
    integration_wt="$SPRINT_AUTO_INTEGRATION_WORKTREE"
    feature_branch=$(git branch --show-current)  # e.g. auto/<slug>

    # The edit was already applied in the per-IDEA worktree by Phase 2 step 1.
    # To expose it to the integration worktree's containers for mid-cycle
    # testing — BEFORE Phase 3's batch commit — pick ONE of these mechanisms
    # (git can't push uncommitted state, so this is a real choice, not a
    # hand-wave):
    #
    #   (a) WIP commit on the per-IDEA branch + push, integration worktree
    #       fetches and `git checkout --detach` to the WIP SHA. Phase 3 later
    #       squashes / rewrites the WIP into the proper batch commit.
    #       NOT ALLOWED under the default bounded-autonomy policy: the
    #       squash-on-Phase-3 step requires `--force-with-lease`, and
    #       force-pushing to a branch with an open PR invalidates earlier
    #       review-anchor comments (which the loop's escalation discipline
    #       depends on). Use only if the human explicitly authorizes a
    #       history rewrite for this PR (e.g. `--allow-force-rewrite` arg
    #       to sprint-auto, not yet implemented). The repo's review-loop
    #       discipline is "fresh commits + git revert; avoid force-push."
    #
    #   (b) `rsync --exclude='.git' <per-idea-worktree>/ <integration-worktree>/`
    #       or a project-local bind-mount in docker-compose so the integration
    #       container sees the per-IDEA worktree's source live. Costs:
    #       project-specific compose setup; one-time configuration in
    #       tools/sprint-auto-hooks.sh.
    #
    #   (c) Skip mid-cycle test verification entirely; defer to Phase 3's
    #       post-commit Copilot retrigger to surface failures via the next
    #       review cycle. Costs: a regression slips one cycle later.
    #
    # The v1 of v3.1 ships (c) as the safe default. (b) is the project opt-in
    # via `tools/sprint-auto-hooks.sh:sync_per_idea_to_integration`. (a) is
    # disallowed by default per the force-push prohibition above.
    # After Phase 3 commits + pushes, the integration worktree can always
    # `cd $integration_wt && git fetch origin <branch> &&
    #   git checkout --detach origin/<branch>` (NOT plain `git checkout
    # <branch>` — that errors with "already checked out" because the
    # per-IDEA worktree claims the branch ref) — no special sync needed
    # post-commit.

    # Mid-cycle targeted test against the integration stack:
    pushd "$integration_wt" >/dev/null
    # Sync the per-IDEA worktree's source into the integration worktree
    # (project-specific; rsync-with-exclude is one option, but the simplest
    # contract is "Phase 3 commits + Phase 3 push, then this checkout sees
    # the new state"). For mid-cycle test BEFORE Phase 3 commit, projects
    # may need a project-local hook in tools/sprint-auto-hooks.sh.
    docker compose exec -T web pytest <targeted path>  # against current state
    test_exit=$?
    popd >/dev/null

    if (( test_exit != 0 )); then
        # Test failed: revert the EDIT (in the per-IDEA worktree's working
        # tree, NOT a commit since none was made yet for this finding).
        # Use `git checkout -- <files>` to restore from index; or `git stash`
        # the bad edit and pop it later for forensics.
        git checkout -- <files-that-were-edited>
    fi
fi
```

DB state on the integration worktree is preserved across fix-cycle iterations within an IDEA's Copilot session — sprint-auto only resets between IDEAs (S1.5), not between Copilot commits. Fix commits typically don't migrate, so the DB state at this-IDEA's-baseline is consistent for the duration of the session.

**Phase 3 is unchanged in v3.1**: at the end of each Copilot review cycle, all successfully-applied fixes from Phase 2 still get batched into ONE commit (`fix(scope): address Copilot review N (PR #M)`), pushed once, and the Copilot retrigger fires once. The v3.1 routing only changes the test-execution location; the commit cadence is identical to standalone mode.

**Implementation gap acknowledged**: the snippet above describes the contract; the exact mechanism for "expose per-IDEA worktree's edits to the integration worktree's containers without committing yet" is project-specific and may need a project-local hook (e.g. `tools/sprint-auto-hooks.sh` could expose a `sync_per_idea_to_integration <branch>` function). For v3.1 first ship, projects that can't satisfy mid-cycle test routing should fall back to: apply the edit in the per-IDEA worktree, defer the targeted test to Phase 3's post-commit retrigger (Copilot's next review will catch any regression), then either ship the failing fix as Tier 3 escalation or revert and try a different angle on next cycle.

When `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset (standalone copilot-loop), step 2 runs the targeted test against the current worktree's stack as before — no behaviour change.

## Phase 3: Commit + push + re-trigger

**Skip condition**: if zero fixes were applied in Phase 2 (all findings Tier 3, or all edits reverted on test failure), skip Phase 3 **and** skip Phase 4 entirely — hand back to the user immediately with all unfixed findings surfaced as Tier 3 escalations. Rationale: no fixes means no push; no push means Copilot has nothing new to review; polling would only rediscover the same unfixable findings and waste the active-work budget. The user either fixes manually and re-invokes `/copilot-loop`, or decides the findings are not actionable. Do not commit empty, do not re-trigger Copilot on unchanged code.

If at least one fix was applied:

1. **One commit per Copilot review cycle**, not per finding.
   - Format: `fix(scope): address Copilot review N (PR #M)`
   - Body lists each finding closed.
2. `git push origin HEAD`.
3. `./tools/copilot_retrigger.sh [PR_NUMBER]` (preferred) — wraps `gh pr edit <PR> --add-reviewer @copilot` (requires `gh` ≥ 2.88) so the invocation can be pre-approved in `~/.claude/settings.json` without risking arbitrary reviewer additions. Falls back to current-branch PR lookup if no arg given. **Calibration caveat**: whether re-adding an already-requested reviewer actually re-triggers Copilot is empirically TBD — if the first PR test shows it doesn't, the script falls back to remove-then-add (`gh pr edit --remove-reviewer @copilot && gh pr edit --add-reviewer @copilot`).
4. Increment session commit counter. If ≥ 20 → stop and hand back.

## Phase 4: Wait + wake

The wake-loop in this phase IS a watcher in the [`skills/work/references/WATCHER_HYGIENE.md`](../skills/work/references/WATCHER_HYGIENE.md) sense: orchestrator-armed, supersede-able, never wall-clock-timeout-bound. Apply that reference's discipline — explicit `TaskStop` on supersede, no `pgrep -f` self-match traps, explicit cleanup on terminal condition.

1. `ScheduleWakeup(delaySeconds=180, ...)` for the first poll (cache-warm). Subsequent polls also use short cache-warm intervals — see escalation note below.
2. On wake: re-fetch Copilot comments via `./tools/find_copilot_comments.sh`. The script output includes two signals of interest: a `COPILOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<timestamp>` line if Copilot has posted a "found no new issues" review, and an inline list of any unresolved findings (with their review comment ids).
3. Decision tree — evaluate in order. The first two branches are **absolute hard-bound guards**: they are checked before any happy-path branch so that the happy paths (which are collectively exhaustive over wake state) cannot shadow them.
   - **Guard: active-work minutes ≥ 180** (excluding sleep) → hand back immediately, regardless of wake state.
   - **Guard: no-progress detector trips** — same finding category flagged 2× across cycles where a commit *attempted* that category (success-or-revert both count) → hand back immediately. This closes the mixed-cycle stuck-loop case where a reverted fix could be retried indefinitely when a sibling finding's successful push re-triggered Copilot.
   - **New findings since `last_seen_comment_id`** → reset idle-poll counter to 0, update `last_seen_comment_id` to the newest finding's id in the scratch file, reload triage state, return to Phase 1. (Compare against `last_seen_comment_id`, **not** last push SHA — when Phase 3 is skipped, the push doesn't advance and "new since last push" would stay true forever, resetting `idle_polls` on every wake. `last_seen_comment_id` ensures once a review is processed, subsequent polls with no new findings correctly accumulate idle polls.) **This branch must precede the clean-signal branch** because `/reviews` (clean signals) and `/comments` (findings) are independent API resources; both can coexist for the same commit if Copilot is re-triggered and produces new findings after a prior clean review. Unprocessed findings always take precedence over a stale clean signal.
   - **`COPILOT_CLEAN_SIGNAL` present AND its `COMMIT` equals `last_push_sha`** → **PR clean for current head** → hand back immediately with the clean summary. Do not wait out the idle-poll bound. Ignore clean signals whose `COMMIT` is a stale SHA (Copilot posted them for a previous push). (This branch is only reached when the new-findings branch above didn't fire — i.e. no unprocessed findings exist.)

     **Race-condition caveat — clean signal `COMMIT` is the trigger-anchor SHA, not the reviewed SHA.** Copilot review takes ~30s (much faster than Bugbot's 1–10 min) but the principle still applies: during that window a docs / comment / no-content commit may land on the branch. The review-body's `Reviewed by GitHub Copilot for commit <sha>` and the script's `COPILOT_CLEAN_SIGNAL=<id> COMMIT=<sha>` both reflect **the SHA at trigger time** — not what Copilot's diff scanner actually inspected. The scanner reads the PR's current diff vs base, which at review-firing time may already include the post-trigger commits. So a strict `COMMIT === last_push_sha` check fails (signal says `facd6c08`, push says `60ed665e`) even when the review's verdict factually applies to the current HEAD.

     When the comparison fails but the signal is suspiciously fresh, apply a **timestamp tiebreaker** before re-triggering: if the review's `AT` is later than the latest commit's push timestamp (i.e. Copilot fired AFTER the most recent push landed), treat the clean signal as applying to current HEAD. Practical heuristic — and the safer default if you can't get the push timestamp cheaply: **if the intervening commits since the signal's `COMMIT` are docs-only / comments-only / markdown-only / no source-path changes, skip the re-trigger.** Copilot doesn't review prose-only diffs as new findings (best-guess — empirically calibrate); the re-trigger is at best a no-op and at worst billable noise.

     The strict equality check stays as the default because it's safe (worst case: one extra cycle), but the race caveat is the documented escape hatch when a docs commit / wrap commit lands between fix-push and clean-signal arrival.

   - **No clean signal, no new findings**, idle-poll counter < 20 → increment idle-poll counter, `ScheduleWakeup` again with a **linear 270s cadence** (just under the 300s prompt-cache TTL so each wake stays cache-warm — never ramp past 5 min between Copilot checks). Clean signal is the fast path; idle-poll accumulation is the fallback for the case where Copilot is hung or slow. Use `max_idle_polls = 20` as the only backstop — a slow-but-progressing Copilot (typical) will land findings or a clean signal well before that counter maxes, and a genuinely hung Copilot hits the 20-poll bound in under 90 min, which is the right moment to hand back.
   - **No clean signal, no new findings**, idle-poll counter ≥ 20 → escalate: Copilot may be hung; hand back to user.

## Hand-back report

Always end with:

1. Summary: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
2. Tier 3 escalations with reasoning (these need human decision).
3. Suggested broader regression command for the user to run before merge (e.g. `make test ARGS="app.tests"`).
4. PR URL.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.

Under sprint-auto v3.1, the "user" the loop hands back to is sprint-auto itself (the orchestrator), which uses the Tier-3 list to drive its escalation cycle (S4 deliverables / S7 docs / S11.10 integration / S11.12 re-review). The hand-back semantics are unchanged — copilot-loop produces the same Tier-3 hand-back regardless of caller.
