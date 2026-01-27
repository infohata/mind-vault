# /bugbot Command Documentation

**Purpose:** Invoke automated code review via Bugbot on the current PR. Automatically handles commits, pushes, and PR creation with AI-generated messages.

**AI Workflow:**
1. **Analyze changes**: Read git diff, file stats, and branch context
2. **Generate commit message**: Semantic understanding of feature scope and changes
3. **Generate PR details**: Comprehensive title and description
4. **Execute bugbot**: Run with AI-generated messages via environment variables

**Features:**
- ✅ Auto-commits uncommitted changes with semantic commit message
- ✅ Auto-pushes to remote branch
- ✅ Auto-creates draft PR if needed
- ✅ Invokes bugbot for automated code review

**Usage:** `/bugbot`

**Requirements:**
- Repository must have a `tools/bugbot.sh` script
- GitHub CLI (`gh`) must be configured
- Current branch should be a feature branch

**AI Advantages over heuristic scripts:**
- Semantic understanding of code relationships
- Context-aware commit messages
- Comprehensive PR descriptions
- Handles complex multi-file changes accurately

**Manual override available:**
```bash
COMMIT_MSG="feat(auth): custom commit message" ./tools/bugbot.sh
```