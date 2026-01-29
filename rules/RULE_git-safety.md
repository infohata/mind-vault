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

**ONLY exception:** User says "yes, commit" or "go ahead" in the CURRENT response.

### 3. NEVER MERGE TO MAIN
**Agent NEVER merges to main branch:**
- ❌ NEVER run `git merge` (any branch)
- ❌ NEVER run `gh pr merge` (any PR to main)
- ❌ NEVER use GitHub API to merge PRs
- ❌ NEVER click merge buttons (if browser automation available)
- ❌ Even if user says "merge" or "click the green button" - DON'T DO IT

**What agents DO:**
- ✅ Create feature branches
- ✅ Commit changes (with approval)
- ✅ Push branches
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

**Last Updated**: 2026-01-29
