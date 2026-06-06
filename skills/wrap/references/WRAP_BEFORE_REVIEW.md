# Wrap before review — finalize docs to shipped state *before* the review-loop runs

**When this fires**: a doc-heavy PR (substantial IDEA-file / plan / index / devlog / guide changes alongside code) headed for `/review-loop` (single- or multi-engine) — which is **every sprint IDEA** (IDEA file + plan + devlog), so this is the canonical chain, not an exception. The chain is a **single** review pass, after the doc wrap: `work → /wrap (docs) → review-loop → /land (merge)`. Doc-finalization runs **before** the one review, never after — so the reviewer sees the PR at its merged shape. (Code-only PRs with no doc churn collapse to `work → review-loop → land`; the wrap is a near-no-op.) Merge is a separate, named stage — `/land` — run after the single review clears; it is no longer a `--scope` of wrap. See *Why one review pass* below.

## Why

Modern review engines review **docs, not just code** — Copilot in particular comments on frontmatter↔body symmetry, stale comments, count/range claims, terminology precision. Reviewing while docs are still `status: in-progress` / pre-devlog fails two ways:

1. The reviewer flags the WIP state itself (e.g. "frontmatter says X but body says in-progress"), OR
2. Docs get finalized *after* review in the wrap pass — so reviewed state ≠ merged state, and any issue the wrap introduces ships unreviewed.

Wrapping first collapses both: the reviewer sees docs in their merge shape, doc findings land alongside code findings, no post-review drift.

## Why one review pass, not two

The earlier model ran **two** review passes — a deliverables (code) pass *before* the wrap, then a docs pass *after*. IDEA-015 retired it: if wrap always precedes review, there is no reason to review twice.

- `/review-loop` already **iterates to clean** — it re-reviews on every fix push (Phase 4 wake-loop), and its Phase-1 triage is **finding-class-agnostic** (it tiers every finding, code or doc, the same way). So one pass over the *wrapped* PR absorbs both code and doc findings; the loop's own fix-cycles do what the second pass used to do.
- The deliverables-first pass was *premature* — it reviewed an incomplete PR (docs not yet finalized), guaranteeing a second look. Front-loading the wrap makes the first look the only look needed.
- **Reviewing more than once is still allowed** — a mid-`/work` Claude pass for early code signal is fine. What's retired is the *mandatory ceremonial* second pass, not the option.

**Merge is its own stage.** `/wrap` finalizes docs and **never merges**. After the single `/review-loop` clears, run `/land NNN` — it verifies docs are finalized (its precondition guard), then squash-merges on non-protected targets or hands back the PR URL on protected ones. (Legacy: merge used to be `/wrap --scope=full`; that scope is now a deprecated shim that redirects to `/land`.) See [`../../land/references/ATOMIC_MERGE.md`](../../land/references/ATOMIC_MERGE.md).

## The tension this creates, and how to handle it

Wrapping first writes `status: complete`, the `completed:` date, and devlog "what shipped" bullets *before* review adds its fix commits. Two manageable consequences:

### 1. The status-flip MUST sync the body-prose status line (mandatory sub-step)

Flipping frontmatter `status: in-progress → complete` isn't enough. IDEA files (and many plan/index docs) carry a *second*, human-readable `**Status**: 🚧 In Progress` prose line. The flip leaves it stale, and a doc-reviewing engine **will** flag the frontmatter↔body mismatch — a self-inflicted finding the wrap created and a review cycle then spends fixing.

So wrap Step 2 gains a grep-and-sync sub-step: after editing frontmatter, grep the same file (and sibling plan/README docs) for a `**Status**:` / `Status:` line and sync it (`✅ Complete (YYYY-MM-DD)`). One-liner, zero review cost. See wrap SKILL.md Step 2.

### 2. Review-cycle commits can outdate the devlog — re-touch only if material

Most review commits are noise (lint nits, translation-map entries, decorators) that don't change the devlog narrative — leave them. If a cycle lands a *material* user-facing change (a real bug fix altering behaviour the devlog describes), re-touch the bullet at merge. The bar: "would a devlog reader be misled?" — usually no.

## Evidence (one multi-engine run)

A doc-heavy migration PR was wrapped-then-reviewed. Cycle 1: 4 findings, **all code, zero docs** — the wrapped docs reviewed clean, validating front-loading. A later cycle: exactly 1 doc finding — the frontmatter↔body status-line mismatch the wrap's own flip introduced (sub-step #1 didn't yet exist). That finding is the whole basis for making the body-prose sync mandatory: front-loading kills the *external* doc-drift class, but the wrap must not *introduce* an internal-inconsistency finding while finalizing.

## When NOT to reorder

- **Code-only PRs** (no doc churn worth reviewing) — ordering is moot.
- **Trivial wraps** (only doc change is the frontmatter flip) — still do the body-prose sync, but the reviewer gains nothing from seeing it first.
- The reorder controls *what state the reviewer sees*, not when you merge. Never let "wrap first" pull merge before review clears.
