# RULE_commit-approval

## Principle
Always ask user for approval before committing. Show changes first, explain rationale, wait for confirmation.

## Details

### When to Ask for Approval

**CRITICAL**: Always ask for explicit approval before ANY commit, regardless of prior context or previous approvals.

**Always ask before committing**:
- ✅ Every single commit, no exceptions
- ✅ Even if you've received approval for similar changes before
- ✅ Even if user said "go ahead" in a previous conversation
- ✅ Even if changes seem trivial or obvious
- ✅ Each new session requires fresh approval
- ✅ Each new set of changes requires fresh approval

**The ONLY exception to asking**:
- If, in THIS CURRENT MESSAGE/RESPONSE, user explicitly says one of:
  - "Go ahead and commit"
  - "Commit this"
  - "Yes, commit"
  - "Commit with that message"
  - Or similar explicit approval **in the same turn**

**Previous approvals DO NOT carry over**:
- ❌ Prior context from earlier messages is ignored
- ❌ "Earlier you approved X" does not count
- ❌ Previous sessions don't carry consent
- ❌ "You said you would commit when ready" requires fresh ask
- ❌ Previous approval for similar changes doesn't apply to new changes

**Every commit requires fresh approval**:
- Show the changes
- Show the commit message
- Ask "Should I commit?"
- Wait for explicit "yes" in this turn

### Pre-Commit Review Process

**Step 1: Show the Change**
```bash
# Display staged changes
git diff --cached

# Or for specific file
git diff --cached skills/SKILL_example.md
```

**Step 2: Summarize**
Explain clearly:
- What file(s) are being changed
- What's being added/modified/removed
- Why the change was made
- Any potential impacts

**Step 3: Ask Approval**
Present the information and ask:
> "I've made these changes to [files]. Should I commit them with message '[commit message]'?"

**Step 4: Wait for Response**
- If approved ("yes", "commit", "go ahead"): commit with clear message
- If feedback given: adjust and re-show changes, ask again
- If rejected or no response: do NOT commit, do NOT revert. Wait for explicit instruction.
- Revert ONLY if user explicitly commands it with `git revert <commit-hash>` or similar

### Commit Message Standards

**Format**:
```
type(scope): brief description (≤72 chars)

Optional explanation of why this change was made.
```

**Before committing, show user**:
- The files being changed
- The specific changes (git diff)
- The commit message you'll use
- Why this change is needed

### Change Summary Example

```
## Summary of Changes

**Files modified**:
- skills/SKILL_new_pattern.md (new file, 250 lines)
- AGENTS.md (modified, +15 -2 lines)

**What's changing**:
- Adding new skill for django-tenants patterns
- Updating AGENTS.md with reference to new skill

**Commit message**:
feat(skill): add django-tenants-patterns skill

Adds comprehensive skill for multi-tenant context management
in Django projects using django-tenants package.

**Approval needed**: Yes

Ready to commit?
```

## Examples

✅ DO:

```
I've created SKILL_error-handling-async.md with async error 
categorization patterns. The file is 300 lines with examples 
from Teisutis.

Commit message: feat(skill): add error-handling-async skill

Should I commit this?
```

```
I've updated AGENTS.md to add link to the new skill.
Changes: +3 lines, links to error handling documentation.

Commit message: docs: update AGENTS.md with error-handling-async reference

Ready to commit?
```

❌ DON'T:

```
# Without showing changes
git add .
git commit -m "update files"
git push

# Without asking
# Just committing directly without user input
```

```
# Vague summary
"Making changes to the repository"
```

## The Rule (No Exceptions)

**There are NO exceptions to asking for approval on each commit.**

This is not a guideline. This is a hard rule.

### What Might Seem Like Exceptions (But Aren't)

**You still must ask** when:
- User said "commit when ready" (requires fresh ask when actually committing)
- User approved earlier similar changes (must ask again for new changes)
- User said "feel free to make changes and commit" (must ask before each commit)
- It's a "simple" or "obvious" change (ask anyway)
- Multiple files seem unrelated (ask anyway)
- Changes are small (ask anyway)
- You're confident the changes are correct (ask anyway)
- Previous conversation approved this type of work (ask anyway)

### The Only Real Exception

**Skip asking ONLY if**, in this very message, user says something like:
- "Go ahead and commit"
- "Commit it"
- "Yes, commit with that message"
- Or explicitly approves the specific commit you're about to make

After you commit, the approval is spent. The next commit needs new approval.

## Why This Matters

- **User Control**: User stays informed about repository changes
- **Quality**: Catches mistakes before they're committed
- **History**: Ensures commit messages are clear and accurate
- **Accountability**: User explicitly approves what gets committed
- **Trust**: Transparency in what agent is doing

## Related Rules

- [`RULE_git-workflow.md`](RULE_git-workflow.md) - Branching and commit practices
- [`RULE_merge-approval.md`](RULE_merge-approval.md) - Merge approval process
- [`AGENTS.md`](../AGENTS.md) - Overall agent guidelines

---

**Last Updated**: 2026-01-26
