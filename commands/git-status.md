---
description: Show comprehensive git status and working directory state
agent: general
---

Execute the git-status command to display detailed git status and working directory state.

Steps to follow:

1. Run `git status -b` — shows current branch, ahead/behind remote, untracked + modified + staged in one pass.

2. Run `git log --oneline -5` to show recent commits.

3. Run `git diff --stat HEAD` to show unstaged changes summary.

4. Run `git diff --cached --stat` to show staged changes summary.

5. Display any uncommitted changes in detail if present

6. Provide summary of repository state and any recommendations (e.g., commit changes, push branch)
