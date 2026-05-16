# Manual-eval issues tracker artefact

The eval-checklist that `/wrap` Step 7 emits lists *scenarios for the human to walk*. The **manual-eval issues tracker** is the back-and-forth log that captures *issues found while walking those scenarios* with stable identifiers across cycles.

The two artefacts are distinct:

| Artefact | Authored by | Purpose | Lifecycle |
|---|---|---|---|
| `<DATE>-manual-evaluation.md` (eval-checklist) | `/wrap` Step 7 | Scenarios to walk | One-shot, written pre-merge, walked post-merge by reviewer |
| `MANUAL_EVAL_ISSUES.md` (this tracker) | Agent + human, iteratively | Issues surfaced during the walk | Multi-cycle, lives until all rows are 🟢 VERIFIED |

## When to introduce the tracker

The first time a manual-eval gated IDEA produces a regression report. Don't wait for the third — once back-and-forth gets confused ("the user-menu thing is broken… the *other* user-menu thing"), you've already lost the cycle to ambiguity.

## The artefact

A single Markdown file at `docs/archive/<YYYY-MM-idea-NNN-slug>/MANUAL_EVAL_ISSUES.md` alongside the eval-checklist:

```markdown
| ID  | Surface / scope        | Severity | Description                                                  | Status        | Fix SHA                                  |
|-----|------------------------|----------|--------------------------------------------------------------|---------------|------------------------------------------|
| M0  | Bugbot review          | medium   | Scroll events don't bubble; drilling fix.                    | 🟢 VERIFIED  | abc1234 — confirmed 2026-05-06           |
| M1  | Centre / drawer panes  | high     | Long Lithuanian compounds overflow narrow panes.             | 🟢 VERIFIED  | def5678                                  |
| M2  | Mobile dropdown        | low      | Theme picker chevron mis-aligned on iOS Safari < 16.         | 🟡 IN PROGRESS | (none yet)                              |
| M3  | Drawer dismiss         | high     | Swipe-down to close fires on intra-drawer scroll.            | 🔴 OPEN      | (regression report 2026-05-07)            |
```

## Conventions

- **Stable IDs**: `M0`, `M1`, `M2`, … — assigned once, never renumbered. Skips on dropped items are fine; renumbering breaks every back-reference in conversation history.
- **Surface / scope**: a short string that lets the reviewer locate the affected surface in seconds. Be specific ("Centre / drawer panes" beats "UI").
- **Severity**: `high` / `medium` / `low`. Lets the human prioritise verification order; low-severity polish can defer past the merge gate.
- **Status emoji**: `🔴 OPEN` (just reported) → `🟡 IN PROGRESS` (agent has a fix in flight) → `🟢 VERIFIED` (reviewer confirmed the fix in their own walk). Reviewer flips the emoji and appends the commit SHA in the same edit.
- **Multi-cycle entries**: when an issue takes multiple fix attempts, leave the row's ID stable and append `cycle 2`, `cycle 3` notes inline in the description. The history matters — a cycle-7 fix often reads differently than a cycle-1 fix.

## How the cycle runs

1. Reviewer walks the eval-checklist; finds an issue.
2. Reviewer reports it: "M3 broken — swipe-down on intra-drawer scroll closes the drawer". Or, in the early-cycle case, the reviewer just describes the issue and the agent assigns the next ID.
3. Agent appends the row at status 🔴, fixes, commits, replies with the commit SHA and flips status to 🟡.
4. Reviewer re-walks; if fixed, flips to 🟢 and appends the SHA verification line. If still broken, keeps at 🔴 and adds a "cycle 2" note in the description.
5. Loop until every row is 🟢. Last-of-batch flip is the merge unblocker.

## Why stable IDs matter

The first manual-eval back-and-forth without IDs is fine. The fifth requires cross-referencing every prior message ("the swipe one — no, the OTHER swipe one"). The tracker's ID is unambiguous: `M3 cycle 2`, `M14 still broken`, `M17 verified` are all instantly resolvable.

The tracker also captures cycle history that the conversation drops on context compaction — `M17 went through 11 cycles before the right Bulma-touch-range vs @include mobile split landed` is the kind of forensic detail you want in the archive dir, not in chat memory.

## Anti-patterns

- ❌ Reusing M-IDs after dropping a row. Conversation history references the original assignment; reuse silently maps a dead ref onto a live row.
- ❌ Skipping severity. Without it, the human can't sequence the walk; the merge gate ends up waiting on every-row-verified including low-priority polish.
- ❌ "I'll just describe each issue in chat — no need for the file." Works for cycles 1-2, fails in cycle 3+. The artefact lives in the archive dir for the same reason every other PR artefact does: the conversation is ephemeral, the archive isn't.

## Provenance

Surfaced 2026-05-07 during a mobile bottom-tab nav + pane swipe + iOS Safari gotchas project: a 26-issue 60+-commit cycle (M0–M25). The tracker was retroactively introduced when the ad-hoc back-and-forth started losing track of which issue was which; after introduction, every reference was unambiguous, and the reviewer could verify in-place by changing the emoji and appending a commit SHA.

---

**Last Updated**: 2026-05-07
