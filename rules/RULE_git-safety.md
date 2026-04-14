# RULE_git-safety

## The Hard Rules

### 1. NEVER COMMIT TO MAIN
- Always work on feature branches: `git checkout -b feature/name origin/main`
- Never `git checkout main` until ready to create new branch
- If accidentally on main: stash, create branch, pop stash

### 2. NEVER COMMIT WITHOUT APPROVAL
**BEFORE every `git commit`:**
1. STOP
2. Run `git diff --cached`
3. Show user the diff
4. Show user the commit message
5. Ask: "Should I commit?"
6. Wait for "yes" in THIS response
7. If no "yes" → DO NOT COMMIT

**Previous approval does NOT count:**
- Each commit = fresh approval
- "Commit when ready" = still ask when ready
- Approval from X messages ago = expired (even if X=1)

**ONLY exceptions:**

- User says "yes, commit" or "go ahead" in the CURRENT response.
- **Autonomous workflows with pre-granted commit authority** — specifically the `/bugbot-loop` workflow (see `commands/bugbot-loop.md`). Invocation of the loop is session-level approval; Tier 1 auto-fix commits proceed without per-cycle prompts. Tier 2 still requires per-finding direction approval. All other guardrails (never merge *into* main, never force-push, never `--no-verify`) remain absolute.

### 3. NEVER MERGE *INTO* MAIN
The forbidden operation is writing to `main`, not the `git merge` command itself. Direction matters.

**Agent NEVER merges into the main (or any protected) branch:**
- ❌ NEVER run `git merge <feature>` while on `main`
- ❌ NEVER run `gh pr merge` (any PR to main)
- ❌ NEVER use GitHub API to merge PRs
- ❌ NEVER click merge buttons (if browser automation available)
- ❌ Even if user says "merge" or "click the green button" — DON'T DO IT

**Forward-sync IS allowed — merging `main` *into* a feature branch:**
- ✅ `git merge origin/main` while on a feature branch — pulls upstream work into the branch
- ✅ `git pull --rebase origin main` on a feature branch — equivalent effect via rebase
- ✅ `git rebase origin/main` on a feature branch (the branch is the one being rewritten, not `main`)

The distinguishing question before any merge/rebase: *which branch's tip is about to move?* If the answer is `main` (or another protected branch), abort. If the answer is the current feature branch, it's safe.

**What agents DO:**
- ✅ Create feature branches
- ✅ Commit changes (with approval)
- ✅ Push branches
- ✅ Forward-sync feature branches from `main` via merge or rebase
- ✅ Create PRs with `gh pr create`
- ✅ Provide PR URL for user to review and merge

**After user merges on GitHub:**
- ✅ Agent can clean up local branches (`git branch -d`)
- ✅ Agent can pull latest main (`git pull`)

**How to respond when asked to merge:**
```
"I've created/updated PR #X at [URL].

To merge this PR:
1. Review the changes on GitHub
2. Click the green 'Merge pull request' button
3. Confirm the merge

Let me know when you've merged it and I can help with cleanup."
```

**Why this rule exists:**
- Merging to main is a critical operation
- User should review PR on GitHub before merging
- Prevents accidental merges of untested code
- Maintains clear human decision point for production changes

## Branch Workflow

```bash
# 1. Create feature branch from main
git checkout -b feature/my-feature origin/main

# 2. Make changes, stage them
git add <files>

# 3. STOP - Show diff and ask approval
git diff --cached
# → Show to user, ask approval, wait for "yes"

# 4. Commit (only after approval)
git commit -m "type(scope): description"

# 5. Push with upstream tracking
git push -u origin feature/my-feature

# 6. Create PR (if gh available)
gh pr create --title "..." --body "..."

# 7. User merges on GitHub

# 8. After merge - safe cleanup
# IMPORTANT: If Docker containers are running, STOP
# Never checkout stale branches when containers are active
docker compose ps  # Check if containers running
# If running → docker compose down first
# Then:
git checkout main
git pull
git branch -d feature/my-feature
```

## Commit Message Format

```
type(scope): brief description (≤72 chars)

Optional explanation of why.
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `style`, `chore`

## What If I Forget?

**If you catch yourself about to commit without showing diff:**
- STOP immediately
- Do NOT commit
- Show the diff
- Ask for approval
- Proceed only if user says yes

**If you already committed without approval:**
- You violated the rule
- Inform user immediately
- Wait for instruction (they may want to revert)

## Why This Matters

- User controls what enters git history
- User controls what gets merged to main
- Clear accountability for all changes
- No surprises in commit history

---

**Last Updated**: 2026-04-14
