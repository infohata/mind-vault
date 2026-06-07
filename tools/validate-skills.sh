#!/bin/bash
# Validate skill format.
#
# Default mode is Claude Code (mind-vault's source-of-truth host): checks the
# universal structural rules (name format, frontmatter present, name↔dir match,
# description present + non-empty). CC skill descriptions are intentionally
# rich/long for probabilistic triggering, so there is NO upper length cap by
# default.
#
# Pass --opencode to ADD the stricter OpenCode-format checks (≤1024-char
# description, 100-200 recommended range, OpenCode section headings). Those are
# only meaningful when forking a skill into the OpenCode host — see
# docs/guides/AGENT_PORTABILITY.md. Running them against a CC-first skill is a
# false alarm, which is why they are opt-in.
#
# Usage: ./tools/validate-skills.sh [--opencode] [skill-name]
#        ./tools/validate-skills.sh [--opencode] --all

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Mode: cc (default) | opencode (--opencode adds OpenCode-format checks).
# Extract the flag from anywhere in the arg list, leave the rest positional.
MODE=cc
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --opencode) MODE=opencode ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# Counters
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# Function to validate a single skill
validate_skill() {
  local SKILL_NAME="$1"
  local SKILL_DIR="skills/$SKILL_NAME"
  local SKILL_FILE="$SKILL_DIR/SKILL.md"
  local HAS_ERRORS=0
  local HAS_WARNINGS=0

  echo -e "${BLUE}Validating skill: $SKILL_NAME${NC}"
  echo "================================"

  # Check directory exists
  if [ ! -d "$SKILL_DIR" ]; then
    echo -e "${RED}❌ Directory not found: $SKILL_DIR${NC}"
    return 1
  fi

  # Check SKILL.md exists
  if [ ! -f "$SKILL_FILE" ]; then
    echo -e "${RED}❌ SKILL.md not found in $SKILL_DIR${NC}"
    return 1
  fi

  # Validate name format
  if ! echo "$SKILL_NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo -e "${RED}❌ Invalid name format: $SKILL_NAME${NC}"
    echo "   Must match: ^[a-z0-9]+(-[a-z0-9]+)*$"
    echo "   Requirements:"
    echo "   - Lowercase letters only (a-z)"
    echo "   - Numbers allowed (0-9)"
    echo "   - Single hyphens as separators"
    echo "   - Cannot start or end with hyphen"
    echo "   - No consecutive hyphens"
    HAS_ERRORS=1
  fi

  # Check name length
  NAME_LENGTH=${#SKILL_NAME}
  if [ $NAME_LENGTH -lt 1 ] || [ $NAME_LENGTH -gt 64 ]; then
    echo -e "${RED}❌ Name length must be 1-64 characters (got $NAME_LENGTH)${NC}"
    HAS_ERRORS=1
  fi

  # Check frontmatter exists
  if ! grep -q "^---$" "$SKILL_FILE"; then
    echo -e "${RED}❌ Missing YAML frontmatter (must start with ---)${NC}"
    HAS_ERRORS=1
  else
    # Check frontmatter name matches
    if ! grep -q "^name: $SKILL_NAME$" "$SKILL_FILE"; then
      echo -e "${RED}❌ Frontmatter 'name' doesn't match directory name${NC}"
      echo "   Expected: name: $SKILL_NAME"
      ACTUAL_NAME=$(grep "^name: " "$SKILL_FILE" | head -n1 || echo "not found")
      echo "   Found: $ACTUAL_NAME"
      HAS_ERRORS=1
    fi

    # Check description exists
    if ! grep -q "^description:" "$SKILL_FILE"; then
        echo -e "${RED}❌ Missing 'description' in frontmatter${NC}"
        HAS_ERRORS=1
    else
        # Handle both single-line and multiline descriptions. The description
        # spans from its line to the next frontmatter field — but that search
        # MUST be bounded by the closing `---` fence. Without the bound, a
        # description that is the last frontmatter field over-reads into the
        # body until the first `word:` line there (e.g. `status: complete`
        # inside a fenced YAML example), inflating the count by thousands of
        # chars and producing false "description too long" failures.
        local desc_start=$(grep -n "^description:" "$SKILL_FILE" | head -n1 | cut -d: -f1)
        # Closing frontmatter fence = the 2nd `^---$`.
        local fm_end=$(grep -n "^---$" "$SKILL_FILE" | sed -n '2p' | cut -d: -f1)
        local desc_end
        if [ -n "$fm_end" ]; then
            # Next frontmatter field after description, WITHIN the frontmatter only.
            local next_field=$(grep -n "^[a-zA-Z_][a-zA-Z0-9_]*:" "$SKILL_FILE" | awk -F: -v start="$desc_start" -v end="$fm_end" '$1 > start && $1 < end {print $1; exit}')
            if [ -n "$next_field" ]; then
                desc_end=$((next_field - 1))
            else
                desc_end=$((fm_end - 1))
            fi
        else
            # Malformed frontmatter (no closing fence) — treat description as 1 line.
            desc_end=$desc_start
        fi

        if [ $desc_end -ge $desc_start ]; then
            DESCRIPTION=$(sed -n "${desc_start},${desc_end}p" "$SKILL_FILE" | sed '1s/^description: //' | sed '/^$/d')
            DESC_LENGTH=$(echo -n "$DESCRIPTION" | wc -c)
            
            if [ $DESC_LENGTH -lt 1 ]; then
                # Universal: a description must exist and be non-empty.
                echo -e "${RED}❌ Description is empty${NC}"
                HAS_ERRORS=1
            elif [ "$MODE" = opencode ] && [ $DESC_LENGTH -gt 1024 ]; then
                # OpenCode-only hard cap. CC has no upper limit.
                echo -e "${RED}❌ Description too long: $DESC_LENGTH characters (max 1024, OpenCode format)${NC}"
                HAS_ERRORS=1
            elif [ "$MODE" = opencode ] && [ $DESC_LENGTH -lt 20 ]; then
                echo -e "${YELLOW}⚠️  Description very short: $DESC_LENGTH characters (recommend 100-200)${NC}"
                HAS_WARNINGS=1
            elif [ "$MODE" = opencode ] && [ $DESC_LENGTH -gt 300 ]; then
                echo -e "${YELLOW}⚠️  Description long: $DESC_LENGTH characters (recommend 100-200, OpenCode)${NC}"
                HAS_WARNINGS=1
            fi
        fi
    fi
  fi

  # Check for common issues
  if grep -q "TODO" "$SKILL_FILE"; then
    echo -e "${YELLOW}⚠️  Found TODO comments${NC}"
    HAS_WARNINGS=1
  fi

  if grep -q "FIXME" "$SKILL_FILE"; then
    echo -e "${YELLOW}⚠️  Found FIXME comments${NC}"
    HAS_WARNINGS=1
  fi

  if grep -q "XXX" "$SKILL_FILE"; then
    echo -e "${YELLOW}⚠️  Found XXX comments${NC}"
    HAS_WARNINGS=1
  fi

  # Recommended sections — OpenCode-format convention only. CC skills use their
  # own heading wording (e.g. "## When to use"), so these would false-warn on
  # healthy CC skills; gate behind --opencode.
  if [ "$MODE" = opencode ]; then
    if ! grep -q "^## Overview" "$SKILL_FILE" && ! grep -q "^## What I do" "$SKILL_FILE"; then
      echo -e "${YELLOW}⚠️  Missing 'Overview' or 'What I do' section${NC}"
      HAS_WARNINGS=1
    fi

    if ! grep -q "^## When to Use" "$SKILL_FILE" && ! grep -q "^## When to use me" "$SKILL_FILE"; then
      echo -e "${YELLOW}⚠️  Missing 'When to Use' section${NC}"
      HAS_WARNINGS=1
    fi

    if ! grep -q "^## Examples" "$SKILL_FILE" && ! grep -q "^## Example" "$SKILL_FILE"; then
      echo -e "${YELLOW}⚠️  Missing 'Examples' section${NC}"
      HAS_WARNINGS=1
    fi
  fi

  # Check for code blocks
  if ! grep -q '```' "$SKILL_FILE"; then
    echo -e "${YELLOW}⚠️  No code blocks found (consider adding examples)${NC}"
    HAS_WARNINGS=1
  fi

  # Summary
  echo ""
  if [ $HAS_ERRORS -eq 0 ]; then
    if [ $HAS_WARNINGS -eq 0 ]; then
      echo -e "${GREEN}✅ Skill validation passed: $SKILL_NAME${NC}"
    else
      echo -e "${GREEN}✅ Skill validation passed with warnings: $SKILL_NAME${NC}"
    fi
    echo ""
    return 0
  else
    echo -e "${RED}❌ Skill validation failed: $SKILL_NAME${NC}"
    echo ""
    return 1
  fi
}

# Main script
if [ "$1" = "--all" ]; then
  echo -e "${BLUE}Validating all skills... (mode: $MODE)${NC}"
  echo ""
  
  for skill_dir in skills/*/; do
    if [ -d "$skill_dir" ]; then
      skill_name=$(basename "$skill_dir")
      
      # Skip special directories
      if [ "$skill_name" = "_archived" ] || [ "$skill_name" = "_template" ]; then
        continue
      fi
      
      TOTAL=$((TOTAL + 1))
      
      if validate_skill "$skill_name"; then
        PASSED=$((PASSED + 1))
      else
        FAILED=$((FAILED + 1))
      fi
    fi
  done
  
  # Summary
  echo "================================"
  echo -e "${BLUE}Validation Summary${NC}"
  echo "================================"
  echo "Total skills: $TOTAL"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
  else
    echo "Failed: $FAILED"
  fi
  echo ""
  
  if [ $FAILED -gt 0 ]; then
    exit 1
  else
    echo -e "${GREEN}✅ All skills validated successfully!${NC}"
    exit 0
  fi
  
elif [ -z "${1:-}" ]; then
  echo "Usage: $0 [--opencode] <skill-name>"
  echo "       $0 [--opencode] --all"
  echo ""
  echo "Modes:"
  echo "  (default)    Claude Code format — universal structural checks, no description length cap"
  echo "  --opencode   add OpenCode-format checks (≤1024-char desc, section headings)"
  echo ""
  echo "Examples:"
  echo "  $0 django-multi-tenant"
  echo "  $0 --all"
  echo "  $0 --opencode --all      # audit OpenCode-fork readiness"
  exit 1
else
  validate_skill "$1"
fi
