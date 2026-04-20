---
description: Automated code review and PR creation with AI-generated messages
agent: general
---

# bugbot

Execute automated code review via Bugbot on the current PR. Automatically handles commits, pushes, and PR creation with AI-generated messages.

Steps to follow:

1. Set CURSOR_AI_MODE=1 environment variable to enable auto mode
2. Execute the bugbot.sh script: ./tools/bugbot.sh
3. The script will automatically:
   - Commit any staged changes with AI-generated semantic commit message
   - Push changes to remote branch
   - Create draft PR if none exists
   - Post "bugbot run" comment to trigger automated review

Use the Bash tool to run the script with proper environment variables.
