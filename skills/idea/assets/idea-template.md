---
id: "{{NNN}}"            # QUOTED — a bare 0NN is YAML-1.1 OCTAL (035 → 29). See SKILL.md §4.
title: "{{TITLE}}"       # QUOTED — an unquoted `:` in the title breaks the whole frontmatter.
status: idea          # idea | in-progress | complete | superseded
priority: {{PRIORITY}}   # high | medium | low
supersedes: {{SUPERSEDES_LIST}}       # QUOTED ids, e.g. ["012"] — or []
superseded_by: null                   # when set: QUOTED id, e.g. "042"
depends_on: {{DEPENDS_ON_LIST}}       # QUOTED ids, e.g. ["015"] — or []
related: {{RELATED_LIST}}             # QUOTED ids, e.g. ["007", "013"] — or []
created: {{TODAY}}
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: {{AUTO_SAFE}}                                     # true | false
auto_safe_reason: "{{AUTO_SAFE_REASON}}"                     # why safe, or what blocks — 1-2 sentences
sensitive_paths_cleared: {{SENSITIVE_PATHS_CLEARED}}         # true | false
sensitive_paths_cleared_reason: "{{SENSITIVE_REASON}}"       # any auth/permission/schema/infra touch? — 1-2 sentences
---

# IDEA-{{NNN}}: {{TITLE}}

**Status**: 💡 Idea
**Priority**: {{PRIORITY_TITLECASE}}

**Problem** (or opportunity): {{PROBLEM}}

**Proposal** (or idea): {{PROPOSAL}}

**Why now**:
- {{WHY_NOW}}

**Non-goals**:
- {{NON_GOALS}}

**Related**: {{RELATED_PROSE}}
