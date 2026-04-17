---
description: Find and display bugbot comments on current or specified PR
agent: general
---

Execute the bugbot_comments command to retrieve and display bugbot code review comments from GitHub PRs.

Steps to follow:

1. Determine the PR number:

   - If PR_NUMBER environment variable is set, use that
   - Otherwise, get the PR number for the current branch using: gh pr view --json number -q .number

2. Fetch all review comments from the PR using GitHub API:

   - Use gh api repos/{owner}/{repo}/pulls/{pr_number}/comments
   - Filter comments where the author is 'cursor[bot]' (bugbot)

3. Display the comments sorted by severity (High > Medium > Low):

   - For each comment, show:
     - Severity level
     - File path and line number
     - Title and description
     - Comment link

4. If no comments found, display a message indicating that

5. Handle errors gracefully (PR not found, no permissions, etc.)

Use the Bash tool to run gh commands, and process the JSON output to filter and display the comments.
