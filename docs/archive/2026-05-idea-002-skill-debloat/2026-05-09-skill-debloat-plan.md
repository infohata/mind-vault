---
stage: plan
slug: skill-debloat
created: 2026-05-09
source: ./IDEA-002-skill-debloat.md
status: shipped
project: mind-vault
---

# Skill debloat — extract over-budget SKILL.md bodies into references/

## Context

Three SKILL.md bodies exceed the ~500-line soft budget set by `docs/guides/SKILL_SPECIFICATION.md`. Every `Skill` tool invocation loads the full SKILL.md body into the consuming agent's context, so bloat is paid as a per-activation token cost. PR #106 established the rules-reorg precedent — domain-specific patterns moved from always-on `rules/` to load-on-demand `skills/<owner>/references/`. This IDEA extends the same discipline from `rules/` to over-budget SKILL.md bodies themselves: long inline patterns ship as load-on-demand references, the SKILL.md body keeps a one-paragraph stub + pointer.

`/wrap` is the highest-leverage target — it gets invoked twice per IDEA under sprint-auto (S5 pre-merge eval-gate emission + S8 post-merge wrap). Trim there compounds across every sprint.

## Problem Frame

Audit captured 2026-05-09 (line counts re-verified against current `main` tip `f9a7544`):

| Skill | Lines | Top extract candidates (this PR's Phase 1 + IDEA-body Phase 2/3) |
| --- | --- | --- |
| `skills/wrap/SKILL.md` | 546 | Step 5 worktree teardown (L234-340 = 107L), Step 7 eval-gate emission (L369-445 = 77L), Step 8 atomic merge (L446-518 = 73L). Total **~257L = 47%** of body. |
| `skills/django-frontend/SKILL.md` | 920 | App-shell layout (L117-226 = 110L), Alpine.store coordinators (L271-354 = 84L), Active-state tracking (L355-420 = 66L), Template comment syntax (L709-751 = 43L), SCSS vendor-import (L779-817 = 39L), JS sibling-comment trap (L752-778 = 27L). Total **~369L = 40%** of body. Deferred to Phase 2 PR. |
| `skills/django/SKILL.md` | 802 | Distributed bloat — Cross-entity session-filter (~78L), LLM output post-processing (~65L), FileField MIME (~54L), Env-driven allowlists (~53L), ManifestStaticFilesStorage (~50L). No single dominant section. Deferred to Phase 3 PR (lowest leverage, hardest to extract cleanly). |

The cost manifests as: every `/wrap` invocation pulls 546 SKILL.md lines into context; every `/work` that touches a frontend pattern pulls 920 lines from django-frontend; etc. Multiplied across sprint-auto's per-IDEA invocations and bugbot fix cycles, the steady-state token bill is high enough that the trim earns its keep.

## Requirements Trace

- **R1.** `/wrap` SKILL.md drops to ≤ 350L by extracting Step 5 (teardown), Step 7 (eval-gate), Step 8 (atomic merge) bodies into `skills/wrap/references/{WORKTREE_TEARDOWN,EVAL_GATE_EMISSION,ATOMIC_MERGE}.md`. Each step's place in the SKILL body becomes a one-paragraph stub explaining when the step fires + a load-on-demand pointer.
- **R2.** Each extracted reference file is self-contained — a reader landing on the reference via the SKILL body's pointer must understand what triggers the step, what to do, what the failure modes are, and what comes next, without needing to re-read the SKILL body.
- **R3.** Cross-references that previously pointed at the SKILL body's step anchors (e.g. another skill's "see `skills/wrap/SKILL.md#step-7-eval-gate-emission`") get rewritten to point at the new reference file. No broken links.
- **R4.** `skills/wrap/SKILL.md` continues to function as the canonical entry point — every step still has a numbered presence in the body so the linear reader can follow the wrap workflow end-to-end without jumping to references unless they need mechanics.
- **R5.** PR scope is **Phase 1 (wrap) only**. Phase 2 (django-frontend) and Phase 3 (django) are deferred to follow-up PRs after this PR merges and the extraction pattern is validated.
- **R6.** No behaviour change. The wrap workflow's contract — what gets done, in what order, with what side-effects — is identical pre and post extraction. Only file layout + load mechanism changes.

## Scope Boundaries

**In scope:**

- `skills/wrap/SKILL.md` — Steps 5, 7, 8 body extraction + stub rewrite + References list update.
- `skills/wrap/references/` — three new files: `WORKTREE_TEARDOWN.md`, `EVAL_GATE_EMISSION.md`, `ATOMIC_MERGE.md`.
- Cross-reference rewrites in any file that currently links to those step anchors (verify via repo-wide grep).
- CHANGELOG entry for the extraction.

**Out of scope (deferred to Phase 2/3 PRs):**

- `skills/django-frontend/SKILL.md` — six sections enumerated in IDEA body, total ~369L. Larger cross-reference surface (teisutis archives + sibling skills); ships as its own PR after Phase 1's pattern validates.
- `skills/django/SKILL.md` — distributed bloat with no single dominant section. Lowest priority; per-section judgment call on whether each inline body earns extraction.

**Explicit non-goals:**

- Not rewriting wrap's step logic. The reference file is verbatim relocation of the existing step body, not a refactor.
- Not enforcing a hard 500-line cap on every skill. The SPECIFICATION's target is soft; skills with every-line-earned bodies stay over budget.
- Not extracting the wrap body's smaller sections (Steps 1-4, Step 6, Mode detection, Scope detection) — extraction overhead exceeds the savings for sub-30L blocks.
- Not touching `skills/wrap/assets/` or `skills/wrap/agents/` — only SKILL.md + new references/ files.
- Not changing the four `rules/` files — PR #106 already settled which rules are always-on.

## Context & Research

### Existing code and patterns to reuse

- `skills/wrap/references/` — already exists with three reference files (per `ls skills/wrap/references/` baseline check). New extracts join the existing pattern; no new directory.
- `skills/sprint-auto/references/` — established the precedent for naming convention (`UPPERCASE_NAME.md`) and the "stub + pointer" pattern in the parent SKILL body. PR #106's sprint-auto/SKILL.md updates are the reference.
- `skills/django-frontend/references/HTMX_ALPINE_WAITS.md` — fresh-from-PR-#106 example of a self-contained reference file with code blocks, decision trees, and "when to use" framing. Mirror this shape for the wrap extracts.

### Institutional learnings

- `docs/guides/SKILL_SPECIFICATION.md` — soft budget ~500 lines, References list at bottom of every SKILL.md.
- `mind-vault/CHANGELOG.md` PR #106 entry — documents the rules-reorg pattern (always-on vs load-on-demand) that this IDEA extends.
- `~/.claude/projects/-home-kestas-projects-mind-vault/memory/feedback_skill_references_outcome_not_plan.md` — References lists must point at outcome (live implementation), not plan (archived ROADMAPs). Apply when adding the three new entries to wrap/SKILL.md's References list — link to the new `references/*.md` files, NOT to this plan.
- `~/.claude/projects/-home-kestas-projects-mind-vault/memory/project_rules_curation_principle.md` — the broadly-applicable-vs-domain-specific criterion. Wrap's Step 5/7/8 are intrinsically wrap-internal — they don't fire across multiple skills, only when wrap activates — so reference (load-on-demand) is the right home, not rule (always-on).

### External references

- None required. This is a pure-internal reorg with no framework or SDK behaviour at issue.

## Key Technical Decisions

- **One reference file per extracted step**, not a single combined `WRAP_STEP_BODIES.md`. Per-step files are self-contained for the reader who lands on one via SKILL.md's pointer; combining them re-introduces the bloat we're extracting.
- **Stub format in SKILL.md**: 2-4 sentences explaining when the step fires + skip conditions at a glance + pointer link. The stub must let the linear reader decide "is this step relevant to my current run?" without clicking through to the reference. Mechanics (commands, edge cases, failure modes) live in the reference.
- **Reference file structure**: H1 title, brief "When this fires" preamble, then verbatim relocation of the existing step body (commands, decision tables, edge cases). No new prose — this is a relocation, not a rewrite.
- **Filename convention**: `WORKTREE_TEARDOWN.md`, `EVAL_GATE_EMISSION.md`, `ATOMIC_MERGE.md` — UPPER_SNAKE matching existing references/ files, semantic-not-step-numbered AND concept-not-lifecycle-scoped (so renumbering wrap steps later, OR relaxing pre-merge/post-merge gating, doesn't invalidate filenames). Lifecycle qualifiers (e.g. "post-merge only") stay in the SKILL.md stub, not the filename.
- **Cross-reference rewrites scoped to repo only.** Memory entries that reference wrap step anchors stay as-is — memory is per-machine and not part of the contract.
- **References list update in wrap/SKILL.md**: add three new entries pointing at the new files. Per the outcome-not-plan rule, do NOT cite this plan or its archive dir from the References list.
- **Architect review runs as subagent invocation** (`Agent` with `subagent_type: feature-dev:code-architect`), not self-review — round-trip is cheap on a short plan, independent context catches author blind spots. (Resolved from Q1.)
- **IDEA-001 frontmatter cleanup is out of scope** for this PR — IDEA-001 still says `in-progress` despite PR #106's merge; that's a pending separate `/wrap` invocation, not part of IDEA-002's diff. Bundling would muddy the diff. (Resolved from Q2.)

## Open Questions

- **Q1. Stub anchor stability — when a reader does `Skill wrap` then needs to jump to the eval-gate reference, do we hard-link via fenced markdown link in the stub, or rely on the References list at the bottom?**
  - **Default:** Both. The stub carries an inline link (`see [WORKTREE_TEARDOWN.md](references/WORKTREE_TEARDOWN.md) for mechanics`) AND the References list at the bottom gets a corresponding entry. The inline link is the fast path; the References list is the discovery path for someone reading the SKILL body sequentially.
  - **Trade-off:** Two pointers means two places to keep in sync if a file moves. Acceptable cost — it's only three references being added.

## Execution Sequence

The whole sequence runs on `feature/idea-002-skill-debloat` (already created). Per `RULE_rename-before-drop`, references are added FIRST and the SKILL.md body is extracted LAST in each step's commit, so per-commit `git bisect` stays clean.

### Phase 1.0 — Architect review

1. Invoke `feature-dev:code-architect` subagent with this plan as input. See `skills/plan/references/architect-handoff.md` for the handoff protocol.
2. Apply architect findings inline to this plan; flip `status: shipped` → `status: shipped` once findings are integrated.

### Phase 1.1 — Extract wrap Step 5 (worktree teardown)

3. Create `skills/wrap/references/WORKTREE_TEARDOWN.md` containing the verbatim step body (current SKILL.md L234-340) with H1 + "When this fires" preamble.
4. Edit `skills/wrap/SKILL.md`:
   - Replace L234-340 step body with a 2-4-sentence stub + pointer link.
   - Add References list entry: `[skills/wrap/references/WORKTREE_TEARDOWN.md](references/WORKTREE_TEARDOWN.md) — destructive teardown mechanics for post-merge runs in worktrees`.
5. Verify no broken links via `grep -rn 'wrap/SKILL.md#step-5\|wrap/SKILL.md#worktree-teardown'` repo-wide. Rewrite to point at the new reference.
6. Commit: `refactor(wrap): extract Step 5 worktree teardown to references/WORKTREE_TEARDOWN.md`.

### Phase 1.2 — Extract wrap Step 7 (eval-gate emission)

7. Create `skills/wrap/references/EVAL_GATE_EMISSION.md` containing verbatim step body (current SKILL.md L369-445).
8. Edit `skills/wrap/SKILL.md` Step 7: stub + pointer + References list entry.
9. Verify no broken links via `grep -rn 'wrap/SKILL.md#step-7\|wrap/SKILL.md#eval-gate'`.
10. Commit: `refactor(wrap): extract Step 7 eval-gate emission to references/EVAL_GATE_EMISSION.md`.

### Phase 1.3 — Extract wrap Step 8 (atomic merge)

11. Create `skills/wrap/references/ATOMIC_MERGE.md` containing verbatim step body (current SKILL.md L446-518). **Update the forward-reference inside the body** that points back at Step 5 — replace step-numbered references (e.g. `# 4. Step 5's destructive worktree teardown becomes available now …`) with reference-named pointers (e.g. `# 4. Run WORKTREE_TEARDOWN.md (linked from SKILL.md Step 5) now that git branch -d will agree`). This applies the same semantic-not-step-numbered discipline to internal forward-refs as to filenames.
12. Edit `skills/wrap/SKILL.md` Step 8: stub + pointer + References list entry.
13. Verify no broken links via `grep -rn 'wrap/SKILL.md#step-8\|wrap/SKILL.md#atomic-merge'`.
14. Commit: `refactor(wrap): extract Step 8 atomic merge to references/ATOMIC_MERGE.md`.

### Phase 1.4 — Final sweep + verification

15. Run repo-wide cross-reference checker (Python broken-link verifier from PR #106) on touched files. Confirm zero broken links.
16. Verify SKILL.md line count: `wc -l skills/wrap/SKILL.md` — target ≤ 350L (down from 546L; ~196L saved net of stubs).
17. Update `CHANGELOG.md` with a Phase 1 entry referencing this IDEA archive dir.
18. Commit: `docs(changelog): IDEA-002 Phase 1 — wrap SKILL.md debloat`.

### Phase 1.5 — PR

19. `git push -u origin feature/idea-002-skill-debloat`.
20. `gh pr create` with body referencing IDEA-002 archive dir + plan + Phase 2/3 deferral note.
21. Hand back to user; await review + merge.

## Verification

- `wc -l skills/wrap/SKILL.md` returns ≤ 350 (was 546).
- `wc -l skills/wrap/references/{WORKTREE_TEARDOWN,EVAL_GATE_EMISSION,ATOMIC_MERGE}.md` — each ~75-110L (matching the source step bodies).
- Repo-wide grep finds zero broken links to the old step anchors.
- Repo-wide grep confirms each new reference file is linked from the wrap SKILL.md body's stub + References list (so the reference is reachable for both readers — the one using the inline pointer and the one scanning the References list).
- Manually re-read `skills/wrap/SKILL.md` end-to-end as a linear reader: every step is still numbered + present + has enough body to know when it fires + when to skip. The skill remains comprehensible without ever clicking through to a reference.
- Architect-review subagent verdict: ARCHITECTURALLY SOUND.

---

**Status:** ready — architect-review verdict REQUIRES ABSTRACTION (3 findings) integrated 2026-05-09. Findings: (1) `POST_MERGE_TEARDOWN` → `WORKTREE_TEARDOWN` (lifecycle qualifier moved from filename to stub), (2) ATOMIC_MERGE body's Step-5 forward-reference rewritten to reference-named, (3) Q1+Q2 collapsed into Key Technical Decisions. Cleared for /work execution.
