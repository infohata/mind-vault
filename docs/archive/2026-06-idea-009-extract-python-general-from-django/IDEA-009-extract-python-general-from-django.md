---
id: 009
title: Extract Python-general patterns from the django skill into a python skill
status: in-progress   # idea | in-progress | complete | superseded
priority: low   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by:
depends_on: []       # list of IDEA ids required before starting, or []
related: [IDEA-014]             # list of IDEA ids that share context, or []
created: 2026-05-27
completed:
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Requires judgment on which django references are genuinely Python-general (vs framework-coupled) and how to seed/structure a new top-level skill; carries a rename-before-drop move sequence. Not a blind additive change — leave for /plan."
sensitive_paths_cleared: true         # true | false
sensitive_paths_cleared_reason: "Touches only skills/ and docs/ markdown (a new skills/python/, skills/django/ pointers, the RULE_rename-before-drop pointer). No auth, permission, schema, infra, or secrets paths."
---

# IDEA-009: Extract Python-general patterns from the django skill into a python skill

**Status**: 🚧 In Progress
**Priority**: Low

**Problem** (or opportunity): The `django` skill's `references/` tree holds content that is
Python-general, not django-specific. The first concrete instance is
`MODULE_SPLIT_AST_EXTRACTION.md` — a byte-exact flat-module → package split driven by stdlib
`ast` + `autopep8` + `pyflakes`, with django appearing only in the verification step
(`manage.py check`). Because it lives under `skills/django/references/`, an agent working a
non-django Python project never loads it. Worse, `skills/django/` is currently the *only*
Python home in the vault, so any future Python-general pattern defaults there by gravity — the
misfile compounds with each addition. The forced-atomic dedup in v4.3.7 (PR #148) made the
smell visible: a general rule (`RULE_rename-before-drop`) now points *into* a django reference
for a Python-general sequencing wrinkle.

**Proposal** (or idea): Create a `skills/python/` skill as the base Python layer beneath
`django` / `django-frontend`. Audit `skills/django/references/` for Python-general content and
lift it there — `MODULE_SPLIT_AST_EXTRACTION.md` is the seed. Generalize django-isms (fence
framework-specific verification as a clearly-marked example per the skill-writer
cross-project-portability rule). Keep a pointer in the `django` skill's `## References` so
django consumers still discover the lifted recipes, and repoint
`RULE_rename-before-drop-rationale.md` § *Forced-atomic member* at the new `skills/python/`
path. Sequence as rename-before-drop: move + repoint all references, green gate (link audit),
then drop the django copies in a dedicated commit.

**Why now**:

- The v4.3.7 forced-atomic dedup surfaced the misfile concretely and left a general-rule →
  django-ref cross-link that reads as the wrong home.
- Cheapest while only one reference needs lifting — the move cost grows with every new
  Python-general reference that lands under `django` first.
- Continues the skill-curation lineage of IDEA-002 (body-level debloat) and IDEA-007
  (references-block consolidation): right-sizing where vault content lives.

**Non-goals**:

- Not splitting or merging the `django` / `django-frontend` skills themselves.
- Not creating a thin one-reference skill that never grows — only proceed if the audit finds
  enough Python-general surface, or commit to `python` deliberately as a base layer that will
  accrete (decide in `/plan`).
- No behavior change to the recipes; pure relocation + generalization.

**Related**: [IDEA-014](../../ideas/IDEA-014-stack-agnostic-agents.md) — the stack-agnostic agent architecture resolves generic personas against per-stack skills; the `skills/python/` this idea extracts is exactly that kind of stack-layer skill. Same craft/stack separation principle at a smaller scope; landing this first de-risks 014's skill-contract design.
