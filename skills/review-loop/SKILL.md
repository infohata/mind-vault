---
name: review-loop
description: Drive a bounded-autonomy review-fix-rerun loop against one or more pluggable review engines (Cursor Bugbot, GitHub Copilot, Claude Code Review, Grok Build, future N-engines) on a PR. Triages findings into Tier 1 / 2 / 3, batches per-cycle fixes into single commits, retriggers engines after each push, tracks each engine through a review-state machine (NOT_TRIGGERED → TRIGGERED → RUNNING → DONE) read from its check-run status, treats an engine as clean only when DONE with zero active findings, and hands back to the user with a structured report. Engine-agnostic core; per-engine specifics live in references/engine-<name>.md per the adapter contract.
---
