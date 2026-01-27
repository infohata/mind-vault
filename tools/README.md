# Mind-Vault Tools

This directory contains utility scripts and tools for maintaining the mind-vault repository.

## Available Tools

### cleanup-contamination.sh
**Purpose**: Detect and remove grok-code-fast-1 tool response contamination from files

**Problem Solved**:
- grok-code-fast-1 model has a bug where `write` tool operations sometimes include tool response format in generated content
- This results in files containing: `</content><parameter name="filePath">`, `(End of file`, `</file>`

**Usage**:
```bash
# From repo root
./tools/cleanup-contamination.sh

# Interactive mode - scans all files, shows contaminated ones, asks for confirmation
# Creates .backup files for safety
```

**Features**:
- ✅ Scans entire repository (excluding .git/, node_modules/, etc.)
- ✅ Detects multiple contamination patterns
- ✅ Interactive confirmation before making changes
- ✅ Creates backup files (.backup extension)
- ✅ Safe - only removes known contamination patterns
- ✅ Colored output for better readability

**Contamination Patterns Detected**:
- `</content>` at end of lines
- `<parameter name="filePath">` lines
- `(End of file - total X lines)` lines
- `</file>` lines

**Example Output**:
```
🔍 Scanning for grok-code-fast-1 tool response contamination...
Repository: /path/to/mind-vault

⚠️  Found 3 contaminated files:
  - docs/artefacts/README.md
  - docs/artefacts/taxonomy.md
  - docs/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md

Do you want to clean up these files? (y/N) y

🧹 Cleaning up contaminated files...
Processing: docs/artefacts/README.md ... CLEANED
Processing: docs/artefacts/taxonomy.md ... CLEANED
Processing: docs/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md ... CLEANED

🎉 Cleanup complete!
Files processed: 3
Files cleaned: 3
Backups saved: *.backup (for cleaned files only)
```

## Adding New Tools

**Guidelines**:
1. Place scripts in this directory
2. Make them executable (`chmod +x`)
3. Add documentation to this README
4. Include usage examples
5. Follow naming: `[purpose]-[action].sh`

**Template for new tools**:
```bash
#!/bin/bash
# Description: What this tool does
# Usage: How to run it
# Author: Who wrote it
# Date: When it was created

set -e  # Exit on error

# Your script here
```

## Maintenance

- **Regular runs**: Run cleanup script after intensive AI agent work
- **Backup management**: Review and remove old .backup files periodically
- **Version control**: Commit tool improvements and new scripts

---

**Tools Directory**: `mind-vault/tools/`
**Last Updated**: 2026-01-27
