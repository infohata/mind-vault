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

### 5. Integrate into Development Workflow
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

### 6. Monitoring Architecture Design
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

## References
- [Agent Artefacts Knowledge Base](../docs/artefacts/README.md)
- [Multi-dimensional Taxonomy](../docs/artefacts/taxonomy.md)
- [Django Architecture Skill](../skills/django-architecture/SKILL.md)
- [Git Workflow Rule](../rules/RULE_git-workflow.md)