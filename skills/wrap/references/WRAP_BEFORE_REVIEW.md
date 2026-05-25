# Wrap before review — finalize docs to shipped state *before* the review-loop runs

**When this fires**: a doc-heavy IDEA (the PR carries substantial IDEA-file / plan / index / devlog / guide changes alongside code) is headed for a bot review pass (`/review-loop`, single- or dual-engine). The default documented sprint chain is `work → review-loop → wrap`. For doc-heavy PRs, **reorder the doc-finalization to run first**: `work → wrap(docs) → review-loop → human-merge`.

## Why

Modern review engines review **docs, not just code**. Copilot in particular comments on markdown: frontmatter↔body symmetry, stale comments, count/range claims, terminology precision. If the review runs while the docs are still in their `status: in-progress` / pre-devlog state, one of two bad things happens:

1. The reviewer flags the WIP doc state as a finding (e.g. "frontmatter says X but body says in-progress"), OR
2. The docs get finalized *after* review in the wrap pass — so the reviewed state ≠ the merged state, and any doc issue the wrap introduces ships unreviewed.

Wrapping the docs first collapses both: the reviewer sees the docs in the exact shape they'll merge in, doc-consistency findings land in the same pass as code findings, and there's no post-review doc drift.

**The merge stays where it always was.** Wrapping-first reorders only the *doc-finalization* steps (frontmatter flip, ideas-index move, devlog entry, downstream-docs scan). The atomic-merge step (wrap Step 8 / `ATOMIC_MERGE.md`) is unaffected — it still runs only after review clears, and on protected targets (or under a "never agent-merge" user rule) stays with the human. Decouple the two halves of wrap mentally: **doc-finalization is pre-review; merge is post-review-clear.**

## The tension this creates, and how to handle it

Wrapping first means `status: complete`, the `completed:` date, and the devlog "what shipped" bullets are written *before* the review cycles add their fix commits. Two consequences, both manageable:

### 1. The status-flip MUST sync the human-readable body-prose status line (mandatory sub-step)

Flipping frontmatter `status: in-progress → complete` is not enough. IDEA files (and many plan/index docs) carry a *second*, human-readable status — a `**Status**: 🚧 In Progress` prose line in the body. The frontmatter flip leaves that line stale, and a doc-reviewing engine **will** flag the frontmatter↔body mismatch. This is a self-inflicted finding: the wrap created it, the review caught it, a cycle was spent fixing it.

So wrap Step 2 (frontmatter flip) gains a grep-and-sync sub-step: after editing frontmatter, grep the same file (and sibling plan/README docs) for a `**Status**:` / `Status:` prose line and update it to match (`✅ Complete (YYYY-MM-DD)`). One-liner, zero review cost. See wrap SKILL.md Step 2.

### 2. Review-cycle commits can outdate the devlog "what shipped" — re-touch lightly at merge if material

Most review-cycle commits are noise (lint nits, translation-map entries, login_required decorators) that don't change the devlog's user-facing narrative — leave them. But if a review cycle lands a *material* user-facing change (a real bug fix that alters behaviour the devlog describes), do a light re-touch of the devlog bullet at merge time. Judgement call; the bar is "would a reader of the devlog be misled?" — usually no.

## Evidence (one observed dual-engine run)

A doc-heavy migration PR was wrapped-then-reviewed. Review cycle 1: 4 findings, **all code, zero docs** — the wrapped docs reviewed clean, validating that front-loading them works. Later cycle: exactly 1 doc finding, and it was the frontmatter↔body status-line mismatch the wrap's own flip introduced (sub-step #1 above did not yet exist). That single finding is the entire basis for making the body-prose sync a mandatory wrap sub-step rather than a nice-to-have: front-loading docs eliminates the *external* doc-drift class, but the wrap must not *introduce* a new internal-inconsistency finding in the act of finalizing.

## When NOT to reorder

- **Code-only PRs** (no IDEA-file/devlog/index churn worth reviewing) — ordering is moot; the default chain is fine.
- **Trivial wraps** where the only doc change is the frontmatter flip itself — still do the body-prose sync, but there's nothing for the reviewer to gain from seeing it first.
- The reorder is about *what state the reviewer sees*, not about merging earlier. Never let "wrap first" pull the merge before review clears.
