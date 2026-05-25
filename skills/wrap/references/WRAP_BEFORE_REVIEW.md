# Wrap before review — finalize docs to shipped state *before* the review-loop runs

**When this fires**: a doc-heavy PR (substantial IDEA-file / plan / index / devlog / guide changes alongside code) headed for `/review-loop` (single- or dual-engine). The default chain is `work → review-loop → wrap`; for doc-heavy PRs, **run doc-finalization first**, splitting wrap into two passes: `work → wrap pass 1 (/wrap, scope=docs default) → review-loop → wrap pass 2 (/wrap --scope=full) | human merge`. Pass 1 is a bare `/wrap NNN` — the `docs` default finalizes docs and **structurally cannot reach Step 8 (merge)**, so there is nothing to "remember to stop." Pass 2 is `/wrap --scope=full NNN`, the explicit merge opt-in that runs Step 8 on non-protected targets — or, on protected targets, Step 8 auto-skips and the human merges. See *The two-pass model* below.

## Why

Modern review engines review **docs, not just code** — Copilot in particular comments on frontmatter↔body symmetry, stale comments, count/range claims, terminology precision. Reviewing while docs are still `status: in-progress` / pre-devlog fails two ways:

1. The reviewer flags the WIP state itself (e.g. "frontmatter says X but body says in-progress"), OR
2. Docs get finalized *after* review in the wrap pass — so reviewed state ≠ merged state, and any issue the wrap introduces ships unreviewed.

Wrapping first collapses both: the reviewer sees docs in their merge shape, doc findings land alongside code findings, no post-review drift.

**The merge doesn't move — and the default scope can't reach it.** This is a **two-pass** model, enforced by the `--scope` enum:

1. **Pre-review pass (pass 1) — bare `/wrap NNN` (`--scope=docs`, the default).** Runs the doc-finalization steps (frontmatter flip, ideas-index move, devlog entry, downstream-docs scan — wrap Steps 1–4 and 6, plus the conditional Step 7 eval-gate emission when it fires) and **structurally cannot reach Step 8 (atomic merge)**. No "remember to stop" — the default scope makes the stop a property of the tool, not operator discipline. (`--scope=idea-only` also skips Step 8 but *additionally* skips the devlog/index steps you want pre-review, so it's the sprint-auto tool, not this one.)
2. **Post-review pass (pass 2) — `/wrap --scope=full NNN`.** Re-run after `/review-loop` clears. The doc-finalization steps are idempotent guards (Step 2 short-circuits on `status: complete`; Steps 3/4 detect their existing entries), so pass 2 effectively just re-audits docs (Step 6) and runs Step 8 — atomic-merges on non-protected targets, or hands back on protected targets (where Step 8 auto-skips). `ATOMIC_MERGE.md`'s `clean_sha == head_sha` gate handles the HEAD that review-loop moved.

Mentally split wrap: **doc-finalization is pre-review (`docs`); merge is post-review-clear (`full`).** The scope enum makes the split structural, not a discipline you have to remember.

## The tension this creates, and how to handle it

Wrapping first writes `status: complete`, the `completed:` date, and devlog "what shipped" bullets *before* review adds its fix commits. Two manageable consequences:

### 1. The status-flip MUST sync the body-prose status line (mandatory sub-step)

Flipping frontmatter `status: in-progress → complete` isn't enough. IDEA files (and many plan/index docs) carry a *second*, human-readable `**Status**: 🚧 In Progress` prose line. The flip leaves it stale, and a doc-reviewing engine **will** flag the frontmatter↔body mismatch — a self-inflicted finding the wrap created and a review cycle then spends fixing.

So wrap Step 2 gains a grep-and-sync sub-step: after editing frontmatter, grep the same file (and sibling plan/README docs) for a `**Status**:` / `Status:` line and sync it (`✅ Complete (YYYY-MM-DD)`). One-liner, zero review cost. See wrap SKILL.md Step 2.

### 2. Review-cycle commits can outdate the devlog — re-touch only if material

Most review commits are noise (lint nits, translation-map entries, decorators) that don't change the devlog narrative — leave them. If a cycle lands a *material* user-facing change (a real bug fix altering behaviour the devlog describes), re-touch the bullet at merge. The bar: "would a devlog reader be misled?" — usually no.

## Evidence (one dual-engine run)

A doc-heavy migration PR was wrapped-then-reviewed. Cycle 1: 4 findings, **all code, zero docs** — the wrapped docs reviewed clean, validating front-loading. A later cycle: exactly 1 doc finding — the frontmatter↔body status-line mismatch the wrap's own flip introduced (sub-step #1 didn't yet exist). That finding is the whole basis for making the body-prose sync mandatory: front-loading kills the *external* doc-drift class, but the wrap must not *introduce* an internal-inconsistency finding while finalizing.

## When NOT to reorder

- **Code-only PRs** (no doc churn worth reviewing) — ordering is moot.
- **Trivial wraps** (only doc change is the frontmatter flip) — still do the body-prose sync, but the reviewer gains nothing from seeing it first.
- The reorder controls *what state the reviewer sees*, not when you merge. Never let "wrap first" pull merge before review clears.
