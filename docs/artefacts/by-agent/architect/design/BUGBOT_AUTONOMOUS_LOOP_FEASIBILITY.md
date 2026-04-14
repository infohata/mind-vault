# Bugbot Autonomous Loop — Feasibility & Design Notes

**Author**: Claude Opus 4.6 (architect role)
**Date**: 2026-04-14
**Status**: Policy chosen (2026-04-14) — **Option B+** with bounded autonomy carve-out. v1 implemented as `commands/bugbot-loop.md`. Option C deferred until ≥3 successful dogfood runs.
**Context**: Materialised from Teisutis PR #293 (IDEA-088 Phase 2) — a session where 6+ bugbot review cycles were driven manually, each round: read finding → fix → run targeted tests → commit → push → `gh pr comment "bugbot run"` → wait.

## Problem Statement

Cursor Bugbot (`cursor[bot]` on GitHub) posts review comments on PRs when triggered via a `bugbot run` comment. A typical PR goes through 3–8 review cycles before it's clean. Today this is driven manually:

1. User asks agent to check PR comments.
2. Agent fetches via `gh api`, filters to `cursor[bot]`, presents findings.
3. For each actionable finding: agent proposes fix, user approves, agent implements.
4. Agent commits, pushes, comments `bugbot run`.
5. Wait 1–3 minutes for bugbot to re-review.
6. Loop.

The plumbing (`ScheduleWakeup`, `gh api`, existing `tools/find_bugbot_comments.sh`) is all in place. The question is whether this should be autonomous — i.e. the agent drives the loop without per-cycle user involvement.

## Where Autonomy Works

- **Dynamic pacing** — `ScheduleWakeup` already supports adaptive delays (keep cache warm under 300s when polling, amortise past 1200s+ when idle).
- **Deterministic cycle** — the fix-push-rerun flow is already codified in memory (`feedback_bugbot_workflow.md`).
- **Targeted tests are cheap** — `make test-fresh ARGS=...` on a single class is ~8s; cost per cycle is negligible.
- **Stop conditions are observable** — "no new cursor[bot] comments for N polls after last push" is a clean terminator.

## Where Autonomy Gets Dangerous

### 1. Context rot

A 5-cycle review session like PR #293 accumulates real code changes + file reads + tool outputs across rounds. An autonomous loop running unattended will hit the summariser and drift — early commits made with full context, late commits made with a summary of a summary. Fixes in round 5 may contradict decisions made in round 1 because the agent no longer remembers why round 1 went that way.

**Mitigation**: loop must checkpoint its own decisions (not just code changes) to memory at each cycle, so the next iteration can reload intent without re-reading the summary.

### 2. Self-withdrawn findings

In the PR #293 session, bugbot self-withdrew one finding mid-session ("the arithmetic is correct... Withdrawing the budget concern") — after the agent had already started analysing it. An autonomous loop that doesn't re-read the comment thread each cycle might:

- "Fix" a finding that bugbot later withdrew.
- Introduce a regression while closing a non-issue.
- Miss a `Resolved` / `Outdated` status marker on the comment.

**Mitigation**: per finding, agent must explain *why it's a bug* in its own words before fixing. If the explanation wobbles, skip and log.

### 3. False-positive handling

Some findings are legitimately "won't fix":
- Stylistic preferences (bugbot disagrees with project convention)
- Out-of-scope for the PR (pre-existing issue surfaced by diff proximity)
- Theoretically valid but economically not worth fixing (low-severity edge cases on code paths that can't hit production state)

An autonomous loop with no "skip" capability either churns forever (trying to close noise) or ships bad fixes. The loop needs an explicit *triage* step with three outcomes per finding: **fix**, **skip-with-justification**, **escalate-to-user**.

### 4. Test suite cost

- Targeted `make test-fresh ARGS="app.tests.ClassName"` → ~8s, safe to run every cycle.
- Broader regression (e.g. `app.tests`) → minutes, should run at end of loop, not per cycle.
- Full suite (per project CLAUDE.md: 20+ min for Teisutis) → **never** inside the loop.

Loop needs a "how wide to test" heuristic per finding:
- Finding touches ≤1 module → targeted test class only.
- Finding touches shared helper / mixin → run full module.
- Finding spans files → surface to user.

### 5. Commit hygiene

PR #293 accumulated 6 micro-commits for bugbot fixes. That's fine when a human is steering scope ("this is the only thing I want to change this round"), but autonomous loops tend to over-commit — one commit per finding, leading to noisy history.

Options:
- **Per-cycle commits** (current manual pattern) — readable history, but noisy.
- **Batch per bugbot-run trigger** — agent fixes all findings from one review pass, one commit per retrigger. Cleaner.
- **Squash at end** — let the loop make noisy commits, squash in a final step before handing back.

### 6. Stop conditions

"No new comments for N cycles" is insufficient — bugbot can take 3–5 minutes per review. Need:

- **Max wall-time** (e.g. 30 min total loop budget).
- **Max commits** (e.g. 5 fix commits before handing back to user).
- **No-progress detector** — if bugbot keeps finding the same category of issue after N fixes, something is systemically wrong; escalate.
- **User interrupt** — the loop must never block the user from breaking in.

## Architectural Options

### Option A: Full autonomous loop

Agent polls bugbot, fixes every actionable finding, retriggers, repeats until clean or budget exhausted.

- **Pros**: hands-off; maximises leverage of `ScheduleWakeup`.
- **Cons**: all five risks above; hard to bound blast radius when the agent goes wrong.
- **Verdict**: not recommended as a first implementation.

### Option B: Semi-autonomous — "fix-push-rerun automated, triage manual"

The existing `feedback_bugbot_workflow.md` pattern, codified as a skill. Agent presents findings → user approves per finding (or batch) → agent executes the fix/push/rerun/wait cycle autonomously until the next review lands → presents next batch.

- **Pros**: 80% of the value (removes the tedious wait-and-poll part); user keeps control over *what* gets fixed.
- **Cons**: still needs a human at the keyboard.
- **Verdict**: **recommended as v1**. ~50 lines of skill logic plus `ScheduleWakeup` polling.

### Option C: Policy-driven autonomous loop

Full autonomy behind a declarative policy:

```yaml
bugbot_autopilot:
  auto_fix_severities: [low, medium]
  escalate_severities: [high, critical]
  max_commits_per_session: 5
  max_wall_time_minutes: 30
  test_strategy: targeted
  commit_strategy: per-bugbot-run
  require_fix_explanation: true
```

- **Pros**: bounded blast radius; user can tune aggression per repo.
- **Cons**: complexity; policy tuning is its own problem.
- **Verdict**: good destination after v1 proves the happy path.

## Existing Building Blocks

- `tools/find_bugbot_comments.sh` — fetches `cursor[bot]` comments from a PR.
- `tools/bugbot.sh` — (spec-check needed) likely trigger wrapper.
- `~/.claude/memory/projects/-home-kestas-projects-teisutis/feedback_bugbot_workflow.md` — codifies the current fix/push/rerun loop.
- `ScheduleWakeup` — dynamic pacing with cache-aware delays.
- `commands/bugbot_comments` — user-invocable slash command that fetches and displays comments.

## Recommended Skill Shape (v1 = Option B)

```
commands/bugbot-loop.md
  ↳ Inputs: PR number (optional; default current branch)
  ↳ Phase 1 (triage): fetch comments, group by severity, present with per-finding action prompt
  ↳ Phase 2 (execute): for each approved fix:
      - apply edit
      - run targeted test
      - commit (fix(scope): description (bugbot PR #N))
  ↳ Phase 3 (poll): push, comment "bugbot run", ScheduleWakeup(180s)
  ↳ Phase 4 (wake): re-fetch; if new comments → back to Phase 1; if clean → report
  ↳ Stop conditions: max_commits=10, max_active_work=20min, max_idle_polls=20, or user interrupt
```

## Open Questions

1. **Where should the skill live?** `commands/bugbot-loop.md` (slash-invocable) vs `skills/bugbot-autopilot/` (richer, can include sub-templates per finding category).
2. **How should findings be persisted between wake cycles?** Memory file per PR? Scratch file in `~/.claude/memory/projects/<slug>/bugbot-<pr>.md`? Inline in the skill state?
3. **Triage UI.** Single interactive prompt per cycle vs bulk `TodoWrite` per-finding-as-task vs approval-file the user edits.
4. **Cross-project reuse.** Teisutis has `make test-fresh`; other projects have different test invocations. The skill needs a per-project hook (read from project CLAUDE.md / Makefile detection).

## Chosen Policy: Option B+ (2026-04-14)

After re-evaluation the user accepted **Option B with a narrow autonomy carve-out**:

### Autonomy ladder (per finding)

| Tier | Shape | Action |
|------|-------|--------|
| 1 — Auto-fix | Matches one of 8 codified patterns in `AGENT_bugbot.md`, ≤1 file, targeted test exists | Fix, test, commit (no prompt) |
| 2 — Approve-then-fix | Actionable but uncodified, OR touches shared helper | Present diff + justification, wait `yes` |
| 3 — Escalate | Cross-file, architectural, or bugbot self-withdrew | Skip finding, log it, continue cycle; surface in final hand-back (per-finding escalation, not whole-loop abort) |

### Hard bounds

- `max_commits_per_session = 10`
- `max_active_work_minutes = 20` — wall-time **excluding** `ScheduleWakeup` sleep. Bugbot review latency does not eat the budget (review can legitimately exceed 30 min on wide-touch PRs).
- `max_idle_polls = 20` — consecutive wakes with no new comment AND no new push.
- Per-finding written justification required before any Tier 1 or 2 fix.
- Commit strategy: batch per `bugbot run` cycle, not per finding.
- Test scope inside loop: targeted class only.
- No-progress detector: same finding category 2× post-fix → escalate.

### Worktree bootstrap (Phase 0)

If running inside a git worktree and `.env` missing but `.env.template` present: create `.env` with test-safe sentinels (`*_API_KEY=test-not-a-real-key`, `SECRET_KEY=test-<random>`). Documented as a narrow exception in global `CLAUDE.md` to the "never touch .env" guardrail. Never applies in the primary working tree.

### Deltas from original §6 stop conditions

- **Removed** `max_wall_time = 30min` — bugbot review latency on wide-touch PRs can exceed this; punishing the agent for bugbot's queue depth is the wrong signal.
- **Added** `max_active_work_minutes = 20` — bounds *agent* churn instead of total elapsed.
- **Added** `max_idle_polls = 20` — naturally scales (1–6 hours of patient waiting at 180–1200s pacing).

## Next Steps

1. ~~Decide Option A vs B vs C~~ — done: B+.
2. ~~Pick skill location~~ — `commands/bugbot-loop.md` (slash-invocable). Promote to `skills/` only if proven.
3. ~~Draft the skill frontmatter and execution template~~ — done.
4. **Dogfood** on a low-stakes PR before turning loose on production branches.
5. After ≥3 successful dogfood runs: revisit Option C (declarative policy YAML).

---

**Related Artefacts**:
- Memory: `feedback_bugbot_workflow.md` — current manual workflow
- Memory: `project_bugbot_watcher.md` — earlier untested `bugbot-watcher.sh` draft in `mind-vault/tools/`
- Tools: `mind-vault/tools/find_bugbot_comments.sh`, `mind-vault/tools/bugbot.sh`
- Command: `commands/bugbot_comments` (existing triage read-only command)
