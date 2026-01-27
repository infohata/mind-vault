# /create-pr Command Documentation

**Purpose:** Generate and create a comprehensive GitHub pull request with proper title, description, and labels.

**Usage:** `/create-pr`

**AI Workflow:**
1. **Analyze branch**: Determine base branch and feature scope
2. **Review changes**: Comprehensive analysis of all modifications
3. **Generate title**: Clear, descriptive PR title following conventions
4. **Write description**: Detailed summary including:
   - What changes were made
   - Why changes were necessary
   - How to test the changes
   - Any breaking changes or migration notes
5. **Suggest labels**: Appropriate GitHub labels (enhancement, bug, documentation, etc.)
6. **Create PR**: Execute `gh pr create` with generated content

**PR Structure Generated:**
```markdown
## Title
feat|fix|docs(scope): Brief description of changes

## Description
### Summary
High-level overview of the feature/fix

### Changes Made
- Specific file/component changes
- New functionality added
- Breaking changes (if any)

### Testing
How to test the changes, expected behavior

### Related Issues
Closes #123, Fixes #456
```

**Features:**
- ✅ Auto-detects base branch (main/master)
- ✅ Comprehensive change analysis
- ✅ Conventional commit title format
- ✅ Detailed technical descriptions
- ✅ Testing instructions included
- ✅ Related issue linking
- ✅ Appropriate label suggestions

**Requirements:**
- GitHub CLI (`gh`) configured
- Branch pushed to remote
- No uncommitted changes (auto-commits if needed)

**Example PR Created:**
```
Title: feat(auth): implement user session management

Description:
## Summary
Implements comprehensive user session handling with automatic cleanup and security features.

## Changes Made
- Added Session model with expiry tracking
- Implemented session cleanup cron job
- Added middleware for session validation
- Updated authentication views

## Testing
1. Login and verify session creation
2. Check session expiry after timeout
3. Verify session cleanup removes expired sessions

Closes #123
```