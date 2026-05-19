# RULE_git-safety

## The Hard Rules

Protected branches are `main` and the release branch (`production` or `deployment`, whichever the project uses). Everything else is a feature branch and is the agent's sandbox.

The HITL gate is **merge to a protected branch**, nothing else.

### 1. NEVER COMMIT TO MAIN

- Always work on feature branches: `git checkout -b feature/name origin/main`.
- Never `git checkout main` with intent to commit.
- If accidentally on main: `git stash`, create a feature branch, `git stash pop`.
- `main` is off limits for direct push, force-push, rewriting history, and direct merge.

### 2. NEVER MERGE OR PUSH INTO A PROTECTED BRANCH

The forbidden operation is writing to a protected branch, not the `git merge` command itself. Direction matters.

**On protected branches the agent:**

- ❌ Never commits directly.
- ❌ Never runs `git merge <feature>` while checked out on a protected branch.
- ❌ Never runs `gh pr merge`, GitHub API merges, or browser-click merges.
- ❌ Never force-pushes, `git reset --hard`, or rewrites history.
- ✅ Creates PRs with `gh pr create` and hands the URL back to the human.
- ✅ Cleans up local feature branches **after** the human has merged upstream.

**Forward-sync IS allowed — merging `main` *into* a feature branch:**

- ✅ `git merge origin/main` while on a feature branch.
- ✅ `git pull --rebase origin main` on a feature branch.
- ✅ `git rebase origin/main` on a feature branch (the branch's tip moves, `main` does not).

**The distinguishing question** before any merge/rebase: *which branch's tip is about to move?* If the answer is a protected branch, abort. If the answer is the current feature branch, it's safe.

**How to respond when asked to merge to main/production:**

```text
I've created/updated PR #X at [URL].

To merge:
  1. Review the changes on GitHub
  2. Click the green 'Merge pull request' button
  3. Confirm the merge

Let me know once it's merged and I'll handle local cleanup.
```

### 3. Feature branches — agent has normal commit authority

On any non-protected branch the agent commits freely. **No per-commit approval prompt.** The human reviews at the PR, not per-commit.

**Allowed without asking:**

- ✅ Commit as work progresses.
- ✅ Amend, squash, rebase interactively.
- ✅ Reset, cherry-pick, stash, delete local feature branches.
- ✅ `git push --force-with-lease` on a feature branch the agent owns.

**Still forbidden (even on feature branches):**

- ❌ `--no-verify`, `--no-gpg-sign`, or any flag that bypasses hooks or signing, unless the user explicitly asks.
- ❌ Plain `git push --force` — always use `--force-with-lease` so a collaborator's newer commits are protected.
- ❌ Force-pushing to a branch with an open PR *without informing the human first* — it invalidates existing review threads.
- ❌ Deleting or resetting a branch the agent doesn't recognise — it may be someone else's in-progress work.
- ❌ Committing files that likely contain secrets (`.env`, `credentials.json`, private keys). Warn the user if a commit includes any.

## Branch Workflow

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

## What If I Forget?

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

## The Genesis-Commit Chicken-and-Egg

A brand-new GitHub repo with zero commits has no `main` to PR against. Pushing the first feature branch makes GitHub auto-promote *that branch* to default, leaving no `main` ref at all. The agent literally cannot follow the "feature branch → PR → human merges" workflow because the PR target doesn't exist.

This is the only exception to rule 1 that has a defensible workflow path. There are three ways through, in order of preference:

### Path A — Human seeds main via the GitHub web UI (preferred)

The user creates `main` manually:

1. Push the agent's feature branch first (`git push -u origin feature/initial-scaffold`). GitHub auto-sets it as default.
2. On the GitHub repo page, click "creating a new file" or use the web UI to add a README / LICENSE / `.gitkeep`. This creates a `main` branch on the remote with an initial commit.
3. In repo Settings → Branches, set `main` as the default branch.
4. Agent rebases the feature branch onto `origin/main` and opens the PR normally.

Zero rule violation by the agent. Highest ceremony but cleanest history.

### Path B — User explicitly authorises a one-time genesis commit on main

The user grants the exception with explicit language: *"yes, this one commit on main is the genesis exception."* The agent then:

1. Commits the scaffold (or just a `.gitkeep` / `README.md`) directly on local `main`.
2. Pushes `main` to origin.
3. From here on, the strict rule applies — no further direct commits to `main`.

The explicit user grant covers exactly one commit. Subsequent work goes back to feature branches.

### Path C — Feature branch becomes main via GitHub rename

If the agent has already pushed a feature branch to an empty repo (and GitHub auto-promoted it to default), the user can rename it to `main` via the GitHub web UI or API (`gh api -X POST repos/<owner>/<repo>/branches/<branch>/rename`). The single commit becomes `main`'s genesis. The agent then starts strict feature-branch workflow for the next change.

### What the agent should NOT do

- ❌ Commit directly to local `main` without explicit user direction (the classifier should block; if it doesn't, refuse anyway).
- ❌ Push the feature branch's SHA to `origin/main` (`git push origin feature/x:main`) — this is a write to a protected ref, still rule 2.
- ❌ Use `gh api` to create the `main` ref pointing at the feature branch's commit — same rule, different syntax.
- ❌ Open a PR with `--base main` against a non-existent main ref and hope GitHub figures it out — `gh` rejects with "No commits between main and feature/x".

### Detection — when does this rule apply

Probe at the start of any "initialise this repo" / "first commit" task:

```bash
gh repo view <owner>/<repo> --json defaultBranchRef,isEmpty
# {"defaultBranchRef":{"name":""},"isEmpty":true}  ← chicken-and-egg territory
```

If `isEmpty: true` and `defaultBranchRef.name: ""`, the standard workflow doesn't apply. Surface the three paths to the user; let them choose.

## Why This Matters

- The human controls what enters production (main / deployment).
- Feature branches are the agent's sandbox — freedom to iterate without constant check-ins.
- The PR is the one HITL gate that matters.
- Clear accountability: the merge to a protected branch is the point of no return, and it's always human-initiated.

**Last Updated**: 2026-05-19 — added "The Genesis-Commit Chicken-and-Egg" section covering empty-repo bootstrap. Promoted from `tasker` IDEA-001 (the first IDEA of a new project hit exactly this pattern — see [`tasker/docs/archive/2026-05-DEVELOPMENT_LOG.md`](https://github.com/sarunazs/tasker)).
