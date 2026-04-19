---
stage: plan
slug: {{SLUG}}
created: {{TODAY}}
source: {{SOURCE_PATH_OR_NULL}}
status: draft
project: {{PROJECT_NAME}}
---

# {{TITLE}}

## Context

{{Why this work is being done — the problem or need, what prompted it, the intended outcome. One or two paragraphs.}}

## Problem Frame

{{What is broken or missing today, how it manifests, who feels it. Grounded in observable symptoms, not abstractions.}}

## Requirements Trace

- **R1.** {{Each requirement phrased as a testable outcome, traceable back to the IDEA body or the user's words.}}
- **R2.** ...
- **R3.** ...

## Scope Boundaries

**In scope:**

- {{Files, modules, behaviours explicitly included.}}

**Out of scope:**

- {{Tempting adjacent work that is explicitly deferred.}}

**Explicit non-goals:**

- {{Things the work must NOT do, even if a reasonable reader might assume it would.}}

## Context & Research

### Existing code and patterns to reuse

- {{`<repo-relative/file/path.py>`}} — {{what it does, why it's relevant}}
- ...

### Institutional learnings

- {{`<project>/docs/solutions/<topic>.md`}} — {{the prior learning being applied}}
- {{`mind-vault/skills/<name>/SKILL.md`}} — {{cross-project convention in play}}
- ...

### External references

- {{Framework docs, SDK notes, specs — only when the plan depends on behaviour the agent isn't certain of.}}

## Key Technical Decisions

- **{{Decision name}}.** {{One-line rationale.}}
- **{{Another decision}}.** {{One-line rationale.}}
- ...

## Open Questions

- **Q1. {{Question text}}**
  - **Default:** {{Suggested answer.}}
  - **Trade-off:** {{What's gained vs. lost if default is chosen.}}

## Execution Sequence

1. {{Concrete step — file to create/modify, command to run, test to write}}.
2. ...

## Verification

- {{Command or check that confirms the work landed. Specific enough to copy-paste.}}
- ...

---

**Status:** draft — awaiting {{architect-review | user-approval | both}} before execution.
