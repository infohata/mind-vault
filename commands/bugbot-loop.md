---
description: Semi-autonomous bugbot review loop with bounded-autonomy policy (Option B+)
agent: general
---

# /bugbot-loop

Drive a Cursor Bugbot review-fix-rerun cycle on the current PR (or specified PR number) under the bounded-autonomy policy defined in `agents/AGENT_bugbot.md`.

**Inputs**: optional PR number. Default: PR for current branch.

## Hard bounds (enforced by the loop)

- `max_commits_per_session = 10`
- `max_active_work_minutes = 20` (excludes ScheduleWakeup sleep time)
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
4. Persist triage to `~/.claude/memory/projects/<project-slug>/bugbot-pr-<N>.md` so the next wake cycle can reload intent without re-reading summaries (mitigates context rot).

## Phase 2: Execute

For each Tier 1 finding (no prompt) and each Tier 2 finding (after explicit `yes` from user):

1. Apply the edit.
2. Run targeted test (`make test-fresh ARGS="app.tests.ClassName"` or project equivalent) — class scope only.
3. If test fails: revert edit, log to scratch file, move to next finding (do not retry-fix in the same cycle).

Tier 3 findings: skip the fix, log to the scratch file, and continue processing other findings in this cycle. List all Tier 3 escalations in the final hand-back for human decision. This is a *per-finding* escalation, not a whole-loop abort.

## Phase 3: Commit + push + re-trigger

**Skip condition**: if zero fixes were applied in Phase 2 (all findings Tier 3, or all edits reverted on test failure), skip Phase 3 entirely and go directly to Phase 4 with `idle_polls += 1`. Do not commit empty, do not re-trigger bugbot on unchanged code — that would just burn the active-work budget on the same unfixable findings. Surface the unfixed findings in the hand-back immediately if no Tier 1/2 fixes are possible.

If at least one fix was applied:

1. **One commit per bugbot-run cycle**, not per finding.
   - Format: `fix(scope): address bugbot review N (PR #M)`
   - Body lists each finding closed.
2. `git push origin HEAD`.
3. `gh pr comment -b "bugbot run"`.
4. Increment session commit counter. If ≥ 10 → stop and hand back.

## Phase 4: Wait + wake

1. `ScheduleWakeup(delaySeconds=180, ...)` for the first poll (cache-warm).
2. On wake: re-fetch bugbot comments via `./tools/find_bugbot_comments.sh`.
3. Decision — compare against `last_seen_comment_id` tracked in the scratch file, **not** against last push SHA. Reason: when Phase 3 is skipped (all fixes reverted), the last push doesn't advance, so "new since last push" would stay true forever and reset `idle_polls` on every wake. Comparing against `last_seen_comment_id` ensures that once a review is processed, subsequent polls with no new findings correctly accumulate idle polls.
   - **New comments since `last_seen_comment_id`** → **reset idle-poll counter to 0**, update `last_seen_comment_id` to the newest comment's id in the scratch file, reload triage state, return to Phase 1. (The bound counts *consecutive* idle polls; any productive cycle resets.)
   - **No new comments**, idle-poll counter < 20 → increment idle-poll counter, `ScheduleWakeup` again (escalate delay: 180 → 600 → 1200s).
   - **No new comments**, idle-poll counter ≥ 20 → escalate: bugbot may be hung or PR clean; hand back to user.
   - **Active-work minutes ≥ 20** (excluding sleep) → hand back.
   - **Same finding category flagged 2× across cycles where a commit attempted that category** → no-progress detector trips; hand back. ("Attempted" counts whether the fix succeeded or was reverted — this closes the mixed-cycle stuck-loop gap where a reverted fix could be retried indefinitely if a sibling finding's successful push re-triggered bugbot.)

## Hand-back report

Always end with:

1. Summary: cycles run, findings auto-fixed, findings approved, findings escalated, findings skipped.
2. Tier 3 escalations with reasoning (these need human decision).
3. Suggested broader regression command for the user to run before merge (e.g. `make test ARGS="app.tests"`).
4. PR URL.

Do not merge. Do not push to main. The loop hands the PR back to the user for final review and merge.
