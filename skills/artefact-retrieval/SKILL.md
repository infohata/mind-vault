---
name: artefact-retrieval
description: Search outside the project (in IDE plans, AI agent memory, or /tmp temporary storage) and retrieve standalone artefacts, research, or validation logs to bring them inside the project repository.
---

# SKILL_artefact-retrieval

## Overview
Systematic approach for retrieving and utilizing artefacts from the mind-vault knowledge base, enabling agents and developers to access validated research, analysis, and documentation efficiently across projects.

## When to Use
- Starting new projects that can leverage existing validated knowledge
- Researching proven patterns before implementing solutions
- Validating assumptions against documented findings
- Building on previous agent analysis and validation work
- Ensuring consistency with established best practices
- Avoiding re-inventing solutions already documented
- Checking for Cursor plan mode artefacts that should be saved to the project

## Pattern

### 1. Identify Retrieval Context
Determine what type of knowledge you need:

```bash
# For pattern validation
cd docs/artefacts/by-agent/test-engineer/validations/

# For research findings
cd docs/artefacts/by-agent/researcher/research/

# For model analysis
cd docs/artefacts/by-agent/[agent]/model-analysis/
```

### 2. Query by Multiple Dimensions
Use the multi-dimensional taxonomy for comprehensive discovery:

```bash
# Find by Agent
find docs/artefacts/by-agent/researcher/ -name "*.md" | head -10

# Find by Type
find docs/artefacts/by-type/validations/ -name "*DJANGO*" -type f

# Find by Topic
find docs/artefacts/by-topic/django-architecture/ -name "*.md"
```

### 3. Implement Structured Retrieval
Create reusable retrieval patterns:

```python
import os
import glob
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

def retrieve_artefacts(query_type, subject, agent=None):
    """
    Retrieve artefacts matching specific criteria.
    
    Args:
        query_type: 'validation', 'research', 'analysis', 'report' or None
        subject: topic or pattern name
        agent: specific agent name (optional)
    
    Returns:
        List of file paths sorted by modification time (newest first)
    
    Raises:
        ValueError: If parameters contain invalid characters
    """
    # Input validation
    if query_type and not query_type.replace('-', '').replace('_', '').isalnum():
        raise ValueError(f"Invalid query_type: {query_type}")
    
    if subject and not subject.replace('-', '').replace('_', '').isalnum():
        raise ValueError(f"Invalid subject: {subject}")
    
    base_paths = []
    
    if query_type:
        base_paths.append(f"docs/artefacts/by-type/{query_type}")
    
    if subject:
        base_paths.append(f"docs/artefacts/by-topic/{subject}")
    
    if agent:
        base_paths.append(f"docs/artefacts/by-agent/{agent}")
    
    results = []
    for path in base_paths:
        if os.path.exists(path):
            # Fixed glob pattern with proper path separator
            pattern = f"{path}/**/*{subject or ''}*.md"
            try:
                for file in glob.glob(pattern, recursive=True):
                    # Validate file path to prevent traversal attacks
                    if os.path.commonpath([os.path.abspath(file), os.path.abspath(path)]) == os.path.abspath(path):
                        results.append(file)
            except Exception as e:
                logger.warning(f"Error searching in {path}: {e}")
    
    return sorted(set(results), key=lambda x: os.path.getmtime(x), reverse=True)

# Example usage
django_validations = retrieve_artefacts('validation', 'django', 'test-engineer')
```

### 4. Validate Artefact Relevance
Always assess artefact applicability:

```python
def validate_artefact_relevance(artefact_path, current_context):
    """
    Check if artefact applies to current project context.
    
    Args:
        artefact_path: path to artefact file
        current_context: dict with project details (can be None)
    
    Returns:
        bool: True if artefact is relevant
    
    Raises:
        FileNotFoundError: If artefact file doesn't exist
    """
    # Input validation
    if current_context is None:
        current_context = {}
    
    if not os.path.exists(artefact_path):
        raise FileNotFoundError(f"Artefact not found: {artefact_path}")
    
    try:
        with open(artefact_path, 'r', encoding='utf-8') as f:
            content = f.read().lower()
    except Exception as e:
        logger.error(f"Error reading artefact {artefact_path}: {e}")
        return False
    
    # Check applicability criteria
    checks = {
        'framework': current_context.get('framework', ''),
        'python_version': current_context.get('python_version', ''),
        'production_ready': current_context.get('production_ready', False),
    }
    
    relevance_score = 0
    for key, value in checks.items():
        if value and str(value).lower() in content:
            relevance_score += 1
    
    return relevance_score >= 2  # Require 2+ matches
```

### 5. Retrieve Cursor Plan Mode Artefacts

Cursor's Plan Mode generates structured plans at `~/.cursor/plans/`. These are
valuable artefacts that often get lost because they live outside the project tree.

**Plan file format** (`*.plan.md` with YAML frontmatter):
```yaml
---
name: IDEA-057 Text File Preview
overview: Add text/code/CSV/Markdown file upload support...
todos:
  - id: vendor-assets
    content: Download highlight.min.js + CSS...
    status: completed
  - id: server-mime
    content: Add _validate_file_mime() helper...
    status: completed
isProject: false
---
```

**Discovery — find plans relevant to the current project:**
```bash
# List all Cursor plans (newest first)
ls -lt ~/.cursor/plans/*.plan.md

# Find plans matching a topic (e.g. "dashboard", "auth", "IDEA-047")
grep -l "dashboard\|IDEA-006" ~/.cursor/plans/*.plan.md

# Show plan names and statuses at a glance
for f in ~/.cursor/plans/*.plan.md; do
    name=$(grep "^name:" "$f" | head -1 | sed 's/name: //')
    echo "$f → $name"
done
```

**Save completed plans to the project artefact tree:**
```bash
# Copy a completed plan into the project artefacts
cp ~/.cursor/plans/idea-057_text_file_preview_52778d48.plan.md \
   docs/artefacts/by-type/plans/IDEA-057-text-file-preview.plan.md

# Symlink into the topic taxonomy
ln -sf ../../by-type/plans/IDEA-057-text-file-preview.plan.md \
   docs/artefacts/by-topic/attachments/IDEA-057-text-file-preview.plan.md
```

**When to save plans:**
- Plan is completed (all todos `status: completed`)
- Plan documents a non-trivial architectural decision
- Plan could inform future similar work (reusable patterns)
- Plan captures research/exploration that predates implementation

**Batch check for unsaved plans (run periodically):**
```bash
#!/bin/bash
# Find Cursor plans that might belong to this project
# Match on IDEA numbers, feature names, or module names from AGENTS.md
PROJECT_KEYWORDS="teisutis|IDEA-|kb|ai_service|dashboard"

echo "=== Cursor plans potentially related to this project ==="
for f in ~/.cursor/plans/*.plan.md; do
    if grep -qiE "$PROJECT_KEYWORDS" "$f"; then
        name=$(grep "^name:" "$f" | head -1 | sed 's/name: //')
        basename=$(basename "$f")
        # Check if already saved to project
        if ! find docs/artefacts/ -name "*${basename%.*}*" -o -name "*$(echo "$name" | tr ' ' '-')*" 2>/dev/null | grep -q .; then
            echo "  NOT SAVED: $name ($basename)"
        fi
    fi
done
```

### 6. Retrieve Gemini Agent Artefacts

Gemini (Antigravity) agents generate project-specific artefacts (like implementation plans, analyses, and walkthroughs) stored within isolated conversational brains at `~/.gemini/antigravity/brain/<conversation-id>/artifacts/`.

To ensure permanent retention and cross-session knowledge sharing, valuable Gemini artefacts should be extracted into the project repository.

**Discovery — find recent Gemini artefacts:**
```bash
# List all Gemini conversational brains (newest first)
ls -lt ~/.gemini/antigravity/brain/

# Look for generated artefacts in a specific recent conversation
ls -lt ~/.gemini/antigravity/brain/<conversation-id>/artifacts/
```

**Save valuable Gemini artefacts to the project tree:**
```bash
# Copy an analysis or implementation plan into the project artefacts
cp ~/.gemini/antigravity/brain/<conversation-id>/artifacts/devlog_analysis.md \
   docs/artefacts/by-type/analyses/devlog_analysis.md

# Symlink into the topic taxonomy
ln -sf ../../by-type/analyses/devlog_analysis.md \
   docs/artefacts/by-topic/security/devlog_analysis.md
```

**When to save Gemini artefacts:**
- The agent summarized complex architectural changes or log discoveries
- The artefact contains a reusable implementation plan that was successfully executed
- The artefact acts as a "walkthrough" explaining a new system to developers

### 7. Integrate into Development Workflow
Make artefact retrieval part of standard processes:

```bash
# Pre-implementation checklist
#!/bin/bash
echo "🔍 Checking for existing artefacts..."

PROJECT_TYPE="${1:-django}"
AGENT="${2:-researcher}"

# Find relevant artefacts
find docs/artefacts/ -name "*${PROJECT_TYPE}*" -type f | head -5

# Check for validation reports
if [ -d "docs/artefacts/by-agent/test-engineer/validations/" ]; then
    echo "✅ Validation artefacts available"
    ls docs/artefacts/by-agent/test-engineer/validations/ | grep -i "$PROJECT_TYPE"
fi

echo "📚 Review artefacts before implementation"
```

## Why It's Generic
This pattern applies universally across software development projects because:

- **Knowledge preservation**: Captures institutional memory that would otherwise be lost
- **Consistency enforcement**: Ensures teams build on validated approaches
- **Efficiency gains**: Prevents redundant research and validation cycles
- **Quality assurance**: Leverages peer-reviewed agent outputs
- **Scalability**: Works regardless of project size or team composition

## Example Use Cases

### 1. Django Project Onboarding
New team members automatically access validated Django patterns:
```
docs/artefacts/by-topic/django-architecture/
├── DJANGO_ARCHITECTURE_VALIDATION_REPORT.md
├── ASGI_CONFIGURATION_ANALYSIS.md
└── MODEL_DESIGN_PATTERNS.md
```

### 2. Multi-Tenant Implementation
Retrieve proven multi-tenant patterns before custom development:
```
docs/artefacts/by-agent/architect/analyses/
└── MULTI_TENANT_ARCHITECTURE_REVIEW.md
```

### 3. Monitoring Architecture Design
Review observability patterns for production applications:
```
docs/artefacts/by-agent/architect/analyses/
├── MULTI_TENANT_ARCHITECTURE_REVIEW.md
└── MONITORING_ARCHITECTURE_DESIGN.md
```

### 4. Production Readiness Validation
Check existing validation reports before deployment:
```
docs/artefacts/by-type/validations/
├── DJANGO_PRODUCTION_VALIDATION.md
├── WEBSOCKET_SCALING_ASSESSMENT.md
├── DATABASE_PERFORMANCE_ANALYSIS.md
└── DEPLOYMENT_APPROACH_VALIDATION.md
```

### 5. Deployment Pattern Research
Access validated deployment patterns before implementation:
```
docs/artefacts/by-topic/deployment/
├── DEPLOYMENT_PATTERN_ANALYSIS.md
├── DEPLOYMENT_ARCHITECTURE_DESIGN.md
└── MONITORING_ARCHITECTURE_DESIGN.md
```

### 6. Cursor Plan Mode Artefacts
Completed plans saved from `~/.cursor/plans/` into the project:
```
docs/artefacts/by-type/plans/
├── IDEA-057-text-file-preview.plan.md
├── IDEA-006-user-dashboard.plan.md
└── fix-invitation-accept-flow.plan.md
```

**Artefact sources (complete list):**

| Source | Location | Format |
|---|---|---|
| Agent outputs | `docs/artefacts/by-agent/` | Markdown |
| Research / validations | `docs/artefacts/by-type/` | Markdown |
| Topic cross-refs | `docs/artefacts/by-topic/` | Symlinks |
| Cursor plans | `~/.cursor/plans/*.plan.md` | YAML frontmatter + Markdown |
| Agent transcripts | `~/.cursor/projects/<project>/agent-transcripts/` | JSONL |
| Gemini artefacts | `~/.gemini/antigravity/brain/<id>/artifacts/` | Markdown |
| Gemini transcripts | `~/.gemini/antigravity/brain/<id>/.system_generated/logs/overview.txt` | Text |

## References
- [Agent Artefacts Knowledge Base](../docs/artefacts/README.md)
- [Multi-dimensional Taxonomy](../docs/artefacts/taxonomy.md)
- [Django Architecture Skill](../skills/django-architecture/SKILL.md)
- [Git Workflow Rule](../rules/RULE_git-workflow.md)