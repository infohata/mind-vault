#!/bin/bash
# Validate OpenCode skill format
# Usage: ./tools/validate-skills.sh [skill-name]
#        ./tools/validate-skills.sh --all

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    if ! grep -q "^description: " "$SKILL_FILE"; then
      echo -e "${RED}❌ Missing 'description' in frontmatter${NC}"
      HAS_ERRORS=1
    else
      # Check description length
      DESCRIPTION=$(grep "^description: " "$SKILL_FILE" | sed 's/^description: //')
      DESC_LENGTH=${#DESCRIPTION}
      if [ $DESC_LENGTH -lt 1 ]; then
        echo -e "${RED}❌ Description is empty${NC}"
        HAS_ERRORS=1
      elif [ $DESC_LENGTH -gt 1024 ]; then
        echo -e "${RED}❌ Description too long: $DESC_LENGTH characters (max 1024)${NC}"
        HAS_ERRORS=1
      elif [ $DESC_LENGTH -lt 20 ]; then
        echo -e "${YELLOW}⚠️  Description very short: $DESC_LENGTH characters (recommend 100-200)${NC}"
        HAS_WARNINGS=1
      elif [ $DESC_LENGTH -gt 300 ]; then
        echo -e "${YELLOW}⚠️  Description long: $DESC_LENGTH characters (recommend 100-200)${NC}"
        HAS_WARNINGS=1
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

  # Check for recommended sections
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
  echo -e "${BLUE}Validating all skills...${NC}"
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
  
elif [ -z "$1" ]; then
  echo "Usage: $0 <skill-name>"
  echo "       $0 --all"
  echo ""
  echo "Examples:"
  echo "  $0 django-multi-tenant"
  echo "  $0 --all"
  exit 1
else
  validate_skill "$1"
fi
