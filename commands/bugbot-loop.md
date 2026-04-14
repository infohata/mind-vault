---
description: Semi-autonomous bugbot review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /bugbot-loop

Drive a Cursor Bugbot review-fix-rerun cycle on the current PR (or specified PR number) under the bounded-autonomy policy defined in `agents/AGENT_bugbot.md`.

**Inputs**: optional PR number. Default: PR for current branch.

## Hard bounds (enforced by the loop)

- `max_commits_per_session = 10`
- `max_active_work_minutes = 60` (excludes ScheduleWakeup sleep time)
- `max_idle_polls = 20` (consecutive wakes with no new bugbot comment AND no new push)
- Targeted tests only inside the loop; broader regression deferred to hand-back
- Feature branch only — never main (per `RULE_git-safety`)
- Batch fixes per `bugbot run` cycle into one commit, not one-per-finding
- **Autonomous commit authority within this loop**: per-commit approval from `RULE_git-safety` is *pre-granted* by the act of invoking `/bugbot-loop`. The loop may commit and push Tier 1 fixes without a per-cycle `yes` prompt. Tier 2 fixes still require explicit per-finding approval (that is a *fix-direction* approval, not a commit approval). All other `RULE_git-safety` guardrails remain in force: never main, never merge, never force-push, never `--no-verify`, all commits to feature branches only.

## Phase 0: Worktree environment bootstrap

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

1. Fetch bugbot findings: `./tools/find_bugbot_comments.sh [PR_NUMBER]` (or equivalent `gh api` call filtering `cursor[bot]`).
2. For each finding, classify into a tier:
   - **Tier 1 — Auto-fix**: matches a codified pattern (see `AGENT_bugbot.md` *Common Bugbot Patterns* §1-8), touches ≤1 file, targeted test exists.
   - **Tier 2 — Approve-then-fix**: actionable but uncodified, OR touches shared helper/mixin.
   - **Tier 3 — Escalate**: cross-file, architectural, conflicts with project convention, OR bugbot self-withdrew.
3. For every Tier 1 and Tier 2 finding, write a one-sentence justification: *why is this actually a bug?* If the explanation is hand-wavy or just paraphrases the bot → drop to Tier 3.
4. Persist to `~/.claude/memory/projects/<project-slug>/bugbot-pr-<N>.md` so the next wake cycle can reload state without re-reading summaries (mitigates context rot). The scratch file must checkpoint **every** piece of state that a hard bound depends on, after every mutation:
   - `commits_this_session` (int, /10)
   - `active_work_minutes` (int, /60 — best-effort, updated each cycle)
   - `idle_polls` (int, /20)
   - `last_seen_comment_id` (GitHub comment id; used by Phase 4 to detect truly-new comments)
   - `last_push_sha` (SHA of the last feature-branch push)
   - `no_progress_map` (per-finding-category count of cycles where a commit attempted that category — used by the no-progress detector)
   - Plus the per-cycle triage table (findings + tier + justification + outcome).

   If any of these live only in conversation context, they will be summarised away across `ScheduleWakeup` boundaries and the hard bounds become unenforceable.

## Phase 2: Execute

For each Tier 1 finding (no prompt) and each Tier 2 finding (after explicit `yes` from user):

1. Apply the edit.
2. Run targeted test (`make test-fresh ARGS="app.tests.ClassName"` or project equivalent) — class scope only.
3. If test fails: revert edit, log to scratch file, move to next finding (do not retry-fix in the same cycle).

Tier 3 findings: skip the fix, log to the scratch file, and continue processing other findings in this cycle. List all Tier 3 escalations in the final hand-back for human decision. This is a *per-finding* escalation, not a whole-loop abort.

## Phase 3: Commit + push + re-trigger

**Skip condition**: if zero fixes were applied in Phase 2 (all findings Tier 3, or all edits reverted on test failure), skip Phase 3 **and** skip Phase 4 entirely — hand back to the user immediately with all unfixed findings surfaced as Tier 3 escalations. Rationale: no fixes means no push; no push means bugbot has nothing new to review; polling would only rediscover the same unfixable findings and waste the active-work budget. The user either fixes manually and re-invokes `/bugbot-loop`, or decides the findings are not actionable. Do not commit empty, do not re-trigger bugbot on unchanged code.

If at least one fix was applied:

1. **One commit per bugbot-run cycle**, not per finding.
   - Format: `fix(scope): address bugbot review N (PR #M)`
   - Body lists each finding closed.
2. `git push origin HEAD`.
3. `./tools/bugbot_retrigger.sh [PR_NUMBER]` (preferred) — hard-codes the `bugbot run` body so it can be pre-approved in `~/.claude/settings.json` without risking arbitrary comment injection. Falls back to current-branch PR lookup if no arg given. Equivalent to `gh pr comment <PR> -b "bugbot run"` but auto-approved.
4. Increment session commit counter. If ≥ 10 → stop and hand back.

## Phase 4: Wait + wake

1. `ScheduleWakeup(delaySeconds=180, ...)` for the first poll (cache-warm).
2. On wake: re-fetch bugbot comments via `./tools/find_bugbot_comments.sh`. The script output includes two signals of interest: a `BUGBOT_CLEAN_SIGNAL=<id> COMMIT=<sha> AT=<timestamp>` line if bugbot has posted a "found no new issues" review, and an inline list of any unresolved findings (with their review comment ids).
3. Decision tree — evaluate in order. The first two branches are **absolute hard-bound guards**: they are checked before any happy-path branch so that the happy paths (which are collectively exhaustive over wake state) cannot shadow them.
   - **Guard: active-work minutes ≥ 60** (excluding sleep) → hand back immediately, regardless of wake state.
   - **Guard: no-progress detector trips** — same finding category flagged 2× across cycles where a commit *attempted* that category (success-or-revert both count) → hand back immediately. This closes the mixed-cycle stuck-loop case where a reverted fix could be retried indefinitely when a sibling finding's successful push re-triggered bugbot.
   - **`BUGBOT_CLEAN_SIGNAL` present AND its `COMMIT` equals `last_push_sha`** → **PR clean for current head** → hand back immediately with the clean summary. Do not wait out the idle-poll bound. Ignore clean signals whose `COMMIT` is a stale SHA (bugbot posted them for a previous push).
   - **New findings since `last_seen_comment_id`** → reset idle-poll counter to 0, update `last_seen_comment_id` to the newest finding's id in the scratch file, reload triage state, return to Phase 1. (Compare against `last_seen_comment_id`, **not** last push SHA — when Phase 3 is skipped, the push doesn't advance and "new since last push" would stay true forever, resetting `idle_polls` on every wake. `last_seen_comment_id` ensures once a review is processed, subsequent polls with no new findings correctly accumulate idle polls.)
   - **No clean signal, no new findings**, idle-poll counter < 20 → increment idle-poll counter, `ScheduleWakeup` again (escalate delay: 180 → 600 → 1200s). Clean signal is the fast path; idle-poll accumulation is the fallback for the case where bugbot is hung or slow.
   - **No clean signal, no new findings**, idle-poll counter ≥ 20 → escalate: bugbot may be hung; hand back to user.

## Hand-back report

Always end with:

1. Summary: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
2. Tier 3 escalations with reasoning (these need human decision).
3. Suggested broader regression command for the user to run before merge (e.g. `make test ARGS="app.tests"`).
4. PR URL.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.
