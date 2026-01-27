# /git-status Command Documentation

**Purpose:** Display detailed git status including uncommitted changes, branch info, and repository state.

**Usage:** `/git-status`

**What it shows:**
- Current branch and upstream status
- Staged vs unstaged changes
- Untracked files
- Recent commits (last 3)
- Any merge/rebase conflicts
- Stash status if applicable

**Features:**
- Color-coded output for better readability
- Summary statistics (files changed, insertions/deletions)
- Branch comparison with remote
- Helpful next-step suggestions

**Example Output:**
```
📍 Current Branch: feature/django-multi-tenant
📡 Remote Status: 2 commits ahead of origin/main

📝 Changes to commit:
  modified:   AGENTS.md (15 insertions, 3 deletions)
  new file:   commands/git-status.md

📭 Untracked files:
  docs/temp-notes.md

🔄 Recent commits:
  abc1234 - feat: OpenCode integration (2 hours ago)
  def5678 - docs: Update agent links (1 day ago)

💡 Next steps: Run 'git add .' then 'git commit -m "message"'
```