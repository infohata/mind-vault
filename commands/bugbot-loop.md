---
description: Semi-autonomous bugbot review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /bugbot-loop

Drive a Cursor Bugbot review-fix-rerun cycle on the current PR (or specified PR number) under the bounded-autonomy policy defined in `agents/AGENT_bugbot.md`.

**Inputs**: optional PR number. Default: PR for current branch.

## Hard bounds (enforced by the loop)

- `max_commits_per_session = 20`
- `max_active_work_minutes = 180` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20` (consecutive wakes with no new bugbot comment AND no new push)
- Targeted tests only inside the loop; broader regression deferred to hand-back
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per `bugbot run` cycle into one commit, not one-per-finding
- **Commits**: standard `RULE_git-safety` applies — feature branches are the agent's sandbox, so the loop commits and pushes Tier 1 fixes autonomously. Tier 2 still needs explicit per-finding *fix-direction* approval (that is a content decision, not a commit approval). Protected-branch guardrails remain in force: never main, never merge into a protected branch, never force-push to protected, never `--no-verify`.

## Dual-engine sync rule (combined with `/copilot-loop`)

When the user invokes both `/bugbot-loop` AND `/copilot-loop` on the same PR, the loops MUST sync each cycle to avoid double-pushes that invalidate each other's pending reviews. Each cycle waits for **the slowest engine** to either (a) post findings against `last_push_sha` OR (b) post a clean signal for `last_push_sha`, then BATCHES findings from both into ONE fix commit + pushes once + retriggers BOTH engines.

The rationale: each push invalidates pending reviews of the prior SHA — without sync, bugbot's pending review of SHA-A becomes stale the moment copilot-loop commits a fix to SHA-B, forcing bugbot to re-scan from scratch.

**Trade-off escape hatch — proceed with one engine when the other stalls.** Hard "wait for slowest" risks blocking the loop indefinitely if one engine hangs:

| Trip | Trigger | Action |
|---|---|---|
| Bugbot stalled | `BUGBOT_CHECKRUN status=in_progress` for >15 min (well past 1-10 min normal range) on `last_push_sha` | Proceed with Copilot's findings if any; retrigger bugbot post-push. |
| Copilot service-errored 2× consecutive | Copilot review body literally `"Copilot encountered an error..."` on two consecutive HEAD SHAs | Proceed with bugbot's findings if any; do NOT retry Copilot in this cycle. |
| Copilot service-errored 3× consecutive | Third consecutive error | Hand back to user — durable Copilot service issue, can't resolve from the loop. |
| Bugbot CLEAN + Copilot still hung | `BUGBOT_CLEAN_SIGNAL` for `last_push_sha` + Copilot still queued past idle-poll threshold | Wait up to `max_idle_polls` × 270s; if still no Copilot verdict, hand back with bugbot's CLEAN status documented. |

**Sync state — extra scratch-file fields per-engine when running in dual-engine mode:**

```yaml
last_seen_bugbot_review:  <id> @ <sha> CLEAN=<bool>
last_seen_copilot_review: <id> @ <sha> CLEAN=<bool>
last_seen_bugbot_comment_id:  <id>
last_seen_copilot_comment_id: <id>
no_progress_map:
  bugbot:  { <category>: <count> }
  copilot: { <category>: <count> }
```

**Retrigger discipline — different per engine.** Phase 3 fires after the dual-engine batch commit:
- Bugbot: `tools/bugbot_retrigger.sh <PR>` (posts a `bugbot run` comment).
- Copilot: `remove+add` (`gh pr edit --remove-reviewer @copilot && sleep 1 && gh pr edit --add-reviewer @copilot`). The bare `--add-reviewer @copilot` against an already-requested reviewer is a no-op (empirically confirmed).

Both retriggers happen post-push, in that order.

**Hand-back when only one engine cleared.** A non-trivial fraction of dual-engine runs end with one engine CLEAN and the other in a degraded state. The hand-back report MUST distinguish:
- `bugbot: CLEAN at <sha>` AND `copilot: errored / hung / unavailable` — the PR has ONE engine's verdict. Surface this prominently. User decides whether to merge on bugbot's verdict alone, retry copilot from GitHub UI, or proceed without copilot's verdict.
- Mirror for `copilot: CLEAN` AND `bugbot: hung`.
- `both: CLEAN at <sha>` — merge-ready.
- `both: still finding things` — loop continues.

See `/copilot-loop`'s § First-run calibration + § Failure modes blocks for the Copilot-side specifics that motivate the trade-off table above.

## Phase 0: Worktree environment bootstrap

**Sprint-auto v3.1 mode (new) — short-circuit**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is set in the environment, **skip Phase 0 entirely**. Per-IDEA worktrees under sprint-auto v3.1 are pure code surfaces — no `.env`, no docker compose stack. Bugbot-loop's role in this mode narrows to (a) reading Cursor Bugbot's findings via the GitHub API and (b) committing fixes to the per-IDEA branch. Neither activity needs a runtime in the per-IDEA worktree. When fix-verification runs in Phase 2 / Phase 3, it routes to the integration worktree (see Phase 2 § "v3.1 fix-verification routing"). See [`skills/sprint-auto/references/integration-stage.md`](../skills/sprint-auto/references/integration-stage.md) for the full env-var contract.

**Standalone mode (default)**: if `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset, fall through to the existing worktree-bootstrap logic below.

If `git rev-parse --git-common-dir` differs from `.git` (i.e. running inside a worktree):

1. If `.env` already exists → skip to step 3 (containers only).
2. Else (`.env` missing):
   - If `.env.template` exists:
     - Copy template → `.env`.
     - Replace any `*_API_KEY=` / `*_TOKEN=` / `*_SECRET=` values with `test-not-a-real-key`.
     - Replace `SECRET_KEY=` with `test-<random-hex>` — generate the literal value via `openssl rand -hex 16` and paste the output. (Do NOT write the literal `$(openssl ...)` form into `.env` — most dotenv loaders don't evaluate shell substitution and the loader will use the `$(...)` string verbatim, breaking the app at boot.)
     - Scope DB/Redis URLs to the worktree's docker compose project namespace.
   - If `.env.template` missing → escalate to user; do not proceed.
3. Spin up containers: `docker compose up -d`.
4. In primary working tree: skip this phase entirely.

This is the **only** authorised place to create `.env` — see exception clause in global `CLAUDE.md`.

## Phase 1: Triage

1. **Fetch bugbot state** for the PR:

   - Comments: `./tools/find_bugbot_comments.sh [PR_NUMBER]` (preferred — includes the `BUGBOT_CLEAN_SIGNAL` marker), or equivalent `gh api repos/.../pulls/<N>/comments` + `.../issues/<N>/comments` + `.../pulls/<N>/reviews`, filtering `user.login == "cursor[bot]"`.
   - Parse unresolved review comments on code lines (findings) separately from reviews (clean-signal source).
   - **Dual-signal enumeration — mandatory output shape every cycle.** Always present both signals explicitly in your cycle summary, even when one of them is absent. The two GitHub resources (`/reviews` for the bugbot review-body clean flag, `/comments` for inline line-anchored findings) are **independent and can coexist for the same commit** — bugbot may post an overall "found no new issues" review AND one or more inline LOW-severity style/structure hints on the same push. Inline comments from prior reviews also persist in `/comments` until a reviewer manually clicks "Resolve conversation" on GitHub, so a stale-by-fix finding can linger alongside a fresh clean signal. Required shape:

     ```
     - /reviews  : ✅ CLEAN signal <review-id> @ <sha> OR ❌ no signal for current head
     - /comments : <N> inline finding(s) [list them if > 0, with ids + L# ranges]
     ```

     Then apply Phase 4's decision tree to resolve these two enumerations into an action. **Never collapse the two signals into a single "is the PR clean?" conclusion at Phase 1 output time.** The Phase 4 decision tree will handle the collapse correctly (new-findings branch precedes clean-signal branch), but only if Phase 1's output surfaces both resources independently. Context-rot during `ScheduleWakeup` sleeps tends to re-merge the two signals into one; the explicit dual presentation is what survives compaction.

     Staleness rule — primary, by `pull_request_review_id`: `find_bugbot_comments.sh` emits a `BUGBOT_LATEST_REVIEW=<id> COMMIT=<sha> AT=<ts> CLEAN=<true|false>` marker for the most recent bugbot review, and tags each inline finding with `(comment id <cid>, review <rid>)`. **A finding is active iff its `review <rid>` matches the `BUGBOT_LATEST_REVIEW` id.** Findings whose `rid` is older are stale persistent threads — GitHub keeps them visible in `/comments` until a human clicks "Resolve conversation" on the UI, but bugbot is no longer flagging them on the current code. This is the authoritative filter; it does not require any cross-reference to `last_seen_comment_id` or commit-id math.

     **Why this rule exists**: in the absence of `pull_request_review_id` filtering, the loop processes every unresolved comment on the PR as if it were active, including findings from reviews against pre-fix SHAs. PR #80's compound observed this: cycles 11, 14, 17, 18 all spent on findings that bugbot had already cleared from current HEAD, just because the GitHub UI didn't auto-resolve the threads. Comparing `review` ids against `BUGBOT_LATEST_REVIEW` cuts that noise to zero.

     Legacy fallback (kept for the case where the tool isn't refreshed): a finding is genuinely stale only when **both** (a) bugbot's most-recent `/reviews` entry is clean AND (b) the finding's comment id is ≤ `last_seen_comment_id`. The `pull_request_review_id` rule above supersedes this — it doesn't require the `/reviews` clean-signal precondition.

     **Line-number drift is NOT a new-finding signal.** GitHub line-anchored review comments track code position across commits — the same inline comment id will reappear at *different* line numbers on each fetch as the file is edited around it. Example from mind-vault PR #55: after the fix push, bugbot's unresolved comment 3119819571 shifted from `install-gcloud-cli.sh:88` to `:97`, and comment 3119819578 from `:135` to `:144`. The finding title and file stayed identical; only the line moved. The `comment id` (not `file:line`) is the identity for the staleness comparison above. Never compare on title+line and conclude "still flagged" — compare the id.

2. **Zero bugbot activity for `last_push_sha`?** Either the PR is fresh and bugbot hasn't auto-triggered, or auto-trigger is off for this repo. **Post the trigger comment once, then go to Phase 4** — do NOT fall through to "no findings, hand back":

   - `./tools/bugbot_retrigger.sh [PR_NUMBER]` (preferred — hard-coded body, pre-approved in settings) or `gh pr comment <PR_NUMBER> -b "bugbot run"` as fallback.
   - Record the trigger-comment id in `last_seen_comment_id` immediately so subsequent polls don't misread our own "bugbot run" as a new finding.
   - Do **not** proceed to Phase 2/3 this cycle — there's nothing to fix yet.
   - **Guardrail**: only post the trigger when zero bugbot activity exists for the current push SHA. Don't re-trigger on every invocation; bugbot is rate-limited and each review is billed.

3. For each finding found, classify into a tier:

   - **Tier 1 — Auto-fix**: matches a codified pattern (see `AGENT_bugbot.md` *Common Bugbot Patterns* §1-8), touches ≤1 file, targeted test exists.
   - **Tier 2 — Approve-then-fix**: actionable but uncodified, OR touches shared helper/mixin.
   - **Tier 3 — Escalate**: cross-file, architectural, conflicts with project convention, OR bugbot self-withdrew.

4. For every Tier 1 and Tier 2 finding, write a one-sentence justification: *why is this actually a bug?* If the explanation is hand-wavy or just paraphrases the bot → drop to Tier 3.

5. Persist to `~/.claude/memory/projects/<project-slug>/bugbot-pr-<N>.md` so the next wake cycle can reload state without re-reading summaries (mitigates context rot). The scratch file must checkpoint **every** piece of state that a hard bound depends on, after every mutation:

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

Under sprint-auto v3.1 (`SPRINT_AUTO_INTEGRATION_WORKTREE` is set), step 2's targeted test does NOT run in the per-IDEA worktree (which is code-surface only with no `.env` or docker stack). Only the **test command's location** changes — the edit-then-test contract per finding is unchanged, and Phase 3's "one commit per bugbot-run cycle" batching still applies (the v3.1 routing affects WHERE the test runs, NOT WHEN the commit happens).

```bash
if [[ -n "${SPRINT_AUTO_INTEGRATION_WORKTREE:-}" ]]; then
    integration_wt="$SPRINT_AUTO_INTEGRATION_WORKTREE"
    feature_branch=$(git branch --show-current)  # e.g. auto/<slug>

    # The edit was already applied in the per-IDEA worktree by Phase 2 step 1.
    # Push the per-IDEA branch's tip so the integration worktree can fetch it
    # — but DO NOT commit yet (Phase 3 will batch all of this cycle's fixes
    # into one commit; the push here is to make the in-progress edit visible
    # to the integration worktree's checkout, not to publish it for review).
    #
    # Approach in v3.1: keep the edits unstaged in the per-IDEA worktree;
    # use `git stash create` + `git fetch` of the stash blob to expose the
    # working-tree state to the integration worktree without committing,
    # OR (simpler) commit-then-revert if the edit needs to be restorable
    # mid-cycle. The cleanest contract for v1 of v3.1: just bind-mount or
    # rsync the per-IDEA worktree's source into the integration worktree's
    # web container — most projects already do this via docker compose's
    # volume mount, so `cd $integration_wt && git fetch origin <branch> &&
    # git checkout --detach origin/<branch>` (NOT plain `git checkout
    # <branch>` — that errors with "already checked out" because the
    # per-IDEA worktree claims the branch ref) after any commits in Phase 3
    # is sufficient for the post-Phase-3 retest.
    #
    # Until Phase 3 commits, run the targeted test using the per-IDEA
    # worktree's source by bind-mounting it into the integration worktree's
    # web container — depends on project compose setup. Fallback: skip
    # mid-cycle test verification under v3.1; rely on Phase 3's bugbot
    # retrigger to surface failures via the next review cycle.

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

DB state on the integration worktree is preserved across fix-cycle iterations within an IDEA's bugbot session — sprint-auto only resets between IDEAs (S1.5), not between bugbot commits. Fix commits typically don't migrate, so the DB state at this-IDEA's-baseline is consistent for the duration of the session.

**Phase 3 is unchanged in v3.1**: at the end of each bugbot-run cycle, all successfully-applied fixes from Phase 2 still get batched into ONE commit (`fix(scope): address bugbot review N (PR #M)`), pushed once, and the bugbot retrigger fires once. The v3.1 routing only changes the test-execution location; the commit cadence is identical to standalone mode.

**Implementation gap acknowledged**: the snippet above describes the contract; the exact mechanism for "expose per-IDEA worktree's edits to the integration worktree's containers without committing yet" is project-specific and may need a project-local hook (e.g. `tools/sprint-auto-hooks.sh` could expose a `sync_per_idea_to_integration <branch>` function). For v3.1 first ship, projects that can't satisfy mid-cycle test routing should fall back to: apply the edit in the per-IDEA worktree, defer the targeted test to Phase 3's post-commit retrigger (bugbot's next review will catch any regression), then either ship the failing fix as Tier 3 escalation or revert and try a different angle on next cycle.

When `SPRINT_AUTO_INTEGRATION_WORKTREE` is unset (standalone bugbot-loop), step 2 runs the targeted test against the current worktree's stack as before — no behaviour change.

## Phase 3: Commit + push + re-trigger

**Skip condition**: if zero fixes were applied in Phase 2 (all findings Tier 3, or all edits reverted on test failure), skip Phase 3 **and** skip Phase 4 entirely — hand back to the user immediately with all unfixed findings surfaced as Tier 3 escalations. Rationale: no fixes means no push; no push means bugbot has nothing new to review; polling would only rediscover the same unfixable findings and waste the active-work budget. The user either fixes manually and re-invokes `/bugbot-loop`, or decides the findings are not actionable. Do not commit empty, do not re-trigger bugbot on unchanged code.

If at least one fix was applied:

1. **One commit per bugbot-run cycle**, not per finding.
   - Format: `fix(scope): address bugbot review N (PR #M)`
   - Body lists each finding closed.
2. `git push origin HEAD`.
3. `./tools/bugbot_retrigger.sh [PR_NUMBER]` (preferred) — hard-codes the `bugbot run` body so it can be pre-approved in `~/.claude/settings.json` without risking arbitrary comment injection. Falls back to current-branch PR lookup if no arg given. Equivalent to `gh pr comment <PR> -b "bugbot run"` but auto-approved.
4. Increment session commit counter. If ≥ 20 → stop and hand back.

## Phase 4: Wait + wake

The wake-loop in this phase IS a watcher in the [`skills/work/references/WATCHER_HYGIENE.md`](../skills/work/references/WATCHER_HYGIENE.md) sense: orchestrator-armed, supersede-able, never wall-clock-timeout-bound. Apply that reference's discipline — explicit `TaskStop` on supersede, no `pgrep -f` self-match traps, explicit cleanup on terminal condition.

1. `ScheduleWakeup(delaySeconds=180, ...)` for the first poll (cache-warm). Subsequent polls also use short cache-warm intervals — see escalation note below.
2. On wake: re-fetch bugbot comments via `./tools/find_bugbot_comments.sh`. The script output includes two signals of interest: a `BUGBOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<timestamp>` line if bugbot has posted a "found no new issues" review, and an inline list of any unresolved findings (with their review comment ids).
3. Decision tree — evaluate in order. The first two branches are **absolute hard-bound guards**: they are checked before any happy-path branch so that the happy paths (which are collectively exhaustive over wake state) cannot shadow them.
   - **Guard: active-work minutes ≥ 180** (excluding sleep) → hand back immediately, regardless of wake state.
   - **Guard: no-progress detector trips** — same finding category flagged 2× across cycles where a commit *attempted* that category (success-or-revert both count) → hand back immediately. This closes the mixed-cycle stuck-loop case where a reverted fix could be retried indefinitely when a sibling finding's successful push re-triggered bugbot.
   - **New findings since `last_seen_comment_id`** → reset idle-poll counter to 0, update `last_seen_comment_id` to the newest finding's id in the scratch file, reload triage state, return to Phase 1. (Compare against `last_seen_comment_id`, **not** last push SHA — when Phase 3 is skipped, the push doesn't advance and "new since last push" would stay true forever, resetting `idle_polls` on every wake. `last_seen_comment_id` ensures once a review is processed, subsequent polls with no new findings correctly accumulate idle polls.) **This branch must precede the clean-signal branch** because `/reviews` (clean signals) and `/comments` (findings) are independent API resources; both can coexist for the same commit if bugbot is re-triggered and produces new findings after a prior clean review. Unprocessed findings always take precedence over a stale clean signal.
   - **`BUGBOT_CLEAN_SIGNAL` present AND its `COMMIT` equals `last_push_sha`** → **PR clean for current head** → hand back immediately with the clean summary. Do not wait out the idle-poll bound. Ignore clean signals whose `COMMIT` is a stale SHA (bugbot posted them for a previous push). (This branch is only reached when the new-findings branch above didn't fire — i.e. no unprocessed findings exist.)

     **Race-condition caveat — clean signal `COMMIT` is the trigger-anchor SHA, not the reviewed SHA.** Bugbot review takes 1–10 min; during that window a docs / comment / no-content commit may land on the branch. The review-body's `Reviewed by Cursor Bugbot for commit <sha>` and the script's `BUGBOT_CLEAN_SIGNAL=<id> COMMIT=<sha>` both reflect **the SHA at trigger time** — not what bugbot's diff scanner actually inspected. The scanner reads the PR's current diff vs base, which at review-firing time may already include the post-trigger commits. So a strict `COMMIT === last_push_sha` check fails (signal says `facd6c08`, push says `60ed665e`) even when the review's verdict factually applies to the current HEAD.

     When the comparison fails but the signal is suspiciously fresh, apply a **timestamp tiebreaker** before re-triggering: if the review's `AT` is later than the latest commit's push timestamp (i.e. bugbot fired AFTER the most recent push landed), treat the clean signal as applying to current HEAD. Practical heuristic — and the safer default if you can't get the push timestamp cheaply: **if the intervening commits since the signal's `COMMIT` are docs-only / comments-only / markdown-only / no source-path changes, skip the re-trigger.** Bugbot doesn't review prose-only diffs as new findings; the re-trigger is at best a no-op and at worst billable noise.

     The strict equality check stays as the default because it's safe (worst case: one extra cycle), but the race caveat is the documented escape hatch when a docs commit / wrap commit lands between fix-push and clean-signal arrival.

   - **No clean signal, no new findings**, idle-poll counter < 20 → increment idle-poll counter, `ScheduleWakeup` again with a **linear 270s cadence** (just under the 300s prompt-cache TTL so each wake stays cache-warm — never ramp past 5 min between bugbot checks). Clean signal is the fast path; idle-poll accumulation is the fallback for the case where bugbot is hung or slow. Use `max_idle_polls = 20` as the only backstop — a slow-but-progressing bugbot (typical) will land findings or a clean signal well before that counter maxes, and a genuinely hung bugbot hits the 20-poll bound in under 90 min, which is the right moment to hand back.
   - **No clean signal, no new findings**, idle-poll counter ≥ 20 → escalate: bugbot may be hung; hand back to user.

## Hand-back report

Always end with:

1. Summary: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
2. Tier 3 escalations with reasoning (these need human decision).
3. Suggested broader regression command for the user to run before merge (e.g. `make test ARGS="app.tests"`).
4. PR URL.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.

Under sprint-auto v3.1, the "user" the loop hands back to is sprint-auto itself (the orchestrator), which uses the Tier-3 list to drive its escalation cycle (S4 deliverables / S7 docs / S11.10 integration / S11.12 re-bugbot). The hand-back semantics are unchanged — bugbot-loop produces the same Tier-3 hand-back regardless of caller.
