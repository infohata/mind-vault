# RULE_merge-approval

## Principle
Never merge branches without explicit user approval. User is responsible for all merges to main. Agents can only prepare and present changes.

## Details

### Critical Limitation

**Agents CANNOT**:
- ❌ Merge pull requests (local or on GitHub)
- ❌ Push directly to main branch
- ❌ Create merge commits locally
- ❌ Force push after merging
- ❌ Delete branches after merge

**Only Users CAN**:
- ✅ Review and approve changes
- ✅ Merge PRs on GitHub
- ✅ Delete remote branches
- ✅ Manage main branch state

### When User Should Merge

**User workflow**:
1. Agent creates feature branch and commits changes
2. Agent pushes feature branch with `-u` flag
3. Agent creates PR (if GitHub integration available)
4. **User reviews changes on GitHub**
5. **User merges PR on GitHub**
6. User optionally deletes remote branch
7. Agent cleans up local branch: `git branch -d <branch>`

### Pre-Merge Review for Complex Changes

**If agent needs to prepare merge review** (for local merges only):
Agent should show user:
- List of commits to merge
- Statistics (files changed, lines added/removed)
- Potential issues or conflicts
- Git preview (git log and diff --stat output)

**Example preparation** (agent prepares info, user merges):
```
## Review: feature/new-skill → main

**Commits to merge** (2 commits):
- abc123 feat(skill): add error-handling-async
- def456 docs: update AGENTS.md reference

**Statistics**:
- 2 files changed
- +320 lines, -5 lines
- 1 new file (SKILL_error-handling-async.md)
- 1 modified file (AGENTS.md)

**Potential issues**: None detected

I've prepared this review. When ready, you can merge on GitHub
(or let me know if you want to merge locally with git merge).
```

**User then**:
- Reviews the information
- Decides when/how to merge
- Executes merge command or GitHub button

### Merge Commands (For User Only)

**If user wants agent to show merge command** (user executes it):
```bash
# Show what would be merged
git log main..origin/feature/branch-name
git diff main...origin/feature/branch-name --stat

# (User executes, not agent)
git merge feature/branch-name
```

**On GitHub**:
- User clicks "Merge pull request" button
- User selects merge strategy (Create a merge commit, Squash, Rebase)
- User confirms merge

### After Merge

**CRITICAL**: Safe merge recovery sequence for local branches (especially with running services).

**Step 1: Pull remote main first**
```bash
# Fetch and pull main without switching to it
git fetch origin
git pull origin main:main

# Verify merged changes are in remote main
git log origin/main --oneline -5
```

**Step 2: Verify merged changes**
```bash
# Check if your changes are in remote main
git log origin/main --grep="your-commit-message" --oneline

# Or check specific files
git diff origin/main~1 origin/main -- path/to/file
```

**Step 3: If in doubt - BACKUP AND SHUTDOWN**
```bash
# Backup database before switching branches (if running services)
./tools/backup_db.sh  # or your backup command

# Shutdown running containers
docker compose down

# Then proceed with cleanup
```

**Step 4: Switch to main and cleanup**
```bash
# Only after verifying merged changes and shutting down if needed
git checkout main

# Delete local feature branch
git branch -d feature/branch-name

# Continue with next feature
git checkout -b feature/next-feature origin/main
```

**Why this order**:
- Pulling remote first prevents data sync issues
- Verification confirms merge was successful
- Backup + shutdown prevents data integrity incidents
- Only then switch branches locally

### Handling Merge Conflicts

**If conflicts detected**:
1. Agent informs user about conflicts
2. Agent can offer to resolve them if simple
3. User has final approval for conflict resolution
4. Agent does NOT push conflict resolution without approval

**Example**:
```
Merge would have conflicts in:
- AGENTS.md (lines 45-52)

Conflicts seem resolvable - two agents edited different sections.
Should I resolve them and prepare the merge, or would you prefer
to handle it manually?
```

## Examples

✅ DO:

```
Feature branch 'feature/new-skill' is ready. PR is created 
on GitHub.

Changes summary:
- 1 new file: SKILL_example.md (250 lines)
- Atomic commit with clear message
- No conflicts expected

Ready for you to review and merge on GitHub when convenient.
```

```
Branch is pushed and PR created. Here's what will be merged:

feat(skill): add django-async-patterns
docs: update skill references

2 files changed, +400 -10 lines

User reviews and merges on GitHub.
```

❌ DON'T:

```
# Attempting to merge locally
git merge feature/my-branch
git push origin main

# Attempting to merge on GitHub
gh pr merge 42 --merge

# Force pushing merged state
git push --force origin main
```

```
# Without showing user what's being merged
"I'll merge this now"
[commits changes]
```

## Branch Tracking Safety

**Always verify before push**:
```bash
# Check where branch will push
git branch -vv

# Should show: feature/my-branch [origin/feature/my-branch]
# NOT: feature/my-branch [origin/main]
```

**If tracking is wrong**:
```bash
# Fix it before pushing
git push -u origin feature/my-branch
```

## Conflict Resolution Approval

**If merge has conflicts**:

1. **Show user all conflicts**:
```
Conflict in AGENTS.md:
<<<<<<< HEAD (main)
Version A from main
=======
Version B from feature branch
>>>>>>> feature/new-content
```

2. **Propose resolution strategy**:
"Conflicts detected in [files]. My proposed resolution:
- [file1]: keep version A because [reason]
- [file2]: merge both versions because [reason]

Should I proceed with resolving all conflicts?"

3. **Resolve all conflicts**:
- Stage all resolved files: `git add <files>`
- Do NOT commit yet

4. **Show final resolved state**:
Display the fully resolved code for user review

5. **Get approval for merge commit**:
"All conflicts resolved. Ready to commit as single merge commit?"

6. **Commit as single merge commit**:
```bash
git commit -m "merge: resolve conflicts from feature/branch-name"
```

**Important**: All conflicts solved and reviewed → single merge commit. No intermediate commits during conflict resolution.

## Why This Matters

- **User Control**: User maintains authority over main branch
- **Safety**: Prevents accidental merges to production branch
- **Responsibility**: Clear accountability for what gets released
- **Review**: User personally verifies changes before merge
- **Reversibility**: If needed, user can revert from GitHub UI

## Related Rules

- [`RULE_git-workflow.md`](RULE_git-workflow.md) - Branching and commit practices
- [`RULE_commit-approval.md`](RULE_commit-approval.md) - Commit approval process
- [`AGENTS.md`](../AGENTS.md) - Overall agent guidelines

---

**Last Updated**: 2026-01-26
