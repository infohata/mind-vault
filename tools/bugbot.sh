#!/bin/bash
# Invoke automated code review via Bugbot on the current PR.
# Automatically commits, pushes, and creates PR if needed.
# Uses AI-generated commit messages and PR descriptions.
#
# PR creation uses the GitHub REST API (`gh api repos/.../pulls`) first so we avoid
# `gh pr create --json` failures caused by GraphQL deprecation around classic Projects
# (`repository.pullRequest.projectCards`). Falls back to `gh pr create` if REST fails.
# Optional: BUGBOT_PR_BASE (default: main) — base branch for new PRs.
#
# Auto Mode: When run by AI agent (non-interactive) or CURSOR_AI_MODE=1,
#            automatically generates commit messages and PR descriptions.
#            For better commit messages, provide COMMIT_MSG env var:
#            COMMIT_MSG="descriptive message" ./tools/bugbot.sh
# Interactive Mode: When run manually, prompts user for input.

set -e

# Resolve the base branch once at script start so every function + the eventual
# REST/CLI PR-create call use the same ref. Previously only the PR-create block
# read BUGBOT_PR_BASE, while generate_pr_title / generate_pr_description / the
# changes-summary hardcoded `origin/main` — on a non-main base the PR would be
# opened correctly but its auto-generated metadata would reflect the wrong range.
BASE_REF="${BUGBOT_PR_BASE:-main}"

# Detect if running in auto mode (AI agent) or interactive mode (human)
# Auto mode if:
#   1. CURSOR_AI_MODE environment variable is set to 1
#   2. stdin is not a TTY (non-interactive execution)
AUTO_MODE=false
if [ "${CURSOR_AI_MODE:-0}" = "1" ] || [ ! -t 0 ]; then
    AUTO_MODE=true
fi

# Helper function to generate commit message based on changes
generate_commit_message() {
    local files=$(git diff --cached --name-only)
    local stats=$(git diff --cached --stat)
    
    # Analyze file patterns to determine commit type
    local type="fix"
    local scope=""
    local description=""
    
    # Count file types to determine primary change type
    local py_count=$(echo "$files" | grep -cE "\.py$" || true)
    local test_count=$(echo "$files" | grep -cE "(test|spec)" || true)
    local doc_count=$(echo "$files" | grep -cE "(\.md|docs/)" || true)
    local i18n_count=$(echo "$files" | grep -cE "locale/.*\.po$" || true)
    local js_count=$(echo "$files" | grep -cE "\.js$" || true)
    local migration_count=$(echo "$files" | grep -cE "migrations/.*\.py$" || true)
    
    # Determine type: prioritize feature work over translations/docs
    # If we have substantial Python/JS changes, it's likely a feature (not just i18n)
    if [ "$py_count" -gt 2 ] || [ "$js_count" -gt 0 ]; then
        # Feature work - check for migrations, models, views, etc.
        if [ "$migration_count" -gt 0 ]; then
            type="feat"
        elif echo "$files" | grep -qE "(models\.py|views\.py|serializers\.py)"; then
            type="feat"
        elif echo "$files" | grep -qE "(test.*\.py|tests/.*\.py)"; then
            type="test"
        else
            type="feat"
        fi
    elif [ "$test_count" -gt 0 ] && [ "$py_count" -eq 0 ] && [ "$js_count" -eq 0 ]; then
        type="test"
    elif [ "$doc_count" -gt 0 ] && [ "$py_count" -eq 0 ] && [ "$js_count" -eq 0 ]; then
        type="docs"
    elif [ "$i18n_count" -gt 0 ] && [ "$py_count" -eq 0 ] && [ "$js_count" -eq 0 ] && [ "$migration_count" -eq 0 ]; then
        # Only translations, no code changes
        type="i18n"
    fi
    
    # Check for Python files to detect app scope
    if echo "$files" | grep -qE "\.py$"; then
        # Try to detect app scope from path
        if echo "$files" | grep -qE "teisutis_ai/"; then
            scope="ai"
        elif echo "$files" | grep -qE "teisutis_kb/"; then
            scope="kb"
        elif echo "$files" | grep -qE "teisutis_auth/"; then
            scope="auth"
        elif echo "$files" | grep -qE "teisutis_core/"; then
            scope="core"
        fi
    fi
    
    # Check for JavaScript files
    if echo "$files" | grep -qE "\.js$"; then
        if [ -z "$scope" ]; then
            scope="frontend"
        fi
    fi
    
    # Try to infer feature name from branch name
    local branch=$(git branch --show-current)
    local feature_name=""
    if echo "$branch" | grep -qE "feature/|fix/"; then
        feature_name=$(echo "$branch" | sed -E 's/^(feature|fix|refactor|docs|test)\///' | sed 's/-/_/g' | sed 's/[^a-zA-Z0-9_]/_/g')
    fi
    
    # Generate description - prefer feature name from branch over filename
    if [ -n "$feature_name" ] && [ "$feature_name" != "" ]; then
        description="$feature_name"
    else
        # Fallback: Use most significant file (not docs or translations)
        local significant_file=$(echo "$files" | grep -vE "(\.md$|locale/.*\.po$|archive/)" | head -1)
        if [ -n "$significant_file" ]; then
            local basename=$(basename "$significant_file" | sed 's/\.[^.]*$//')
            description="$basename"
        else
            description="update"
        fi
    fi
    
    # Count changes
    local insertions=$(echo "$stats" | tail -1 | awk '{print $4}' | grep -oE '[0-9]+' | head -1)
    local deletions=$(echo "$stats" | tail -1 | awk '{print $6}' | grep -oE '[0-9]+' | head -1)
    
    # Build commit message
    if [ -n "$scope" ]; then
        description="$type($scope): $description"
    else
        description="$type: $description"
    fi
    
    # Add stats if significant (but don't make it the primary descriptor)
    if [ -n "$insertions" ] && [ "$insertions" -gt 100 ]; then
        description="$description (+$insertions lines)"
    fi
    
    echo "$description"
}

# Helper function to generate PR title
generate_pr_title() {
    local branch=$(git branch --show-current)
    local first_commit=$(git log "origin/$BASE_REF..HEAD" --oneline | head -1 | sed 's/^[a-f0-9]* //')
    
    # Use first commit message as base, or branch name
    if [ -n "$first_commit" ]; then
        echo "$first_commit" | head -c 72  # Limit to 72 chars
    else
        echo "feat: ${branch#feature/}"
    fi
}

# Helper function to generate PR description
generate_pr_description() {
    local commits=$(git log "origin/$BASE_REF..HEAD" --oneline | head -10)
    local stats=$(git diff "origin/$BASE_REF...HEAD" --stat | head -20)
    
    cat <<EOF
## Summary

This PR includes the following changes:

**Commits:**
\`\`\`
$commits
\`\`\`

**Files Changed:**
\`\`\`
$stats
\`\`\`

## Changes

See commit messages for details.

## Testing

- [ ] Tests pass locally
- [ ] Manual testing completed

## Notes

Automatically created PR for bugbot review.
EOF
}

# Get current branch
BRANCH=$(git branch --show-current)

# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "📝 Uncommitted changes detected. Staging all changes..."
    git add -A
    
    # Show summary of changes for AI to generate commit message
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "📋 Changes Summary (for AI commit message generation):"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Files changed:"
    git diff --cached --stat
    echo ""
    echo "File list:"
    git diff --cached --name-only | sed 's/^/  - /'
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [ "$AUTO_MODE" = "true" ]; then
        # Auto mode: Use provided message or generate one
        if [ -n "$COMMIT_MSG" ]; then
            # AI agent provided message via environment variable
            echo "🤖 Auto mode: Using provided commit message..."
        else
            # Generate commit message based on changes (heuristic fallback)
            echo "🤖 Auto mode: Generating commit message (heuristic fallback)..."
            COMMIT_MSG=$(generate_commit_message)
            
            if [ -z "$COMMIT_MSG" ]; then
                echo "⚠️  Could not auto-generate commit message. Falling back to default."
                COMMIT_MSG="fix: update code"
            fi
            
            echo ""
            echo "⚠️  WARNING: Heuristic-generated commit message may be generic/incorrect."
            echo "   ⚠️  Consider manual commit/PR for better results."
            echo ""
            echo "   To provide better commit message:"
            echo "   COMMIT_MSG=\"descriptive message\" ./tools/bugbot.sh"
            echo ""
        fi
        
        echo "📝 Commit message:"
        echo "   $COMMIT_MSG"
        echo ""
    else
        # Interactive mode: Prompt user
        echo "💡 Ask AI to generate a commit message based on the changes above."
        echo "   Then paste the commit message below (or press Ctrl+C to cancel):"
        echo ""
        read -p "Commit message: " COMMIT_MSG
        
        if [ -z "$COMMIT_MSG" ]; then
            echo "❌ No commit message provided. Aborting."
            exit 1
        fi
    fi
    
    echo ""
    echo "💾 Committing changes with message:"
    echo "   $COMMIT_MSG"
    echo ""
    git commit -m "$COMMIT_MSG"
fi

# Check if branch is pushed
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

if [ -z "$REMOTE" ] || [ "$LOCAL" != "$REMOTE" ]; then
    echo "📤 Pushing to remote..."
    git push -u origin "$BRANCH" 2>/dev/null || git push
fi

# Check if PR exists
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null)

if [ -z "$PR_NUMBER" ]; then
    echo "📋 No PR found. Creating PR..."
    echo ""
    
    # Show summary of changes for AI to generate PR description
    echo "═══════════════════════════════════════════════════════════════"
    echo "📋 Changes Summary (for AI PR description generation):"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Branch: $BRANCH"
    echo ""
    echo "Recent commits:"
    git log "origin/$BASE_REF..HEAD" --oneline | head -10 | sed 's/^/  /'
    echo ""
    echo "Files changed:"
    git diff "origin/$BASE_REF...HEAD" --stat | head -20
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [ "$AUTO_MODE" = "true" ]; then
        # Auto mode: Use provided title/description or generate
        if [ -n "$PR_TITLE" ] && [ -n "$PR_BODY" ]; then
            # AI agent provided title and description via environment variables
            echo "🤖 Auto mode: Using provided PR title and description..."
        else
            # Generate PR title and description
            echo "🤖 Auto mode: Generating PR title and description..."
            echo "⚠️  WARNING: Heuristic-generated PR title/description will be generic."
            echo "   ⚠️  Consider manual PR creation for better results."
            echo ""
            
            if [ -z "$PR_TITLE" ]; then
                PR_TITLE=$(generate_pr_title)
            fi
            
            if [ -z "$PR_BODY" ]; then
                PR_BODY=$(generate_pr_description)
            fi
        fi
        
        if [ -z "$PR_TITLE" ]; then
            echo "⚠️  Could not auto-generate PR title. Using branch name."
            PR_TITLE="feat: $BRANCH"
        fi
        
        if [ -z "$PR_BODY" ]; then
            PR_BODY="Automatically created PR for bugbot review"
        fi
        
        echo "📝 PR title: $PR_TITLE"
        echo "📝 PR description (preview):"
        echo "$PR_BODY" | head -5
        echo "..."
        echo ""
    else
        # Interactive mode: Prompt user
        echo "💡 Ask AI to generate a PR title and description based on the changes above."
        echo ""
        read -p "PR title: " PR_TITLE
        echo ""
        echo "PR description (press Enter, then type description, then Ctrl+D to finish):"
        PR_BODY=$(cat)
        
        if [ -z "$PR_TITLE" ]; then
            echo "❌ No PR title provided. Aborting."
            exit 1
        fi
        
        if [ -z "$PR_BODY" ]; then
            PR_BODY="Automatically created PR for bugbot review"
        fi
    fi
    
    # Create draft PR (REST first — avoids gh pr create GraphQL projectCards issues)
    echo ""
    echo "📋 Creating PR with title: $PR_TITLE"
    # BASE_REF is resolved once near the top of the script (line 20) so all
    # metadata generators and this PR-create call share the same base.
    REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    PR_NUMBER=""
    if [ -n "$REPO_SLUG" ]; then
        PAYLOAD_TMP=$(mktemp)
        # `|| true` preserves the REST-to-CLI fallback chain under `set -e`: if
        # `command -v` finds the tool but then it exits non-zero (corrupt binary,
        # OOM, locale error, etc.), the surrounding script must not terminate
        # here — the `-s "$PAYLOAD_TMP"` check below falls through to `gh pr
        # create` on line 360 when the payload file is empty.
        if command -v jq >/dev/null 2>&1; then
            jq -n \
                --arg title "$PR_TITLE" \
                --arg head "$BRANCH" \
                --arg base "$BASE_REF" \
                --arg body "$PR_BODY" \
                '{title: $title, head: $head, base: $base, body: $body, draft: true}' >"$PAYLOAD_TMP" || true
        elif command -v python3 >/dev/null 2>&1; then
            env PR_TITLE="$PR_TITLE" BRANCH="$BRANCH" PR_BODY="$PR_BODY" BUGBOT_PR_BASE="$BASE_REF" python3 -c \
                'import json, os; print(json.dumps({"title": os.environ["PR_TITLE"], "head": os.environ["BRANCH"], "base": os.environ.get("BUGBOT_PR_BASE", "main"), "body": os.environ["PR_BODY"], "draft": True}))' \
                >"$PAYLOAD_TMP" || true
        fi
        if [ -s "$PAYLOAD_TMP" ]; then
            PR_NUMBER=$(gh api "repos/${REPO_SLUG}/pulls" --method POST --input "$PAYLOAD_TMP" --jq '.number' 2>/dev/null || true)
        fi
        rm -f "$PAYLOAD_TMP"
        # `gh api` bypasses `--jq` and prints raw error JSON to stdout on non-2xx
        # responses (422 for duplicate head, 401/403, etc.). Without this guard
        # the JSON body would pass the `-z` empty check below, silently skip the
        # CLI fallback, and propagate as `✅ Created PR #{"message":"..."}` + a
        # crash at the next `gh pr comment`. Require purely numeric output.
        if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
            PR_NUMBER=""
        fi
    fi
    if [ -z "$PR_NUMBER" ]; then
        echo "⚠️  REST PR create failed or no jq/python3; falling back to gh pr create..."
        PR_NUMBER=$(gh pr create --title "$PR_TITLE" --body "$PR_BODY" --draft --base "$BASE_REF" --json number -q '.number' 2>/dev/null || true)
        # Same numeric-guard discipline for parity — cheap, and protects against
        # any future CLI wrapper that might print non-numeric output on edge cases.
        if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
            PR_NUMBER=""
        fi
    fi

    if [ -z "$PR_NUMBER" ]; then
        echo "❌ Failed to create PR. Please create manually:"
        echo "   gh api repos/<owner>/<repo>/pulls --method POST (JSON body)   # or"
        echo "   gh pr create --base '$BASE_REF' --draft --title '...' --body '...'"
        exit 1
    fi

    echo "✅ Created PR #$PR_NUMBER"
fi

# Check if there's an active bugbot run (comment with eyes reaction)
echo "🔍 Checking for active bugbot runs..."
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(echo "$REPO_URL" | sed -E 's/.*github\.com[:/]([^.]+)\.git/\1/' || echo "infohata/mind-vault")

ACTIVE_BUGBOT=$(gh api "repos/$REPO_NAME/issues/$PR_NUMBER/comments" \
    --jq '[.[] | select(.body == "bugbot run" and (.reactions.eyes // 0) > 0)] | length' 2>/dev/null || echo "0")

if [ "$ACTIVE_BUGBOT" -gt 0 ]; then
    echo "⚠️  Active bugbot run detected ($ACTIVE_BUGBOT with 👀 reaction)"
    echo "   Please wait for current analysis to complete before running again."
    echo "   Check PR #$PR_NUMBER for results."
    exit 0
fi

echo "🔍 Invoking Bugbot on PR #$PR_NUMBER..."
gh pr comment "$PR_NUMBER" --body "bugbot run"
echo "✅ Bugbot invocation sent. Check PR comments for review results."
