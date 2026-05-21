# RULE_git-safety

Protected branches are `main` and the release branch (`production` or `deployment`, whichever the project uses). Everything else is a feature branch and is the agent's sandbox. The HITL gate is **merge to a protected branch**, nothing else.

Worked examples, recovery prose, the "which tip moves" disambiguation, and the canonical "please merge" response template live in [`references/RULE_git-safety-rationale.md`](references/RULE_git-safety-rationale.md). Load that file when adjudicating an edge case or when the user asks for the standard workflow.

## The Hard Rules

### 1. NEVER COMMIT TO MAIN

- Always work on feature branches: `git checkout -b feature/name origin/main`.
- Never `git checkout main` with intent to commit.
- If accidentally on main: `git stash`, create a feature branch, `git stash pop`.
- `main` is off limits for direct push, force-push, rewriting history, and direct merge.

### 2. NEVER MERGE OR PUSH INTO A PROTECTED BRANCH

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Direction matters — see the "which tip moves" disambiguation in the rationale doc.

**On protected branches the agent:**

- ❌ Never commits directly.
- ❌ Never runs `git merge <feature>` while checked out on a protected branch.
- ❌ Never runs `gh pr merge`, GitHub API merges, or browser-click merges.
- ❌ Never force-pushes, `git reset --hard`, or rewrites history.
- ✅ Creates PRs with `gh pr create` and hands the URL back to the human.
- ✅ Cleans up local feature branches **after** the human has merged upstream.

**Forward-sync IS allowed** — merging `main` *into* a feature branch (rebase, merge, pull --rebase). The feature branch's tip moves, `main` does not.

When asked to merge to a protected branch, decline and respond with the template in the rationale doc.

### 3. Feature branches — agent has normal commit authority

On any non-protected branch the agent commits freely. **No per-commit approval prompt.** The human reviews at the PR, not per-commit.

**Allowed without asking:** commit as work progresses; amend, squash, rebase interactively; reset, cherry-pick, stash, delete local feature branches; `git push --force-with-lease` on a feature branch the agent owns.

**Still forbidden (even on feature branches):**

- ❌ `--no-verify`, `--no-gpg-sign`, or any flag that bypasses hooks or signing, unless the user explicitly asks.
- ❌ Plain `git push --force` — always use `--force-with-lease`.
- ❌ Force-pushing to a branch with an open PR *without informing the human first* — it invalidates existing review threads.
- ❌ Deleting or resetting a branch the agent doesn't recognise — it may be someone else's in-progress work.
- ❌ Committing files that likely contain secrets (`.env`, `credentials.json`, private keys). Warn the user if a commit includes any.
