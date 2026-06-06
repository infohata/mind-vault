---
description: Multi-engine review-fix-rerun loop (Cursor Bugbot + GitHub Copilot + Claude Code Review, or any subset) with bounded-autonomy policy
agent: general
---

# /review-loop

Drive a review-fix-rerun cycle on the given PR using one or more review engines concurrently.

**Inputs**:

- `PR_NUMBER` (optional; defaults to PR for the current branch)
- `ENGINES` (optional; defaults to all engines with available adapters + tool scripts — `bugbot,copilot,claude`. **Reachability caveat:** `claude` is in the default set only on repos where its action workflow `claude-code-review.yml` is installed; where absent it self-excludes from the default so a bare `/review-loop` doesn't hang. An explicit `claude` still attempts it and degrades loudly.)

**Usage**:

```
/review-loop                        # current branch's PR, all available engines
/review-loop 129                    # PR #129, all available engines
/review-loop 129 bugbot             # PR #129, bugbot only
/review-loop 129 claude             # PR #129, Claude Code Review only (push-triggered)
/review-loop 129 bugbot,copilot     # PR #129, two engines (multi-engine sync mode)
/review-loop 129 bugbot,copilot,claude  # PR #129, all three engines (multi-engine sync mode)
```

When `|ENGINES| > 1`, the loop runs in **multi-engine sync mode** — each cycle waits for the slowest engine's verdict before batching fixes and retriggering all engines. See [`skills/review-loop/references/multi-engine-sync.md`](../skills/review-loop/references/multi-engine-sync.md) for the synchronisation contract, trade-off escape hatches, and asymmetric-clearance hand-back semantics.

## Behaviour

This command invokes [`skills/review-loop/SKILL.md`](../skills/review-loop/SKILL.md) with the given engine list. The skill enforces:

- `max_commits_per_session = 20`
- `max_active_work_minutes = 240`
- `max_idle_polls = 20`
- Retriggers fire only after a fix push or from the zero-activity bootstrap — never while an engine is RUNNING, so no inter-retrigger interval exists. **Every engine — claude included — is retriggered in Phase 3** after a fix push: claude's `synchronize` auto-run skip-no-ops once it has already reviewed the PR, so the explicit `claude_retrigger.sh` is the only thing that produces a fresh verdict on the fix (no double-run — the auto-run skips). The lone exception is a still-in-flight **first** claude review (the Claude-stalled escape hatch): claude hasn't posted yet, so the push's auto-run carries its first review and the explicit retrigger is withheld. See [`multi-engine-sync.md`](../skills/review-loop/references/multi-engine-sync.md) § Retrigger discipline.
- Feature-branch sandbox (per `RULE_git-safety`); never main, never force-push to protected.

## Engine selection

The `ENGINES` argument is a comma-separated list. Currently supported:

- `bugbot` — Cursor Bugbot (`tools/find_bugbot_comments.sh`, `tools/bugbot_retrigger.sh`)
- `copilot` — GitHub Copilot (`tools/find_copilot_comments.sh`, `tools/copilot_retrigger.sh`)
- `claude` — Claude Code Review, the `claude-code-action@v1` + `code-review` plugin (`tools/find_claude_comments.sh`, `tools/claude_retrigger.sh`). **Push-triggered for the FIRST review only** — the action auto-runs on push, but the `code-review` plugin **skip-no-ops once claude has already reviewed the PR**, so Phase 3 **does** fire `claude_retrigger.sh` after a fix push *once claude has posted its first review* to force a fresh verdict (no double-run — the auto-run skips). If that first review is still in-flight, the push's auto-run carries it instead and the explicit retrigger is withheld. NOT Anthropic's managed Code Review App — see [`skills/review-loop/references/engine-claude.md`](../skills/review-loop/references/engine-claude.md) § A7.

To add a new engine, see [`skills/review-loop/references/engine-adapter-contract.md`](../skills/review-loop/references/engine-adapter-contract.md) § Adding a new engine.

## Hand-back

The loop hands back to the user with:

- Per-engine verdict (CLEAN / HUNG / ERRORED / STILL_FINDING).
- Asymmetric-clearance warning if one engine cleared and another didn't.
- Tier 3 escalations (need human decision).
- Pending retriggers not fired (if budget exhaustion prevented them).
- PR URL.

The loop never merges. The merge to a protected branch is always the human's decision.
