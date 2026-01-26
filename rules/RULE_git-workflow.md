# RULE_git-workflow

## Principle
Work on feature branches only; never commit directly to main. All work flows through focused, well-described commits and pull requests.

## Details

### Branch Strategy

**Main Branch Protection**:
- `main` is production-ready and should always be stable
- Only merge via GitHub PR review
- Never push directly to main
- Never commit directly to main (locally or remotely)

**Feature Branches Only**:
- Create feature branches from main: `git checkout -b <branch-name> origin/main`
- Always push with upstream tracking: `git push -u origin <branch-name>`
- Delete branches after merge: `git branch -d <branch-name>` (locally)

### Branch Naming Convention

**Format**: `{type}/{feature-name}`

**Types**:
- `feature/` - New features (e.g., `feature/django-async-patterns`)
- `fix/` - Bug fixes (e.g., `fix/streaming-recovery`)
- `docs/` - Documentation (e.g., `docs/skill-templates`)
- `refactor/` - Refactoring (e.g., `refactor/rule-organization`)

**Examples**:
```
feature/django-async-patterns
feature/error-handling-async
fix/typo-in-skill-template
docs/contributing-guide
```

### Commit Messages

**Format**: Use conventional commits

```
type(scope): brief description (≤72 chars)

Optional longer explanation if needed.
- Use bullet points for multiple items
- Explain the "why" not just the "what"
```

**Types**:
- `feat` - New skill, rule, or feature
- `fix` - Bug fixes
- `docs` - Documentation
- `refactor` - Code/file organization
- `style` - Formatting, whitespace
- `chore` - Build config, dependencies

**Scope** (in parentheses):
- `skill` - Skill files
- `rule` - Rule files
- `agent` - Agent files
- `docs` - Documentation
- `all` - Multiple areas

**Examples**:
```
feat(skill): add django-async-patterns skill
docs(skill): improve SKILL.md template examples
fix(rule): correct git-workflow branch naming
refactor(all): reorganize rules by priority
```

### Commit Practices

**Atomic Commits**:
- Each commit should be a complete, logical change
- Can be reviewed and understood independently
- Should not break the repository

**Approval Required Before Every Commit**:
- Show changes first (git diff --cached)
- Present commit message
- Get explicit user approval in current turn
- Previous approvals don't carry over
- Each new commit requires fresh approval
- (See [`RULE_commit-approval.md`](RULE_commit-approval.md))

**Meaningful Messages**:
- First line is the subject (≤72 characters)
- Leave a blank line after subject
- Explain why the change was made, not just what changed
- Use imperative mood: "add feature" not "added feature"

**Good Examples**:
```
feat(skill): add error-handling-async skill

Add comprehensive skill for categorizing errors in async code:
- Programming errors vs. runtime errors
- Different logging strategies
- Graceful degradation patterns
- Real-world examples from Teisutis

This pattern is reusable across WebSocket/real-time services.
```

```
fix(rule): clarify branch naming convention

Previous examples used hyphens inconsistently.
Now follows kebab-case consistently throughout.
```

### Push Behavior

**Verify Before Push**:
```bash
# Check branch tracking
git branch -vv

# Should show: feature/branch-name [origin/feature/branch-name]
# NOT: feature/branch-name [origin/main]
```

**Set Upstream on First Push**:
```bash
# Always use -u flag on first push
git push -u origin feature/branch-name

# This creates remote branch and sets correct tracking
# Prevents accidental pushes to wrong remote
```

**After First Push**:
```bash
# Subsequent pushes don't need -u
git push
```

### Pull Requests

**Before Creating**:
- [ ] Branch name follows convention
- [ ] Commits are atomic with clear messages
- [ ] Changes are focused (one feature/fix per PR)
- [ ] Documentation is updated (if needed)
- [ ] No merge of main into feature branch

**PR Title**:
- Use first commit message or summarize changes
- Keep ≤72 characters for GitHub display
- Follow conventional commit format

**PR Description**:
- Explain what changed and why
- Link to related issues if applicable
- Note any dependencies on other PRs
- Include context for reviewers

**Example**:
```
## Summary
Add SKILL_error-handling-async.md - comprehensive guide for 
error categorization in async code.

## Changes
- New skill file with pattern documentation
- Examples from Teisutis WebSocket consumers
- Tests and production validation notes

## Type
New documentation/skill

## Related
None
```

### Merge Process

**User Responsibility**:
- Agents commit and push to feature branches
- Agents create PRs (if integration allows)
- **User reviews and merges on GitHub**
- Agents never merge locally or via CLI
- (See [`RULE_merge-approval.md`](RULE_merge-approval.md))

**After Merge - Safe Recovery Sequence**:
1. Fetch and pull remote main (without switching): `git pull origin main:main`
2. Verify merged changes are in remote: `git log origin/main --oneline`
3. If running services: backup DB and shutdown Docker
4. Switch to main: `git checkout main`
5. Delete local feature branch: `git branch -d <branch>`
6. Create new branch from fresh main: `git checkout -b feature/next origin/main`

**Conflict Avoidance**:
- Clean staging prevents most conflicts (rare in practice)
- If conflicts occur: resolve all at once, review final state, single merge commit
- All resolutions staged together before final commit

### Workflow Summary

```
1. Create branch from main
   git checkout -b feature/my-feature origin/main

2. Make changes and commit
   git add <files>
   git commit -m "feat(scope): description"

3. Push with upstream tracking
   git push -u origin feature/my-feature

4. Create PR (if available)
   - Describe changes
   - Explain why

5. Wait for review
   - User reviews changes
   - User merges on GitHub

6. Clean up locally
   git branch -d feature/my-feature

7. Continue with new feature
   git checkout -b feature/next-feature origin/main
```

## Examples

✅ DO:
```bash
# Correct workflow
git checkout -b feature/new-skill origin/main
git add skills/SKILL_new_pattern.md
git commit -m "feat(skill): add new reusable pattern"
git push -u origin feature/new-skill
# Create PR on GitHub, wait for user to merge
git branch -d feature/new-skill
```

❌ DON'T:
```bash
# Wrong: Direct to main
git commit -m "update" -a
git push origin main

# Wrong: No upstream tracking
git push origin feature/my-branch

# Wrong: Merging on local
git merge feature/my-feature
git push origin main

# Wrong: Editing main directly
git checkout main
git add <files>
git commit -m "quick fix"
```

## Why This Matters

- **Stability**: Main stays production-ready
- **History**: Clear, atomic commits tell the story
- **Review**: PRs provide accountability and QA
- **Collaboration**: Prevents conflicts with other agents
- **Rollback**: Easy to revert single commits if needed
- **Learning**: Clear messages help future developers understand decisions

## Related Rules

- [`RULE_commit-approval.md`](RULE_commit-approval.md) - When to ask before committing
- [`RULE_merge-approval.md`](RULE_merge-approval.md) - Merge approval process
- [`AGENTS.md`](../AGENTS.md) - Overall agent guidelines

---

**Last Updated**: 2026-01-26
