---
stage: plan
slug: claude-code-review-engine
created: 2026-06-02
source: ./IDEA-012-claude-code-review-engine.md
status: shipped
project: mind-vault
pr: 167
---

# Integrate Claude Code Review as a third review-loop engine

## Context

mind-vault's `/review-loop` drives a bounded-autonomy review-fix-rerun loop against pluggable engines, two of which ship today: Cursor Bugbot and GitHub Copilot. We just installed `anthropics/claude-code-action@v1` via `/install-github-app` — `.github/workflows/claude-code-review.yml` auto-runs the `code-review` plugin on every PR, and `claude.yml` is an `@claude`-mention interactive agent. Those reviews already happen; the loop just can't *drive or triage* them yet. This work makes `claude` a first-class engine: dogfooding our own review stack, OAuth/subscription-billed (no per-review SKU), and `CLAUDE.md`-convention-aware in a way the generic vendors structurally can't be.

The intended outcome: a `claude` adapter that satisfies the engine-adapter contract (with the divergences below), `claude` added to the default engine set, the sync contract generalized 2→N (and renamed `multi-engine-sync`), and a staged dogfood that proves the adapter in isolation, then proves N-engine sync, before the flow ships to a consuming project.

## Problem Frame

The review-loop's engine-adapter contract assumes every engine: (1) posts a **named check-run** whose `STATUS` maps to RUNNING/DONE; (2) posts findings as a **review with an id** so staleness keys on `pull_request_review_id`; (3) is **idle until explicitly triggered**. `anthropics/claude-code-action@v1` running the `code-review` plugin violates all three — confirmed by research (see `./IDEA-012-...md` § Key finding):

- **No named check-run.** The only pollable surface is the GitHub Actions job status of the `claude-code-review` workflow run. Its conclusion is green whether Claude found 0 or 5 issues — so it is a RUNNING/DONE signal only, never a verdict.
- **Findings = inline comments + a summary comment**, not a stateful review. Clean must be read off the **summary-comment body** (and/or zero head-SHA inline comments), and staleness must key on **comment ids**, not a review id (whether the inline comments share one `pull_request_review_id` is unconfirmed — verify on first run).
- **Auto-trigger.** The action runs on every push (`synchronize`) — so on a fresh PR claude often self-triggers *before* the loop's zero-activity bootstrap runs.

> ⚠️ **The dominant hazard: action + `code-review` plugin ≠ Anthropic's managed Code Review GitHub App.** The managed App has the nice machinery (named `Claude Code Review` check-run, machine-readable severity JSON). We are NOT using it. Anyone reading `code.claude.com/docs` will see machinery we don't have. `engine-claude.md` MUST lead with this trap.

The good news: the contract *already* says "never infer clean from `CONCLUSION`; clean is structural." claude fits that philosophy — it just relocates the structural clean signal from check-run conclusion to the summary-comment body, and the RUNNING/DONE signal from a named check-run to the Actions job status.

## Requirements Trace

- **R1.** `tools/find_claude_comments.sh <PR>` emits the contract-shape marker stream (`CLAUDE_LATEST_REVIEW`, `CLAUDE_CHECKRUN`, inline findings with a `(comment id <cid>, review <rid>)` token) — sourcing check-run STATUS from the Actions job, findings from inline PR comments, clean from the summary-comment body OR zero head-SHA inline comments. Exit 0 on success.
- **R2.** `claude` is a **push-triggered** engine: the action's `synchronize` hook auto-runs on every push, so Phase 3 (post-fix-push) does **NOT** fire an explicit retrigger for claude — the push already triggered it *(architect A7, option a)*. `tools/claude_retrigger.sh <PR>` exists only as a **fallback** (posts `@claude review once`, hard-coded, idempotent, exit 0, pre-approvable), invoked solely when `find_claude_comments.sh` finds **no Actions run at all** for the head SHA (e.g. the auto-run didn't fire). `find_claude_comments.sh` always selects the **latest Actions run by `run_started_at`** + newest summary comment for the head SHA, so any auto-run/fallback overlap dedups to one authoritative signal.
- **R3.** A review-pending race guard: an Actions job that is `completed` but whose summary comment (or inline comments) for the head SHA hasn't posted yet is downgraded to RUNNING. **The settle valve (`CLAUDE_REVIEW_SETTLE_SECONDS`, default 600) releases on summary-/inline-comment PRESENCE, NOT on the Actions conclusion** *(architect A3)* — claude's conclusion is green regardless of findings, so a conclusion gate (copilot's rule) would always release and ship lagged findings as a false CLEAN. When the valve fires on the genuine no-comment-at-all case (issue #1087), it resolves to **CLEAN via the zero-inline arm**, never bypasses a findings-pending state.
- **R4.** `claude` joins the **default** engine set; a bare `/review-loop` drives `bugbot,copilot,claude` — **but only on repos where the action is installed** *(architect A2)*. `find_claude_comments.sh` (and the default-resolution rule) gate claude into the *default* set on an engine-reachability probe (`gh api .../actions/workflows` contains `claude-code-review.yml`); where absent, claude self-excludes from the default set so a bare `/review-loop` doesn't block to HUNG on an un-provisioned engine. Explicit `/review-loop <PR> claude` still attempts it and degrades **loudly** (clear "claude action not installed" hand-back), never silently.
- **R5.** No new orchestrator branch for the bootstrap *(architect A5 — emergent property)*: `find_claude_comments.sh` emits `CLAUDE_CHECKRUN STATUS=in_progress|completed` for the auto-run, which the existing zero-activity guard (`SKILL.md:87`, "check-run presence counts as activity") already reads as not-`NOT_TRIGGERED` — so the bootstrap retrigger is skipped automatically. Any claude-specific bootstrap logic, if dogfood proves it needed, lives in the adapter's `find_*` output shape, **never** in `SKILL.md`.
- **R6.** `engine-claude.md` exists with all contract-required sections, **leading with the action-vs-managed-service trap**, and includes the install hint (`/install-github-app` + `CLAUDE_CODE_OAUTH_TOKEN`).
- **R7.** The sync contract is renamed `dual-engine-sync.md → multi-engine-sync.md` (per `RULE_rename-before-drop`) with all referrers rewired, and carries claude's escape-hatch rows, scratch slots, alphabetical retrigger order (bugbot → claude → copilot), and a 3-engine asymmetric-clearance template.
- **R8.** `sprint-auto`'s `SPRINT_AUTO_REVIEW_ENGINE` validation accepts any non-empty CSV subset of `{bugbot,copilot,claude}` (+ `none`), rejecting unknown names.
- **R9.** Mechanical enum/doc propagation: `commands/review-loop.md`, `review-loop/SKILL.md`, `engine-adapter-contract.md` (formalize "auto-trigger" adapter category), `compound/references/review-finding-ingest.md` (`.claude-loop/` dir + engine inference), README + guides + CHANGELOG.
- **R10.** Staged dogfood: `claude`-solo on this PR → `bugbot,copilot,claude` on the IDEA-009 PR → hand to user for a consuming project.

## Scope Boundaries

**In scope:**

- New `tools/find_claude_comments.sh`, `tools/claude_retrigger.sh`.
- New `skills/review-loop/references/engine-claude.md`.
- Rename `dual-engine-sync.md → multi-engine-sync.md` + rewire all refs.
- `engine-adapter-contract.md` "auto-trigger / comment-anchored" category + N-engine note.
- `review-loop/SKILL.md` + `commands/review-loop.md` enum/default updates.
- `sprint-auto/SKILL.md` engine-validation generalization.
- `compound/references/review-finding-ingest.md` `.claude-loop/` support.
- Doc sweep: `README.md`, `docs/guides/{GIT_WORKFLOW,SPRINT_WORKFLOW,ONBOARDING}.md`, `CHANGELOG.md`.
- `.claude/settings.local.json` (or user settings) pre-approve the two new scripts.

**Out of scope:**

- Building anything on the `@claude`-interactive (`claude.yml`) workflow beyond borrowing `@claude review once` as a retrigger lever.
- A `commands/claude-loop.md` thin single-engine wrapper (optional; defer unless a single-engine entry is wanted — the explicit `/review-loop <PR> claude` covers solo runs).
- Migrating Bugbot/Copilot off — claude is purely additive.

**Explicit non-goals:**

- NOT using Anthropic's managed Code Review GitHub App (different product, different machinery).
- NOT making the orchestrator's phase logic engine-specific — `SKILL.md` stays engine-generic; all claude specifics live in the adapter + `multi-engine-sync.md`.
- NOT hard-failing the loop if the Actions job is unreadable (e.g. `actions: read` perm missing) — degrade gracefully to summary-comment-only state with a logged warning.

## Context & Research

### Existing code and patterns to reuse

- `tools/find_copilot_comments.sh` — the closest structural template: per-endpoint `gh api` fetch, Python sub-passes emitting markers, the **review-pending race guard** + `COPILOT_REVIEW_SETTLE_SECONDS` settle valve (model `find_claude_comments.sh`'s guard on this; settle computed in Python `datetime`, never `date -d`), the `null`/URL PR-number validation, the head-SHA-aware active-finding precheck.
- `tools/copilot_retrigger.sh` — template for `claude_retrigger.sh` (PR-number resolution, hard-coded action body, `set -eo pipefail`).
- `tools/bugbot_retrigger.sh` — comment-post retrigger shape (claude's retrigger is `gh pr comment <PR> --body "@claude review once"`, the bugbot pattern).
- `skills/review-loop/references/engine-copilot.md` — section template for `engine-claude.md` (§ Identity, § Tool invocations, § Review-state + clean detection, § Staleness, § Race-condition caveats, § Failure modes, § Common patterns, § Review-state gate).
- `skills/review-loop/references/engine-adapter-contract.md` — already has "Adding a new engine" (4 steps) + a conclusion-agnostic review-pending guard already generalized to "any new engine whose `find_*` synthesizes clean from a check-run". Add the auto-trigger category here.
- `skills/review-loop/references/dual-engine-sync.md` — already titled "(and N-engine)" with an "Adding a third engine" section and "generalises to N engines without modification"; the rename is mostly cosmetic + adding claude's example rows.

### Institutional learnings

- `RULE_rename-before-drop` — governs R7's file rename: rename + rewire all referrers in one commit, full grep-verify that zero `dual-engine-sync` paths remain, *then* the rename is "dropped". For a doc-file rename the "legacy symbol" is the old path string; the drop is verified by a clean grep, not a separate deletion commit.
- `RULE_self-sweep-before-push` trigger 5 (doc-consistency) + trigger 1 (touched-files) — every commit here is doc/script-heavy.
- IDEA-005 archive (`docs/archive/2026-05-idea-005-review-loop-shared-core/`) — the engine-adapter architecture this extends; its dogfood (10 cycles on PR #131) is the precedent for R10's in-PR validation.
- `feedback_bugbot_loop_no_compound_bash` (auto-memory) — inside review-loops, avoid `&&` chains / utility commands; one allowlist entry per call.

### External references

- `github.com/anthropics/claude-code-action` — the action; `claude-code-review.yml` config + `additional_permissions: actions: read` (needed for the loop to read the Actions job status — R3/RUNNING signal).
- `code.claude.com/docs` `/code-review` plugin — the prompt the action runs. **Caveat:** much of the docs describe the managed App; treat behavioral claims as unconfirmed until the claude-solo dogfood (step 2) verifies them empirically.
- Action issue #1087 (empty-result no-comment) — motivates the belt-and-suspenders clean detector (summary-string-match OR zero head-SHA inline comments).

## Key Technical Decisions

- **`claude` joins the default engine set — gated on reachability** *(user decision + architect A2)*. Default becomes `bugbot,copilot,claude`, but claude is included in the *default* set only when the action's workflow is installed on the target repo (reachability probe). Where absent it self-excludes from the default so a bare `/review-loop` doesn't HUNG; explicit `claude` still attempts and degrades loudly. This reconciles "default-on" with cross-project safety (a consuming project won't break before its own install).
- **Review-state synthesized from the GitHub Actions job** *(user decision)*. `find_claude_comments.sh` polls the `claude-code-review` workflow run (`gh api .../actions/runs` filtered to that workflow + head SHA, **latest by `run_started_at`**): `queued`/`in_progress` → RUNNING, `completed` → DONE. Conclusion ignored (fits "never infer clean from CONCLUSION"). Gives the multi-engine sync gate a real RUNNING signal.
- **`claude` is push-triggered, not retriggered** *(architect A7, option a)*. The action auto-runs on `synchronize`, so a fix push *is* the retrigger — Phase 3 does not fire `claude_retrigger.sh` for claude (avoids the double-run race where the `synchronize` auto-run and an explicit `@claude review once` both run on one head SHA). The retrigger script is a **fallback** for the no-auto-run case only. This simplifies claude's retrigger surface and removes a whole class of "which run is authoritative" ambiguity (dedup: latest run by `run_started_at`).
- **Clean is belt-and-suspenders, substring-matched** *(research + architect A6)*: `clean = summary-comment body contains the case-insensitive substring "no issues found" OR zero claude-authored inline comments on the head SHA after settle`. Substring (not the full sentence) per the copilot lesson (`find_copilot_comments.sh:182-189` — copilot already burned two phrasings); the zero-inline OR-arm covers issue #1087 (no summary comment) + clean-string drift.
- **Settle valve releases on comment presence, not conclusion** *(architect A3)*. See R3 — the load-bearing divergence from copilot's `CONCLUSION=success` settle gate, because claude concludes success even with findings.
- **Staleness keyed on comment ids** (synthesized `LATEST_REVIEW` anchor = the summary-comment id, or the newest head-SHA inline comment id if no summary). Default until the dogfood confirms whether inline comments share a `pull_request_review_id`.
- **Rename `dual-engine-sync.md → multi-engine-sync.md`** *(user decision)*, sequenced per `RULE_rename-before-drop`. **Scope: everywhere** — *(user direction, 2026-06-02, superseding the architect-A1 live-surface-only scoping)*: the `dual-engine` term + file path are unified to `multi-engine` across live docs, CHANGELOG, and archive alike. Only the IDEA-012 plan/IDEA rename-*action* descriptions (`git mv X → Y`) keep the old name as the rename source.
- **Conservative interim identity filter** *(architect A8)*. claude's comment author login (the identity `claude-code-action` posts under) is confirmed on the solo dogfood and hard-coded like copilot's login tuple. Until then, the filter requires **BOTH** the workflow-run-author association AND the `code-review` plugin's comment-body signature — never either alone — so an over-loose filter fails toward "no clean detected" (safe: keeps polling), never a false CLEAN.

## Open Questions

- **Q1. claude's comment author `user.login` + whether inline comments share a `pull_request_review_id`.**
  - **Default:** filter by the action's bot identity (confirm on dogfood); key staleness on comment ids with the summary-comment id as the `LATEST_REVIEW` anchor.
  - **Trade-off:** if the comments *do* share a review id, we could use the cleaner uniform staleness rule; keying on comment ids is safe either way but slightly more bookkeeping. **Resolve in step 2 (claude-solo dogfood) — do not block the build.**
- **Q2. `@claude review once` semantics through the *action* path (vs the managed service the docs describe).**
  - **Default:** `claude_retrigger.sh` posts `@claude review once`; if the dogfood shows it doesn't trigger a `code-review` run, fall back to a plain `@claude` comment instructing `/code-review:code-review <repo>/pull/<N>`.
  - **Trade-off:** the fallback is wordier but deterministic. **Resolve in step 2.**
- **Q3. Does the loop need `actions: read` beyond what `claude.yml` already grants, for `find_claude_comments.sh` to read the job status?**
  - **Default:** `gh api repos/.../actions/runs` uses the user's `gh` auth (not the workflow token), so the local script reads runs fine; no workflow change needed. Confirm the API returns the run for the head SHA.
  - **Trade-off:** if blocked, degrade to summary-comment-only state (lose the RUNNING signal). **Resolve in step 2.**

## Execution Sequence

Commits are grouped so the rename (R7) lands as its own `RULE_rename-before-drop` step with a verify gate, and the adapter is buildable/testable before the default-set flip exposes it to bare invocations.

1. ✅ `6035bc9` **Adapter scripts.** Create `tools/find_claude_comments.sh` (model on `find_copilot_comments.sh`: PR-resolution, Actions-job-status → `CLAUDE_CHECKRUN` (latest run by `run_started_at`), inline-comment findings with `(comment id, review)` token, **case-insensitive `"no issues found"` substring OR zero-inline** clean (A6), review-pending guard whose settle valve releases on **comment presence not conclusion** (A3) + `CLAUDE_REVIEW_SETTLE_SECONDS`, **conservative BOTH-author-AND-body-signature identity filter failing toward no-clean** (A8), and a **reachability probe** (`gh api .../actions/workflows`) so the engine can self-report installed/absent (A2)). Create `tools/claude_retrigger.sh` (`gh pr comment <PR> --body "@claude review once"`) — **fallback only** (A7). `chmod +x`. Self-sweep (pyflakes the embedded Python, shellcheck-eyeball). Pre-approve both in settings.
2. ✅ `15d8b69` **Adapter reference.** Create `skills/review-loop/references/engine-claude.md` with all required sections, **leading with the action-vs-managed-service trap**, the install hint, the push-triggered/retrigger-fallback model (A7), the comment-presence settle rule (A3), the reachability/degrade-loudly failure mode (A2), and the three empirical-verify items (Q1–Q3) flagged as "confirm on first run".
3. ✅ `15d8b69` **Contract doc.** Edit `engine-adapter-contract.md`: add the "auto-trigger / comment-anchored" adapter category and note claude as its first instance; **widen the taxonomy** (A4) — generalize the `<ENGINE>` enumeration (`:43`) to "e.g. `BUGBOT`, `COPILOT`, `CLAUDE`", add the synthesized-summary-comment-id case to the `last_seen_<engine>_signal_id` taxonomy (`:119`), and note in the review-pending-guard paragraph (`:109`) that comment-anchored engines gate DONE on comment presence, not conclusion. Confirm the "Adding a new engine" step list mentions the default-set reachability + sync-doc touchpoints.
4. ✅ `7e33d7a` (rename+rewire; claude rows land with step 5–8 content) **Sync-doc rename (R7, RULE_rename-before-drop).** `git mv skills/review-loop/references/dual-engine-sync.md skills/review-loop/references/multi-engine-sync.md`; update the title/body to drop the "dual" framing; add claude's escape-hatch rows, scratch slots (`claude_review_state`, `last_seen_claude_review`, `last_seen_claude_signal_id`), alphabetical retrigger order (bugbot → claude → copilot, **noting claude's retrigger is push-driven/fallback-only**), and the 3-engine asymmetric-clearance template. **Rewire EVERYWHERE** *(user direction 2026-06-02 — superseded the original A1 live-surface-only scoping)*: a follow-up commit swept `dual-engine`→`multi-engine` (term + `…-sync.md` path) across live docs, CHANGELOG, and `docs/archive/**` alike, excluding only this IDEA-012 plan/IDEA's rename-action descriptions. **Verify gate:** `grep -rin "dual.engine" .` returns hits only inside the IDEA-012 dir (the rename-source descriptions); no markdown link targets the old filename.
5. ✅ `15d8b69` **Orchestrator + command enum.** `review-loop/SKILL.md`: add `claude` to the ENGINES enum + reference `multi-engine-sync.md`; default-engine note now `bugbot,copilot,claude` **with the reachability caveat** (A2 — claude in default only when its action workflow is installed on the repo). `commands/review-loop.md`: update `ENGINES` default (line 13) + reachability note, the supported-engine list (lines 40–41) with the claude tool-script bullet, the examples block, and the `dual` → `multi`-engine wording (line 24).
6. ✅ `15d8b69` **sprint-auto validation (R8).** `sprint-auto/SKILL.md` line ~49: generalize accepted values from `{bugbot,copilot,bugbot,copilot}` to any non-empty CSV subset of `{bugbot,copilot,claude}` (or "any engine with a matching `tools/<engine>_*.sh` pair"), reject unknown names; update the description + S-step prose that enumerate engines.
7. ✅ `15d8b69` **compound ingest (R9).** `compound/references/review-finding-ingest.md`: add `.claude-loop/` to the run-artifact path list (line 7), the engine inference (`.claude-loop/` → `claude`, line 90), and `claude` to the provenance-engine enum (lines 3, 79).
8. ✅ `15d8b69` **Doc sweep.** `README.md` (engine/tool counts + lists), `docs/guides/{GIT_WORKFLOW,SPRINT_WORKFLOW,ONBOARDING}.md` (review-engine mentions), `CHANGELOG.md` (new version section — minor bump: this is a feature, first IDEA-driven release since v4.5; confirm bump at wrap).
9. **Dogfood step A — claude-solo (R10).** Open the PR for this branch. Run `/review-loop <PR> claude`. **This is where Q1–Q3 resolve empirically.** Fix the adapter against real behavior (bot login, retrigger semantics, job-status readability, clean-string). Iterate until claude clears CLEAN solo. Capture confirmed constants back into `engine-claude.md` § first-run calibration.
10. **Dogfood step B — tri-engine (R10).** On the parked IDEA-009 PR, run `/review-loop <PR> bugbot,copilot,claude`. Validates the 2→N sync generalization (slowest-of-three gate, one batched fix commit, three retriggers in alphabetical order, 3-engine asymmetric-clearance hand-back). Fix any sync-layer issues.
11. **Hand to user** for the cross-project test in a consuming project (install via `/install-github-app` there, then `/review-loop <PR> claude`).

## Verification

- **Adapter shape:** `./tools/find_claude_comments.sh <PR>` on a PR with a completed claude run emits a `CLAUDE_CHECKRUN=... STATUS=completed`, a `CLAUDE_LATEST_REVIEW=...`, and either a clean indication or `(comment id <cid>, review <rid>)` finding blocks. `./tools/claude_retrigger.sh <PR>` exits 0 and posts the comment.
- **Race guard (A3):** a poll during an in-flight run (Actions job `in_progress`, or `completed` before the summary/inline comments post) reports `STATUS=in_progress` (RUNNING) — never a premature CLEAN. The settle valve releases only once a head-SHA comment has posted (or, on the #1087 no-comment case, resolves CLEAN via zero-inline) — never off the (always-green) conclusion.
- **Rename verify gate (R7):** `ls skills/review-loop/references/multi-engine-sync.md` exists; no markdown link targets `dual-engine-sync.md`; per the user's everywhere-rename, `grep -rin "dual.engine" .` returns hits ONLY inside the IDEA-012 dir (the rename-action source descriptions) — live docs, CHANGELOG, and archive are all unified to `multi-engine`.
- **Default set + reachability (R4, A2):** on mind-vault (action installed) a bare `/review-loop <PR>` resolves engines to `bugbot,copilot,claude` (inspect scratch `engines:` field); simulate/confirm that on a repo WITHOUT the workflow, claude self-excludes from the default and an explicit `claude` degrades loudly (not HUNG).
- **Push-triggered (R2, A7):** after a Phase-3 fix push, confirm claude is NOT explicitly retriggered (no `@claude review once` comment posted by the loop) and that `find_claude_comments.sh` picks up the `synchronize` auto-run; the fallback retrigger fires only when no run exists for the head SHA.
- **sprint-auto (R8):** `SPRINT_AUTO_REVIEW_ENGINE=claude` and `=bugbot,copilot,claude` both pass validation; `=bogus` aborts with the actionable error.
- **Self-sweep:** pyflakes clean on the embedded Python in both scripts; doc-consistency sweep (frontmatter ↔ prose, engine counts in README) green.
- **End-to-end (R10):** claude clears CLEAN solo on this PR (step 9); the tri-engine run on IDEA-009 reaches a unified verdict with one fix commit per cycle and three retriggers per cycle (step 10).

## Architect Review

Reviewed by `mv-architect` (2026-06-02). **Verdict: 🟡 REQUIRES ABSTRACTION** → resolved. The category abstraction (auto-trigger / comment-anchored) was found sound and the orchestrator genuinely engine-generic; no fatal coupling. Eight findings, all incorporated:

- **A1 (Critical)** — rename verify gate would corrupt archived/historical docs → scoped rewire + gate to **live surface only**; archive + historical CHANGELOG retained (R7, step 4, Verification).
- **A2 (Major)** — default-set flip hard-binds bare `/review-loop` to claude infra on every repo → **engine-reachability probe**; claude self-excludes from the *default* set where the action isn't installed, explicit `claude` degrades loudly (R4, step 1/2/5).
- **A3 (Critical)** — copilot's `CONCLUSION=success` settle gate would always release for claude (green conclusion ≠ clean) → settle valve releases on **comment presence**, not conclusion (R3, KTD, step 1/2).
- **A7 (Major)** — action auto-run vs explicit retrigger = double-run race → **claude is push-triggered**; Phase 3 doesn't retrigger it, the retrigger script is fallback-only, runs dedup to latest by `run_started_at` (R2, KTD, step 4).
- **A4 (Major)** — widen contract `<ENGINE>` enum + signal-id taxonomy for the synthesized-anchor flavor (step 3).
- **A5 (Major)** — reframe the bootstrap-skip as an **emergent property** of correct `CHECKRUN` emission, not new orchestrator logic (R5).
- **A6 (Minor)** — substring `"no issues found"` clean match, not full sentence (KTD, step 1).
- **A8 (Minor)** — conservative BOTH-author-AND-body-signature identity filter, failing toward no-clean (KTD, step 1).

Q1–Q3 (bot login + shared-review-id, `@claude review once` semantics via the action path, `actions: read` reachability) confirmed as genuinely **empirical** — resolved at step 9 (claude-solo dogfood), not blocking.

---

**Status:** ready — architect-reviewed (🟡→resolved), execute via `/work`.
