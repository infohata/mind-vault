# RULE_git-safety — Rationale, Workflow Examples, Recovery

Companion to [`../RULE_git-safety.md`](../RULE_git-safety.md). The parent rule holds the imperative core; this file holds the worked examples, recovery prose, and the "why".

## Standard Branch Workflow

```bash
# 1. Create feature branch from main
git checkout -b feature/my-feature origin/main

# 2. Make changes, stage them
git add <files>

# 3. Commit — no approval prompt needed on a feature branch
git commit -m "type(scope): description"

# 4. Push with upstream tracking
git push -u origin feature/my-feature

# 5. Create PR
gh pr create --title "..." --body "..."

# 6. (HITL gate) Human reviews and merges on GitHub

# 7. After merge — safe cleanup
# IMPORTANT: If Docker containers are running, stop first.
# Checking out stale branches with live containers risks schema/migration drift.
docker compose ps
# If running → docker compose down first
git checkout main
git pull
git branch -d feature/my-feature
```

## Commit Message Format

```text
type(scope): brief description (≤72 chars)

Optional explanation of why, wrapped at 72.
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `style`, `chore`, `test`, `build`, `ci`, `perf`.

## "Please merge to main" — canonical response template

```text
I've created/updated PR #X at [URL].

To merge:
  1. Review the changes on GitHub
  2. Click the green 'Merge pull request' button
  3. Confirm the merge

Let me know once it's merged and I'll handle local cleanup.
```

## Recovery — What If I Forget?

**If about to commit to a protected branch:**

- Stop immediately.
- `git stash` if there are pending changes.
- Create a feature branch from `main` (`git checkout -b feature/x origin/main`).
- `git stash pop` and resume.

**If already committed to a protected branch:**

- You violated rule 1.
- Do NOT push.
- Tell the user immediately; let them decide whether to `git reset` or cherry-pick the commit to a feature branch.

**If about to merge/force-push into a protected branch:**

- Stop. This is rule 2.
- Open a PR instead and hand the URL to the human.

## Why This Matters

- The human controls what enters production (main / deployment).
- Feature branches are the agent's sandbox — freedom to iterate without constant check-ins.
- The PR is the one HITL gate that matters.
- Clear accountability: the merge to a protected branch is the point of no return, and it's always human-initiated.

## The "which tip moves" disambiguation

Forward-sync (merging `main` *into* a feature branch) is **allowed** — the feature branch's tip moves, `main` does not. Examples:

- ✅ `git merge origin/main` while on a feature branch.
- ✅ `git pull --rebase origin main` on a feature branch.
- ✅ `git rebase origin/main` on a feature branch.

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Before any merge/rebase ask: *which branch's tip is about to move?* If the answer is a protected branch, abort.
