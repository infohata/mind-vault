---
description: Overnight unattended orchestrator — run a curated list of opt-in IDEAs through /plan → /work → PR creation in per-IDEA worktrees. Stops at the HITL merge boundary.
agent: general
---

# sprint-auto

Invoke the `sprint-auto` skill to run the IDEA list in `$ARGUMENTS` through `/plan → /work → gh pr create`, one at a time, each in its own git worktree with its own docker-compose stack.

**Invocation shapes**:

- `/sprint-auto IDEA-050 IDEA-051 IDEA-052` — by number
- `/sprint-auto sync-retry modal-dismiss` — by slug
- `/sprint-auto IDEA-050 --budget-minutes=180` — with per-batch wall-clock cap
- `/sprint-auto IDEA-050 --include-high` — one-off override for a `priority: high` IDEA

**What happens**:

1. Preflight: primary tree clean, on `main`, docker daemon up, every IDEA has `auto_safe: true` + `auto_safe_reason` in frontmatter, body thick enough to skip `/plan`'s thin-input bootstrap.
2. For each IDEA: create `../<project>-auto-<slug>` worktree, run `tools/sprint-auto-bootstrap.sh`, invoke `/plan`, invoke `/work`, capture PR URL.
3. Write per-IDEA log + batch summary. Leave worktrees + docker stacks up for morning review.
4. **Never merges**. HITL gate per `RULE_git-safety` stays intact — the human merges PRs in the morning.

**Preflight gates** (any fail → abort or drop the offending IDEA from the batch):

- `auto_safe: true` AND `auto_safe_reason: "..."` in frontmatter (belt-and-suspenders opt-in)
- Body has ≥3 substantive paragraphs (otherwise `/plan` would block on questions)
- `priority` is not `high` (unless `--include-high` explicitly passed)
- `status: idea` (not already in-progress / complete / superseded)
- No dependency on an IDEA that is not `status: complete`
- No sensitive-path hits (`.env*`, base `docker-compose.yml`, `.github/workflows/`, destructive migrations, auth middleware) unless `sensitive_paths_cleared: true` + reason in frontmatter

**On failure**, the failing worktree + branch are preserved so the human can `cd` in and diagnose. The cleanup one-liner is always written into the auto-run log.

See `skills/sprint-auto/SKILL.md` for the full pattern, `references/safety-gates.md` for the opt-in criteria, and `references/worktree-lifecycle.md` for the project-local bootstrap-script contract.
