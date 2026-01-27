#!/bin/bash

# grok-code-fast-1 Write Tool Contamination Cleanup Script
# This script detects and removes tool response format contamination
# caused by grok-code-fast-1 model bug in write operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Contamination patterns to detect and remove
PATTERNS=(
    "</content>$"           # Closing content tag at end of line
    "^<parameter name="     # Parameter lines
    "^(End of file"         # File end markers
    "^</file>$"            # Closing file tags
)

# Files to exclude from scanning
EXCLUDE_PATTERNS=(
    ".git/"
    "node_modules/"
    "*.pyc"
    "*.log"
    "*.tmp"
    "*.swp"
    "*.bak"
    "*~"
)

echo -e "${BLUE}🔍 Scanning for grok-code-fast-1 tool response contamination...${NC}"
echo "Repository: $REPO_ROOT"
echo

# Build find command with exclusions
FIND_CMD="find \"$REPO_ROOT\" -type f"
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    FIND_CMD="$FIND_CMD -not -path \"*/$pattern*\""
done

# Find contaminated files
CONTAMINATED_FILES=()
while IFS= read -r file; do
    # Skip binary files
    if file "$file" | grep -q "text"; then
        for pattern in "${PATTERNS[@]}"; do
            if grep -q "$pattern" "$file" 2>/dev/null; then
                CONTAMINATED_FILES+=("$file")
                break
            fi
        done
    fi
done < <(eval "$FIND_CMD")

if [ ${#CONTAMINATED_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No contaminated files found!${NC}"
    exit 0
fi

echo -e "${YELLOW}⚠️  Found ${#CONTAMINATED_FILES[@]} contaminated files:${NC}"
for file in "${CONTAMINATED_FILES[@]}"; do
    echo "  - ${file#$REPO_ROOT/}"
done
echo

# Ask for confirmation
echo -e "${YELLOW}Do you want to clean up these files? (y/N)${NC}"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo -e "${BLUE}🧹 Cleaning up contaminated files...${NC}"

# Clean each file
CLEANED_COUNT=0
for file in "${CONTAMINATED_FILES[@]}"; do
    echo -n "Processing: ${file#$REPO_ROOT/} ... "

    # Create backup
    cp "$file" "${file}.backup"

    # Clean the file
    temp_file=$(mktemp)
    cleaned=false

    # Process line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        skip_line=false

        # Check each pattern
        for pattern in "${PATTERNS[@]}"; do
            if [[ "$line" =~ $pattern ]]; then
                # Remove the contamination
                case "$pattern" in
                    "</content>$")
                        line="${line%</content>}"
                        ;;
                    "^<parameter name="|"^(End of file"|"^</file>$")
                        skip_line=true
                        ;;
                esac
                cleaned=true
                break
            fi
        done

        # Write line if not skipped
        if [ "$skip_line" = false ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$file"

    # Replace original file
    mv "$temp_file" "$file"

    if [ "$cleaned" = true ]; then
        echo -e "${GREEN}CLEANED${NC}"
        ((CLEANED_COUNT++))
    else
        echo -e "${YELLOW}NO CHANGES${NC}"
        # Remove backup if no changes
        rm "${file}.backup"
    fi
done

echo
echo -e "${GREEN}🎉 Cleanup complete!${NC}"
echo "Files processed: ${#CONTAMINATED_FILES[@]}"
echo "Files cleaned: $CLEANED_COUNT"
echo "Backups saved: ${file}.backup (for cleaned files only)"

if [ $CLEANED_COUNT -gt 0 ]; then
    echo
    echo -e "${BLUE}💡 Tip: Review the .backup files before deleting them${NC}"
    echo -e "${BLUE}   Run: find $REPO_ROOT -name \"*.backup\" -delete${NC}"
fi
