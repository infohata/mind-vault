---
id: "023"            # QUOTED — a bare 0NN is YAML-1.1 OCTAL (035 → 29). See SKILL.md §4.
title: "Cross-project idea namespacing — attribute foreign ideas as IDEA-NNN:project"
status: idea          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # QUOTED ids, e.g. ["012"] — or []
superseded_by: null                   # when set: QUOTED id, e.g. "042"
depends_on: []       # QUOTED ids, e.g. ["015"] — or []
related: []             # QUOTED ids, e.g. ["007", "013"] — or []
created: 2026-08-14
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Judgment calls remain: which surfaces adopt the suffix (session prose, memory, devlogs, commit messages, frontmatter fields?), how it interacts with the scrub gate's foreign-ref rule, and whether frontmatter relationship lists ever carry namespaced ids. Needs /plan before any unattended run."
sensitive_paths_cleared: true         # true | false
sensitive_paths_cleared_reason: "Documentation/convention change only — touches skill/rule/reference markdown, no auth, schema, infra, or secrets paths."
---

# IDEA-023: Cross-project idea namespacing — attribute foreign ideas as IDEA-NNN:project

**Status**: 💡 Idea
**Priority**: Medium

**Problem** (or opportunity): Every project keeps an independent `IDEA-NNN` stream, so bare idea numbers collide the moment two projects appear in one conversation, doc, or memory note. Live incident (2026-08-14): a mind-vault session answered a "where were we" question by citing br-docs IDEAs with bare numbers — mind-vault has its own IDEA-016/017 and br-docs has an unrelated IDEA-016/017 — and the user could not tell which repo the session was even on. The `/idea` skill already carries a defensive rule born of the same ambiguity ("never carry a number from another project's stream"), and memory notes routinely write disambiguators by hand ("(project-x) IDEA-178", "teisutis IDEA-112").

**Proposal** (or idea): Adopt a single attribution convention for foreign-project idea references: `IDEA-NNN:project` (e.g. `IDEA-050:br-docs`), where `project` is the repo/directory name. Bare `IDEA-NNN` always means *the current project's* stream. Wire the convention into the write-sites that produce cross-project references:

- `/idea` + `/plan` + `/wrap` + `/compound` skill prose — a one-liner each where they mention referencing other projects' ideas (catchment-style, per the PR #227 wired-pointer convention).
- Auto-memory guidance — memory notes spanning projects use the suffix instead of ad-hoc "(project) IDEA-N" prose.
- Session/report prose — when an agent cites an idea from a repo other than the session's working repo, the suffix is mandatory.
- Scrub-gate synergy: a namespaced ref self-identifies as foreign, making the `/compound` scrub classification mechanical — `IDEA-050:br-docs` in a staged mind-vault diff is a grep-visible scrub candidate, whereas a bare `IDEA-050` needs context to classify.

**Why now**:
- The ambiguity produced a real repo-context mix-up in a live session; the cost is confusion at exactly the moments (multi-repo estates, cross-project compounds, harvest ledgers) the workflow is designed for.
- The BookingRobot estate (~30 repos, several with their own idea streams) multiplies collision surface — br-docs, br-pms, br-vartai each number independently.

**Non-goals**:
- No renumbering of any existing stream, and no global registry — numbering stays per-project and append-only.
- No frontmatter schema change in this idea's first cut: `related`/`depends_on`/`supersedes` stay same-project bare ids. (Invalidating condition: if a real cross-project dependency ever needs to be machine-readable in frontmatter — e.g. sprint-auto sequencing across repos — that becomes its own follow-up idea, not a silent extension of this one.)
- No retro-editing of merged docs/archives; the convention applies forward from adoption.

**Related**: The `/idea` skill's "each project's numbering is independent" rule (SKILL.md § 4) is the defensive half of this problem; this idea adds the attribution half. The `/compound` scrub gate (mind-vault-promotion.md step 5) treats foreign IDEA refs as scrub candidates — namespaced refs make that classification mechanical.
