# /bugbot_comments Command Documentation

**Purpose:** Retrieve and display bugbot code review comments from GitHub PRs.

**Usage:**
```bash
# Find bugbot comments on current branch's PR
/bugbot_comments

# Find bugbot comments on specific PR number
PR_NUMBER=123 /bugbot_comments
```

**Features:**
- Automatically detects PR from current branch
- Fetches all inline code review comments via GitHub API
- Filters for bugbot comments (cursor[bot])
- Displays comments sorted by severity (High > Medium > Low)
- Shows file path, line number, title, description, and comment link

**Requirements:**
- Repository must have a `tools/find_bugbot_comments.sh` script
- GitHub CLI (`gh`) must be configured
- Current branch should have an associated PR

**Example Output:**
```
🐛 Found 2 bugbot comment(s):

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/2] Severity: MEDIUM
**File:** src/components/Button.tsx:42
**Title:** Missing accessibility attributes
**Description:** Button element should include aria-label for screen readers
**Locations:**
  - src/components/Button.tsx#L42
**Link:** https://github.com/user/repo/pull/123#discussion_r1234567890
```

**Manual usage:**
```bash
# For current branch PR
./tools/find_bugbot_comments.sh

# For specific PR
./tools/find_bugbot_comments.sh 123
```