# Watcher hygiene — orchestrator trash-collection for `run_in_background` watchers

Orchestrator agents that arm `run_in_background` Bash watchers to poll external state (PR reviews, CI status, deploy progress, log lines) accumulate trash if those watchers aren't explicitly retired when superseded or when their reason-to-poll has resolved. Without explicit cleanup, watchers can hang indefinitely — multi-hour residual processes, double-polling APIs, and occupying background-task slots.

**TIMEOUTs are NOT a substitute for explicit cleanup.** Per project convention, watchers and test-running shells must NOT carry hard wall-clock timeouts — large test suites legitimately take 30+ minutes, and a TIMEOUT cap that's small enough to be useful for trash-collection is small enough to kill productive work. The cleanup mechanism is **explicit garbage collection by the orchestrator**, not a self-bound on each watcher.

## Hard Rules

1. **Explicit stop on supersede.** When arming a new background-poll watcher that supersedes a prior one (same purpose, different state target — e.g. polling the next-cycle review after the current cycle landed), `TaskStop` (or kill / equivalent) the prior watcher BEFORE arming the next. The orchestrator OWNS its watchers; it MUST track them and retire them explicitly.

2. **Explicit stop when the reason-to-poll resolves.** When the watcher's terminal condition fires (clean signal, findings detected, supersede event), the orchestrator MUST stop the watcher rather than relying on it to "exit naturally". An exit condition with a subtle bug (see Failure Mode D below) can hang indefinitely; an explicit stop is bug-resistant.

3. **No wall-clock TIMEOUTs on watcher loops.** A `while $(elapsed -lt 1500); do …; done` cap is forbidden by project convention because it would also kill legitimate long-running test invocations. The watcher's lifetime is bounded by the orchestrator's explicit-stop discipline (Hard Rules 1 + 2), not by a timer.

4. **`cd` inside the loop body, not before the watcher arms.** Watchers wrapping a tool with cwd-auto-detect behaviour (e.g. tools that resolve the GitHub repo from `git rev-parse --show-toplevel` of cwd) MUST `cd` into the correct working directory at the START of each iteration of the watcher's loop. Bash subshell `cd` does NOT persist between separate `run_in_background` invocations, and the orchestrator's outer cwd may have moved between when the watcher was authored and when it actually runs.

5. **Avoid self-matching exit conditions in `pgrep` / process-table watchers.** A `until ! pgrep -f '<pattern>' >/dev/null; do sleep 5; done` loop that uses `pgrep -f` (full command-line match) WILL match the watcher's own process — because the watcher's bash command line CONTAINS the pattern as an argument. The until-loop never exits because it sees itself as a still-running match. Workarounds: (a) use `pgrep -x` (exact basename) when the target is a single program; (b) use `pgrep -f '<pattern>' | grep -v $$` to exclude the current shell PID; (c) prefer Monitor / file-tail watchers over `pgrep` polling for "is the other process still running" questions.

6. **Optional but recommended: session-end `tasks/` sweep.** At session-end (orchestrator-completion hook, or end of an unattended overnight batch), the orchestrator should sweep its task-output directory to drop spent files. Each file is small (~5-10 KB) but accumulates across long sessions — especially overnight batches that cycle through dozens of watchers.

## When This Applies

Any orchestrator using `run_in_background` Bash watchers for polling external-state changes — GitHub PR reviews, CI build status, deploy state, log lines, anything where the orchestrator runs through multiple state-supersede cycles within one session.

Specifically:

- `/sprint-auto` S3 + S6 + S11.10 + S13 review loops (one watcher per cycle, ~18 cycles per batch in a typical overnight run).
- `/<engine>-loop` standalone — same pattern at smaller scale.
- Any custom orchestrator that does "wait for X to change" via repeated polling.

Does NOT apply to:

- One-shot `run_in_background` jobs that run a build, test suite, or deploy and return a single result. Those self-clean on completion.
- Foreground polling inside a single tool call. There's no superseding watcher to clean up.

## Failure Modes

**A. Hanging watchers wasting GitHub API quota.** Orchestrator arms watcher #1 polling PR review every 60s. State changes; orchestrator arms watcher #2 to poll the next state. If watcher #1 isn't explicitly killed it keeps polling indefinitely (no timeout per Hard Rule 3). For each unkilled watcher, the orchestrator double-polls (effectively shorter cadence + duplicate API calls). Multiplied by 15+ cycles in a sprint-auto batch, the per-cycle waste compounds.

**B. Wrong-cwd watcher polling the wrong repo.** The engine-specific find-comments helpers (`find_bugbot_comments.sh` / `find_copilot_comments.sh`) auto-detect the GitHub repo via `git rev-parse --show-toplevel`. Orchestrator armed a watcher that ran the tool from a subshell where cwd had been reset to a different project's checkout. Result: 10+ minutes spent polling the wrong repo's PR for a clean signal that would never arrive. Fix: explicit `cd <project-root>` at the top of the watcher's loop body (Hard Rule 4).

**C. `/tmp` pollution.** 63 task-output files at ~280 KB total per single overnight session. Acceptable as forensic artefacts but accumulates if multiple long sessions land on the same machine without cleanup, and the per-session orchestrator state files start visually drowning out the meaningful artefacts when listing the dir.

**D. Self-matching `pgrep -f` exit condition — multi-hour residual.** This is the actual failure that drove this rule. Orchestrator armed an `until ! pgrep -f 'compose exec.*pytest.*<app>/tests' >/dev/null; do sleep 5; done` watcher to detect when a backgrounded `make test` invocation finished. The watcher's own bash command line contains the literal string `compose exec.*pytest.*<app>/tests` (the watcher's `pgrep -f` argument is part of `ps aux` output). `pgrep -f` matches the watcher's own process; the until-loop's exit condition (`! pgrep ...` becomes truthy) never becomes truthy because pgrep always sees its own caller. The watcher hung for **5 hours 45 minutes** before the user surfaced it the next morning. User feedback: "you left hanging shell waiting for test results. that shell is running soon 5h44min so timeout is definitely not working. and we have a rule NOT to setup timeouts because they might break large test suite prematurely. all good, just need effective garbage collection." Fix: per Hard Rule 5, avoid `pgrep -f` for self-referential checks; or per Hard Rule 2, explicitly kill the watcher when its reason-to-poll has resolved (don't rely on the exit condition firing correctly).

## Concrete Supersede Pattern

```bash
# Wrong: arm watcher #2 without stopping #1
run_in_background watcher_a.sh   # polling state X
# ... state changes ...
run_in_background watcher_b.sh   # polling state Y; #1 still spinning forever (no timeout per Hard Rule 3)

# Right: kill prior before arming next
TaskStop watcher_a_id
run_in_background watcher_b.sh   # only one watcher live
```

For the orchestrator's tooling: keep a single state variable `current_watcher_id`; before arming a new watcher, `TaskStop $current_watcher_id` (or whatever the platform's equivalent kill is). Update the variable atomically with the new id. The pattern generalises beyond review polling — any "wait for X to change" loop in a multi-cycle orchestrator follows the same shape.

When the watcher's terminal condition fires, the orchestrator should ALSO `TaskStop` it as a belt-and-suspenders against bugs in the exit condition itself (Hard Rule 2). Even when the loop is well-formed and would exit cleanly, the explicit stop is cheap insurance against the Failure Mode D class of bug where a future edit introduces a self-match.

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

## Concrete `pgrep -f` Self-Match Avoidance

```bash
# Wrong: self-matches because the watcher's own argv contains the pattern
until ! pgrep -f 'compose exec.*pytest.*<app>/tests' >/dev/null; do sleep 5; done

# Right (option 1): exclude the watcher's own PID
until ! pgrep -f 'compose exec.*pytest.*<app>/tests' | grep -v "^$$$" >/dev/null; do sleep 5; done

# Right (option 2): match by basename only (no -f)
until ! pgrep -x pytest >/dev/null; do sleep 5; done

# Better (option 3): don't poll process-table at all; tail the output file
# the backgrounded job is writing to, OR use the orchestrator's task-completion
# notification mechanism (which fires on actual exit, not pgrep state).
```

In a Claude Code orchestrator: prefer awaiting the `task-notification` event for the backgrounded job over polling `pgrep`. The notification fires reliably on exit and doesn't require a separate watcher process at all.

## Optional `/tmp` Cleanup

```bash
# In session teardown / orchestrator-completion hook:
ls -t /tmp/claude-*/-*/tasks/*.output 2>/dev/null | tail -n +50 | xargs -r rm
# Drop all but the 50 most-recent task outputs.
```

This is cheap and prevents long-term `/tmp` creep on machines hosting many orchestrator sessions. The 50-file retention is arbitrary — pick a number that gives forensic headroom without unbounded growth.

## Relationship to Other Rules

- [`RULE_git-safety`](../../../rules/RULE_git-safety.md) — orchestrator commits + pushes happen on feature branches; trash-collection of watchers doesn't bypass the merge-to-protected-branch gate.
- [`PARALLEL_WORKTREE_DOCKER`](../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md) § "State-mutating chain trap" — related cwd-hygiene point about `cd "$WORKTREE_VAR" && docker compose down` falling through when the env var is unset. Same family of bug: cwd assumptions from the outer shell don't survive subshell boundaries, and the cure is the same — pin the path explicitly at the point of use.

## Provenance

Surfaced 2026-05-06 in a sprint-auto batch, refined twice the same morning:

1. Initial user feedback: "you left hanging shell waiting for test results."
2. First-pass rule (this file's earlier version) prescribed a TIMEOUT bound on every watcher as a self-clean upper limit. User correction: "that shell is running soon 5h44min so timeout is definitely not working. and we have a rule NOT to setup timeouts because they might break large test suite prematurely. all good, just need effective garbage collection."

The first-pass rule was wrong on two counts: (a) the hanging watcher had no TIMEOUT — it used a `until ! pgrep -f …` exit condition that self-matched and never exited (Failure Mode D); (b) project convention forbids wall-clock TIMEOUTs on watchers/test-running shells because they break legitimate long test suites. The revised rule (this version) drops the TIMEOUT prescription and makes explicit-stop-by-orchestrator the sole cleanup mechanism, with self-match avoidance added as a sibling failure mode.
