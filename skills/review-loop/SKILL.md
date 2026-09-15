---
name: review-loop
description: Drive a bounded-autonomy review-fix-rerun loop against one or more pluggable review engines (Cursor Bugbot, GitHub Copilot, Claude Code Review, Grok Build, future N-engines) on a PR. Triages findings into Tier 1 / 2 / 3, batches per-cycle fixes into single commits, retriggers engines after each push, tracks each engine through a review-state machine (NOT_TRIGGERED → TRIGGERED → RUNNING → DONE) read from its check-run status, treats an engine as clean only when DONE with zero active findings, and hands back to the user with a structured report. Engine-agnostic core; per-engine specifics live in references/engine-<name>.md per the adapter contract.
---

Drive a review-fix-rerun cycle on the given PR using one or more review engines. The orchestrator is engine-agnostic — all engine-specific work routes through adapters described in `references/engine-adapter-contract.md`.

**Inputs**:

- `PR_NUMBER` (optional; defaults to PR for current branch).
- `ENGINES` (one or more of: `bugbot`, `copilot`, `claude`, `grok`; defaults to `bugbot,copilot,claude,grok` — all engines whose adapter is present + retrigger tool is reachable. **Reachability caveat (A2):** `claude` / `grok` join the default set only where their action workflows (`claude-code-review.yml` / `grok-code-review.yml`) are installed; where absent, `find_*_comments.sh` emits `<ENGINE>_NOT_INSTALLED=true` and that engine **self-excludes from the default** so a bare `/review-loop` doesn't block to HUNG. An explicit `/review-loop <PR> claude` or `grok` still attempts it and degrades **loudly** — see [`references/engine-claude.md`](references/engine-claude.md) / [`references/engine-grok.md`](references/engine-grok.md) § Tool invocations.)

This skill is invoked via `commands/review-loop.md` — the single review entry point. Pass `ENGINES` as `bugbot`, `copilot`, `claude`, `grok`, or any subset (e.g. `bugbot,copilot,claude,grok`); single-engine runs are just a one-element list.
