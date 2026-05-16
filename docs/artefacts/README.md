# Agent Artefacts Knowledge Base

**Purpose**: Structured repository for valuable outputs produced by AI agents during development, research, and validation tasks.

**Benefits**: Persists across projects via mind-vault symlinks, enabling knowledge sharing and preventing loss of high-quality agent work.

## Taxonomy Structure

### Multi-Dimensional Organization

Artefacts are organized by **three dimensions** for flexible discovery:

```
artefacts/
├── by-agent/           # Primary organization by producing agent
│   ├── test-engineer/
│   ├── researcher/
│   ├── architect/
│   └── [other agents]/
├── by-type/            # Secondary organization by artefact type
│   ├── validations/    # Code/skill validation reports
│   ├── research/       # Research findings and analyses
│   ├── analyses/       # Model/topic analyses
│   └── reports/        # General reports and assessments
└── by-topic/           # Tertiary organization by subject matter
    ├── django-architecture/
    ├── ai-models/
    └── [other topics]/
```

### Navigation Strategies

**Find by Agent**: "What did the test-engineer produce?"
- Browse `by-agent/test-engineer/`

**Find by Type**: "What validation reports exist?"
- Browse `by-agent/[agent]/validations/`

**Find by Topic**: "What do we know about Django architecture?"
- Browse `by-topic/django-architecture/`

## How to Contribute

### Adding New Artefacts

1. **Identify the producing agent** (test-engineer, researcher, architect, etc.)
2. **Determine artefact type** (validation, research, analysis, report)
3. **Identify subject topics** for cross-referencing

### File Naming Convention

```
[SUBJECT]_[ACTION]_[QUALIFIER].md
```

**Examples**:
- `DJANGO_ARCHITECTURE_VALIDATION_REPORT.md`
- `TEST_ENGINEER_MODEL_ANALYSIS.md`
- `AGENT_PERFORMANCE_COMPARISON.md`

### Directory Structure Convention

```
by-agent/[agent-name]/[artefact-type]/[filename]
```

**With automatic symlinks to**:
- `by-type/[artefact-type]/[filename]`
- `by-topic/[relevant-topics]/[filename]`

## Current Artefacts

### Architect Artefacts
- **Monitoring Architecture Design** (`analyses/MONITORING_ARCHITECTURE_DESIGN.md`)
  - Comprehensive observability framework design for deployment skill
  - Open source monitoring stack (Prometheus, Grafana, ELK) integration
  - Multi-layer monitoring from infrastructure to business metrics
  - Progressive enhancement from basic to advanced monitoring in deployments

### Test Engineer Artefacts
- **Django Architecture Validation Report** (`validations/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md`)
  - Comprehensive skill validation with critical fixes identified
  - Race conditions, error handling, security improvements
  - Production readiness assessment

- **Model Analysis for Testing Role** (`model-analysis/TEST_ENGINEER_MODEL_ANALYSIS.md`)
  - Comparative analysis of AI models for test-engineer agent
  - Recommendation: Claude Opus 4.5 (80.9% SWE-bench performance)
  - Cost-benefit analysis and implementation guidance

## Usage in Projects

### For Symlinked Projects

Projects symlinking to mind-vault can:

1. **Access existing knowledge**: Browse artefacts for proven patterns
2. **Contribute back**: Add project-specific artefacts to the taxonomy
3. **Leverage agent work**: Use validated research and analysis

### Integration Examples

```bash
# In project symlinked to mind-vault
cd artefacts/by-topic/django-architecture/
# Access validation reports and best practices

cd artefacts/by-agent/test-engineer/validations/
# See how skills were validated for production use
```

## Quality Standards

### Artefact Inclusion Criteria

✅ **Include if**:
- Produced by specialized agent with deep analysis
- Contains actionable insights or critical findings
- Has lasting value beyond immediate task
- Improves future development decisions

❌ **Exclude if**:
- Routine task output without novel insights
- Temporary debugging information
- Project-specific details not generalizable
- Already captured in skills/rules/commands

### Metadata Requirements

Each artefact should include:
- **Production date** and **producing agent**
- **Context** and **purpose** of the analysis
- **Key findings** and **recommendations**
- **Implementation guidance** where applicable

## Maintenance

### Regular Tasks

- **Review and archive**: Move outdated artefacts to archive/
- **Update cross-references**: Ensure symlinks remain valid
- **Consolidate duplicates**: Merge similar artefacts
- **Add topic indexes**: Create overview documents for major topics

### Growth Strategy

As more artefacts accumulate:
- Consider sub-topic organization
- Add search indexes or metadata files
- Create artefact dependency graphs
- Develop automated cross-referencing

## Examples of Future Artefacts

- **Architect validation reports** for system designs
- **Research findings** on new technologies or patterns
- **Performance analysis** of different implementation approaches
- **Security assessments** of proposed architectures
- **Migration planning** documents with risk assessments

---

**Maintained by**: mind-vault curation team
**Last Updated**: 2026-01-28
**Symlinks**: Available in projects linking `~/.config/opencode/skills` → mind-vault
