---
description: Create well-structured pull request with AI-generated title and description
agent: general
---

# create-pr

Execute the create-pr command to generate and create a comprehensive GitHub pull request.

Steps to follow:

1. Check current branch and ensure it's not main:

   - Run git branch --show-current
   - Verify it's a feature branch

2. Check if PR already exists for this branch:

   - Run gh pr view --json number or handle error if not exists

3. Determine base branch and analyze commits:

   - Detect base: try `gh pr view --json baseRefName -q .baseRefName` if a PR exists; otherwise default to `origin/main` (or `origin/deployment` for release-branch projects)
   - Run `git log <base>..HEAD --oneline` to see commits
   - Run `git diff <base>...HEAD --stat` for file changes

4. Generate PR title:

   - Should be clear, descriptive, and follow conventional format
   - Based on the main changes in the branch

5. Generate comprehensive PR description:

   - Include what changed and why
   - List key changes or features
   - Add context for reviewers
   - Include any breaking changes or migration notes

6. Create the PR:

   - Use gh pr create --title "generated title" --body "generated description" --draft
   - Make it draft initially for review

7. Provide the PR URL and summary

Requirements:

- gh CLI configured
- Branch should be pushed to remote
- Should not be on main branch
