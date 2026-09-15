---
name: review-loop
description: Drive a bounded-autonomy review-fix-rerun loop against one or more pluggable review engines (Cursor Bugbot, GitHub Copilot, Claude Code Review, Grok Build, future N-engines) on a PR.
---

**Inputs**:

- `PR_NUMBER` (optional; defaults to PR for current branch).
- `ENGINES` (one or more of: `bugbot`, `copilot`, `claude`, `grok`; defaults to `bugbot,copilot,claude,grok`).

See references/engine-grok.md and docs/GROK_BUILD.md. Full skill body must be restored from SKILL_TO_PUSH.md (md5 634f3b21c52dd2d248c3a3875eb68c9c).
