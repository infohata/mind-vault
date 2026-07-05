# RULE_git-safety

Protected branches are `main` and the release branch (`production` or `deployment`, whichever the project uses). Everything else is a feature branch and is the agent's sandbox. The HITL gate is **merge to a protected branch**, nothing else.

Worked examples, recovery prose, the full standard branch workflow, and commit-message format live in [`../docs/rules/RULE_git-safety-rationale.md`](../docs/rules/RULE_git-safety-rationale.md). Load that file when adjudicating an edge case or when the user asks for the full workflow.

## The Hard Rules

### 1. NEVER COMMIT TO MAIN

- Always work on feature branches: `git checkout -b feature/name origin/main`.
- Never `git checkout main` with intent to commit.
- If accidentally on main: `git stash`, create a feature branch, `git stash pop`.
- `main` is off limits for direct push, force-push, rewriting history, and direct merge.

### 2. NEVER MERGE OR PUSH INTO A PROTECTED BRANCH

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Before any merge/rebase ask: *which branch's tip is about to move?* If the answer is a protected branch, abort.

**On protected branches the agent:**

- ❌ Never commits directly.
- ❌ Never runs `git merge <feature>` while checked out on a protected branch.
- ❌ Never runs `gh pr merge`, GitHub API merges, or browser-click merges.
- ❌ Never force-pushes, `git reset --hard`, or rewrites history.
- ✅ Creates PRs with `gh pr create` and hands the URL back to the human.
- ✅ Cleans up local feature branches **after** the human has merged upstream.

**Forward-sync IS allowed** — feature-branch tip moves, protected tip doesn't:

- ✅ `git merge origin/main` while on a feature branch.
- ✅ `git pull --rebase origin main` on a feature branch.
- ✅ `git rebase origin/main` on a feature branch.

When asked to merge to a protected branch, decline with this template:

```text
I've created/updated PR #X at [URL].

To merge:
  1. Review the changes on GitHub
  2. Click the green 'Merge pull request' button
  3. Confirm the merge

Let me know once it's merged and I'll handle local cleanup.
```

**Being asked is not authorization.** A user saying "merge" does not lift Hard Rule 2 — protected-branch merge is a *human action*, so hand back the button (above). The one exception is the deliberate break-glass in the enforcement hook below (`GIT_SAFETY_ALLOW=1`), which the agent never adds on its own.

**Structural enforcement (backstop for this rule).** This rule is behavioural context and can be rationalised away exactly when it matters (real incident: an agent merged to protected `main` with the rule loaded, reading a user "merge" as license). Mind-vault ships a `PreToolUse(Bash)` hook — [`hooks/block-protected-branch-writes.sh`](../hooks/block-protected-branch-writes.sh), wired in [`hooks/hooks.json`](../hooks/hooks.json) — that **denies** `gh pr merge`, API merges, and direct/force pushes to a protected branch at the tool layer, so a lapse can't move a protected tip. Forward-sync, feature-branch pushes, and `gh pr create` pass through. Symlink-channel installs register it by hand in `~/.claude/settings.json`. The *why* (behavioural rules need structural backstops for irreversible ops) is in [`../docs/rules/RULE_git-safety-rationale.md`](../docs/rules/RULE_git-safety-rationale.md).

### 3. Feature branches — agent has normal commit authority

On any non-protected branch the agent commits freely. **No per-commit approval prompt.** The human reviews at the PR, not per-commit.

**Allowed without asking:** commit as work progresses; amend, squash, rebase interactively; reset, cherry-pick, stash, delete local feature branches; `git push --force-with-lease` on a feature branch the agent owns.

**Still forbidden (even on feature branches):**

- ❌ `--no-verify`, `--no-gpg-sign`, or any flag that bypasses hooks or signing, unless the user explicitly asks.
- ❌ Plain `git push --force` — always use `--force-with-lease`.
- ❌ Force-pushing to a branch with an open PR *without informing the human first* — it invalidates existing review threads.
- ❌ Deleting or resetting a branch the agent doesn't recognise — it may be someone else's in-progress work.
- ❌ Committing files that likely contain secrets (`.env`, `credentials.json`, private keys). Warn the user if a commit includes any.
