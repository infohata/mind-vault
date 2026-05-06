# RULE_orchestrator-trash-collection

Orchestrator agents that arm `run_in_background` Bash watchers to poll external state (PR reviews, CI status, deploy progress, log lines) accumulate trash if those watchers aren't explicitly retired when superseded. The watchers self-clean eventually via their TIMEOUT, but for the window between supersede and timeout they double-poll, waste API quota, and occupy background-task slots. This rule defines the cleanup discipline.

## Hard Rules

1. **Explicit stop on supersede.** When arming a new background-poll watcher that supersedes a prior one (same purpose, different state target — e.g. polling next-cycle bugbot review after the current cycle landed), explicitly stop the prior watcher (`TaskStop` / kill / equivalent) BEFORE arming the next. Don't rely on the prior's TIMEOUT to self-clean — that wastes the polling-interval × cycle-count, and on a multi-cycle sprint that's hours of duplicate API calls.
2. **TIMEOUT bound is mandatory, not optional.** Every background-poll watcher MUST have an absolute TIMEOUT cap (not just a `while true; do … done` loop). The TIMEOUT is the upper-bound self-clean; explicit stop on supersede is the in-window cleanup discipline. Both are needed — one without the other is incomplete.
3. **`cd` inside the loop body, not before the watcher arms.** Watchers that wrap a tool with cwd-auto-detect behaviour (e.g. tools that resolve the GitHub repo from `git rev-parse --show-toplevel` of cwd) MUST `cd` into the correct working directory at the START of each iteration of the watcher's loop. Bash subshell `cd` does NOT persist between separate `run_in_background` invocations, and the orchestrator's outer cwd may have moved between when the watcher was authored and when it actually runs.
4. **Optional but recommended: session-end `tasks/` sweep.** At session-end (orchestrator-completion hook, or end of an unattended overnight batch), the orchestrator should sweep its task-output directory to drop spent files. Each file is small (~5-10 KB) but accumulates across long sessions — especially overnight batches that cycle through dozens of watchers.

## When This Applies

Any orchestrator using `run_in_background` Bash watchers for polling external-state changes — GitHub PR reviews, CI build status, deploy state, log lines, anything where the orchestrator runs through multiple state-supersede cycles within one session.

Specifically:

- `/sprint-auto` S3 + S6 + S11.10 + S13 bugbot loops (one watcher per cycle, ~18 cycles per batch in a typical overnight run).
- `/bugbot-loop` standalone — same pattern at smaller scale.
- Any custom orchestrator that does "wait for X to change" via repeated polling.

Does NOT apply to:

- One-shot `run_in_background` jobs that run a build, test suite, or deploy and return a single result. Those self-clean on completion.
- Foreground polling inside a single tool call. There's no superseding watcher to clean up.

## Failure Modes

**A. Hanging watchers wasting GitHub API quota.** Orchestrator arms watcher #1 polling PR review every 60s. State changes; orchestrator arms watcher #2 to poll the next state. Watcher #1 keeps polling until its 25-min TIMEOUT fires. For 25 minutes the orchestrator double-polls (effectively 30s cadence + duplicate API calls). Multiplied by 15+ cycles in a sprint-auto batch, that's hours of unnecessary GitHub API usage AND background-task slots occupied. Source: teisutis sprint-auto batch 2026-05-05T21-37-46Z — user surfaced "you left hanging shell waiting for test results" the next morning.

**B. Wrong-cwd watcher polling the wrong repo.** Tool `find_bugbot_comments.sh` auto-detects the GitHub repo via `git rev-parse --show-toplevel`. Orchestrator armed a watcher that ran the tool from a subshell where cwd had been reset to a different project's checkout. Result: 10+ minutes spent polling the wrong repo's PR for a clean signal that would never arrive. Source: same batch, mind-vault PR watcher initially polled the main project repo instead of mind-vault. Fix: explicit `cd /correct/path` at the top of the watcher's loop body.

**C. `/tmp` pollution.** 63 task-output files at ~280 KB total per single overnight session. Acceptable as forensic artefacts but accumulates if multiple long sessions land on the same machine without cleanup, and the per-session orchestrator state files start visually drowning out the meaningful artefacts when listing the dir.

## Concrete Supersede Pattern

```bash
# Wrong: arm watcher #2 without stopping #1
run_in_background watcher_a.sh   # polling state X
# ... state changes ...
run_in_background watcher_b.sh   # polling state Y; #1 still spinning

# Right: kill prior before arming next
TaskStop watcher_a_id
run_in_background watcher_b.sh   # only one watcher live
```

For the orchestrator's tooling: keep a single state variable `current_watcher_id`; before arming a new watcher, `TaskStop $current_watcher_id` (or whatever the platform's equivalent kill is). Update the variable atomically with the new id. The pattern generalises beyond bugbot polling — any "wait for X to change" loop in a multi-cycle orchestrator follows the same shape.

## Concrete cwd-Hygiene Pattern

```bash
# Wrong: rely on outer cwd
run_in_background <<EOF
while true; do
    output=\$(/path/to/auto-detect-tool 99)
    # ... processes output assuming the right repo ...
done
EOF

# Right: pin cwd inside the loop body
run_in_background <<EOF
while true; do
    cd <project-root>      # explicit; survives subshell boundary
    output=\$(/path/to/auto-detect-tool 99)
    # ...
done
EOF
```

The `cd` belongs INSIDE the loop body even if it looks redundant — the watcher may run for many iterations across cwd-changing events in the orchestrator's main loop, and the absolute `cd` at the top of each iteration is what makes the watcher self-contained.

## Optional `/tmp` Cleanup

```bash
# In session teardown / orchestrator-completion hook:
ls -t /tmp/claude-*/-*/tasks/*.output 2>/dev/null | tail -n +50 | xargs -r rm
# Drop all but the 50 most-recent task outputs.
```

This is cheap and prevents long-term `/tmp` creep on machines hosting many orchestrator sessions. The 50-file retention is arbitrary — pick a number that gives forensic headroom without unbounded growth.

## Relationship to Other Rules

- [`RULE_git-safety`](RULE_git-safety.md) — orchestrator commits + pushes happen on feature branches; trash-collection of watchers doesn't bypass the merge-to-protected-branch gate.
- [`RULE_parallel-worktree-docker`](RULE_parallel-worktree-docker.md) § "State-mutating chain trap" — related cwd-hygiene point about `cd "$WORKTREE_VAR" && docker compose down` falling through when the env var is unset. Same family of bug: cwd assumptions from the outer shell don't survive subshell boundaries, and the cure is the same — pin the path explicitly at the point of use.

## Provenance

Surfaced 2026-05-06 in teisutis sprint-auto batch 2026-05-05T21-37-46Z. User feedback: "you left hanging shell waiting for test results." The orchestrator left ~18 background watchers superseded but not explicitly stopped over the course of the night; each had a 25-min TIMEOUT self-bound, so they self-cleaned eventually, but the in-window double-polling wasted GitHub API and produced background-task noise.

---

**Last Updated**: 2026-05-06
