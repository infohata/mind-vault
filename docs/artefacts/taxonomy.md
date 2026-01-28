# Artefacts Taxonomy Documentation

## Structure Definition

### Primary Dimension: by-agent/
Organizes artefacts by the AI agent that produced them.

**Directory Structure**:
```
by-agent/
├── [agent-name]/
│   ├── [artefact-type]/
│   │   ├── [artefact-file].md
│   │   └── ...
│   └── [other-artefact-types]/
└── ...
```

**Agent Categories**:
- `test-engineer/` - Validation reports, edge case analysis, quality assessments
- `researcher/` - Research findings, comparative analysis, capability studies
- `architect/` - Design validations, system analysis, architectural reviews
- `curator/` - Quality reviews, consistency checks, documentation improvements
- `frontend/` - UI/UX analysis, component validations, user experience research
- `devops/` - Infrastructure analysis, deployment validations, operations research

### Secondary Dimension: by-type/
Organizes artefacts by their type/purpose.

**Types**:
- `validations/` - Code validation, skill testing, quality assurance reports
- `research/` - Research findings, comparative studies, capability analysis
- `analyses/` - Model analysis, performance studies, in-depth evaluations
- `reports/` - General reports, assessments, documentation

### Tertiary Dimension: by-topic/
Organizes artefacts by subject matter for domain-specific discovery.

**Current Topics**:
- `django-architecture/` - Django framework patterns, architecture validation
- `ai-models/` - AI model capabilities, performance analysis, selection guidance
- `deployment/` - Production deployment patterns, Docker Compose configurations, monitoring integration

## Cross-Referencing System

Artefacts are linked across dimensions using symbolic links:

```
by-type/validations/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md
    ↗️
by-agent/test-engineer/validations/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md
    ↗️
by-topic/django-architecture/DJANGO_ARCHITECTURE_VALIDATION_REPORT.md
```

This allows finding the same artefact through different navigation paths.

## File Organization Rules

### Naming Convention
```
[SUBJECT]_[PURPOSE]_[QUALIFIER].md
```

**Examples**:
- Subject: `DJANGO_ARCHITECTURE`, `TEST_ENGINEER`, `AGENT_PERFORMANCE`
- Purpose: `VALIDATION`, `ANALYSIS`, `COMPARISON`, `ASSESSMENT`
- Qualifier: `REPORT`, `GUIDE`, `STUDY`

### Metadata Standards
Each artefact file must include:
- **Title**: Clear, descriptive title
- **Date**: When the artefact was produced
- **Agent**: Which agent produced it
- **Purpose**: What the artefact accomplishes
- **Status**: Current relevance (Active/Archived/Superseded)

## Maintenance Procedures

### Adding New Artefacts
1. Place primary copy in `by-agent/[agent]/[type]/`
2. Create symlinks in relevant `by-type/` and `by-topic/` directories
3. Update README.md with new artefact descriptions
4. Verify all symlinks are functional

### Archive Process
1. Move outdated artefacts to `archive/` subdirectory
2. Update any referencing symlinks
3. Note archival reason in artefact header
4. Update README.md

### Quality Control
- **Relevance Check**: Monthly review of artefact usefulness
- **Duplicate Consolidation**: Merge overlapping artefacts
- **Link Validation**: Quarterly symlink integrity check
- **Topic Evolution**: Add new topic directories as needed

## Integration with Mind-Vault

### Symlink Propagation
Projects symlinking mind-vault automatically get:
- Access to all artefacts via relative paths
- Cross-project knowledge sharing
- Consistent artefact organization

### Usage in Agent Workflows
Agents can reference artefacts for:
- **Precedent research**: "How was similar validation done?"
- **Quality standards**: "What level of analysis is expected?"
- **Knowledge accumulation**: "Build on existing findings"

## Future Extensions

### Planned Enhancements
- **Search index**: JSON metadata file for programmatic access
- **Dependency tracking**: Which artefacts reference others
- **Version control**: Artefact evolution tracking
- **Automated linking**: Script to maintain cross-references

### Scalability Considerations
- **Sub-topic organization**: `by-topic/django/models/`, `by-topic/django/views/`
- **Temporal organization**: `by-date/2026-01/`, `by-date/2026-02/`
- **Project attribution**: `by-project/teisutis/`, `by-project/mind-vault/`

---

**Taxonomy Version**: 1.0
**Last Updated**: 2026-01-27
**Maintained by**: mind-vault curation agent
