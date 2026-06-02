---
id: 012
title: Integrate Claude Code Review as a third review-loop engine
status: in-progress          # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by: null
depends_on: [5]       # list of IDEA ids required before starting, or []
related: [5, 6]             # list of IDEA ids that share context, or []
created: 2026-06-02
completed: null
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Six open design forks plus a load-bearing unknown (whether the plugin's inline comments share a pull_request_review id) that can only be resolved by empirical observation on a live PR; the dogfood sequence is human-observed by design."
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "Touches CI surface (.github/workflows/claude-code-review.yml) and references the CLAUDE_CODE_OAUTH_TOKEN secret wiring; an install hint documents secret/infra setup. Wants a human eyeball."
---

# IDEA-012: Integrate Claude Code Review as a third review-loop engine

**Status**: 🚧 In Progress (planned 2026-06-02 — see [plan](./2026-06-02-claude-code-review-engine-plan.md))
**Priority**: Medium

**Problem** (or opportunity): `/review-loop` drives a bounded-autonomy review-fix-rerun loop against pluggable engines. Two ship today — Cursor Bugbot and GitHub Copilot, both per-review-billed external vendors. We just installed `anthropics/claude-code-action@v1` via `/install-github-app` (`.github/workflows/claude-code-review.yml` auto-runs the `code-review` plugin on every PR; `claude.yml` is `@claude`-mention interactive). Those reviews already happen — but the loop can't *drive or triage* them. Making `claude` a first-class engine delivers three things no existing engine offers: **(1) in-house dogfooding** — Anthropic's own action running our own `code-review` plugin against our own `CLAUDE.md` rules, so bugs surface on us first before teisutis; **(2) subscription/OAuth billing** (`CLAUDE_CODE_OAUTH_TOKEN`) instead of a per-review SKU — cheaper marginal cost at PR volume; **(3) `CLAUDE.md`-convention-aware findings** the generic vendors structurally can't produce.

**Proposal** (or idea): Add `claude` as a first-class review-loop engine adapter, and generalize the loop's two-engine assumptions to N.

**Key finding — engine-model fit (the crux):** our path is the **GitHub Action + `code-review` plugin**, **NOT** Anthropic's managed Code Review GitHub App. The managed App has the nice machinery (named check-run, machine-readable severity JSON); **the action path has none of it.** It does **not** fit the existing check-run + review-id + explicit-retrigger contract — it needs a **new adapter category: "auto-trigger / comment-anchored".** Concretely:

- **(a) No named check-run.** Only the GitHub Actions job status of the `claude-code-review` workflow is pollable (`queued`/`in_progress`/`completed` → RUNNING/DONE). Its CONCLUSION is *meaningless for verdict* (green whether 0 or 5 findings) — which actually fits the contract's existing "never infer clean from CONCLUSION; clean is structural" rule. The adapter relocates the structural signal from check-run conclusion to the summary-comment body.
- **(b) Findings = inline comments + a summary comment.** Clean is detected by **string-matching the summary body** (`"No issues found. Checked for bugs and CLAUDE.md compliance."`) **and/or zero head-SHA inline comments**. Staleness must key on **comment ids, not a review id** — whether the inline comments share one `pull_request_review` id is **UNCONFIRMED** and must be verified on first run.
- **(c) Auto-trigger AND retriggerable.** The action auto-runs on every push (`synchronize`) — unlike every existing engine — *and* is retriggerable without a push via an `@claude review once` comment. So the zero-activity bootstrap differs: claude often self-triggers before the loop acts.

**Scope / deliverables:**

_Load-bearing (block correctness):_
- `tools/find_claude_comments.sh <PR>` — emits the `CLAUDE_*` markers per the anchor-grep contract, but: `CLAUDE_CHECKRUN` synthesized from the Actions job status; findings parsed from inline PR review comments; clean by summary-string-match OR zero-inline-after-settle; a review-pending race guard (job `completed` AND summary comment for head SHA not yet posted → downgrade to RUNNING) with a `CLAUDE_REVIEW_SETTLE_SECONDS` valve (default 600).
- `tools/claude_retrigger.sh <PR>` — `gh pr comment <PR> --body "@claude review once"` (idempotent, exit 0 on success).
- `skills/review-loop/references/engine-claude.md` — NEW adapter reference. **MUST lead with the action-vs-managed-service trap** or implementers build against the wrong product.
- Generalize `skills/sprint-auto` `SPRINT_AUTO_REVIEW_ENGINE` validation from the hardcoded `{bugbot,copilot}` enum to any non-empty CSV subset of `{bugbot,copilot,claude}` (ideally: any engine resolvable by a matching `tools/<engine>_*.sh` pair).
- `skills/review-loop/references/dual-engine-sync.md` — add claude stall/error escape-hatch rows, the 3-engine asymmetric-clearance template, the scratch schema slots (`claude_review_state`, `last_seen_claude_review`, `last_seen_claude_signal_id`), and the alphabetical retrigger order (bugbot → claude → copilot).

_Mechanical (propagate enum / generalize "dual"→"N"):_
- `skills/review-loop/SKILL.md` ENGINES enum; `commands/review-loop.md` default-ENGINES note + claude tool bullet.
- `skills/review-loop/references/engine-adapter-contract.md` — formalize an "Adding an N-th engine" section + document the auto-trigger adapter category.
- Doc sweep: `common-review-findings.md`, `skills/compound/references/review-finding-ingest.md` (add `.claude-loop/` dir), `README.md`, `docs/guides/{GIT_WORKFLOW,SPRINT_WORKFLOW,ONBOARDING}.md`, CHANGELOG.

_Onboarding:_ surface an **install hint** (the `/install-github-app` command + `CLAUDE_CODE_OAUTH_TOKEN` wiring) in `engine-claude.md` / the review-loop entry so any project can onboard the engine.

**Open questions** (for `/plan` to resolve; some need empirical verification):
1. Synthesize `CLAUDE_CHECKRUN` from the Actions job status (reuses orchestrator machinery, gives a RUNNING signal) vs drive state purely off summary-comment presence (simpler, loses RUNNING during the run)?
2. Does `claude` **join the default ENGINES set** or stay **opt-in**? It auto-runs anyway — lean opt-in so the loop doesn't block on an engine the user didn't ask to gate on.
3. **Staleness anchor** — confirm empirically whether the plugin's inline comments share one `pull_request_review` id; if not, key on a synthesized summary-comment-id anchor.
4. **Clean-string fragility** — recommend belt-and-suspenders: clean = summary-string-match OR zero head-SHA inline comments (also covers the empty-result no-comment upstream bug, action issue #1087).
5. **Rename `dual-engine-sync` → `multi-engine-sync`** now (clean, but a doc-wide rename per `RULE_rename-before-drop`) or just add claude rows (lower churn)?
6. **Self-trigger bootstrap** — skip `claude_retrigger.sh` on first observation (detect the in-flight auto-run) vs always retrigger for determinism and tolerate a duplicate `@claude` comment?

**Risks / unknowns:**
- Single-review-id grouping **unconfirmed** (medium) — load-bearing for staleness; default to comment-id staleness, verify on first run.
- `@claude review once` semantics through the *action* path inferred, not confirmed (medium-high) — fallback: a plain `@claude` comment instructing a `/code-review:code-review` re-run.
- Empty-result no-comment upstream bug (action issue #1087) — covered by the zero-inline-comments fallback in Q4.
- Clean-string drift — hard dependency on an upstream literal we don't control.
- **Managed-service-vs-action documentation confusion is the dominant hazard** — `engine-claude.md` MUST lead with it.

**Rollout / execution sequence** (de-risking ladder):
1. Build the adapter + integration.
2. **Dogfood `claude` ALONE** on this IDEA's own implementation PR — isolates the new adapter (check-run synthesis, finding parse, clean/retrigger) with no multi-engine noise.
3. **Dogfood `claude,copilot,bugbot` tri-engine** on the parked IDEA-009 PR — isolates the dual→N-engine sync generalization; the first real 3-engine exercise (slowest-engine gate, batched fix commit, per-engine retrigger across three).
4. **Hand to user** to test the flow on **teisutis** (cross-project validation).

This ordering separates "does the adapter work" (step 2) from "does N-engine sync work" (step 3), so a step-3 failure points at the sync layer, not the adapter.

**Why now**:
- The action is installed and auto-reviewing every PR *today* — the reviews exist; only the loop integration is missing. Low activation energy.
- We have two live dogfood targets queued (this PR, then the parked IDEA-009 PR) before it ships to teisutis.

**Non-goals**:
- Not switching off Bugbot/Copilot — claude is additive; the loop stays N-engine.
- Not using Anthropic's managed Code Review GitHub App (different product with different machinery) — explicitly the action + `code-review` plugin path.
- Not building `@claude`-interactive (`claude.yml`) workflows into the loop — only the auto-review (`claude-code-review.yml`) engine. The `@claude review once` comment is borrowed only as a retrigger lever.

**Related**: Extends [IDEA-005](../archive/2026-05-idea-005-review-loop-shared-core/IDEA-005-review-loop-shared-core.md) (review-loop shared core / engine-adapter architecture — `depends_on`; IDEA-005 shipped both the bugbot and copilot adapters, the closest structural precedent, though `claude` diverges on every detection axis). Builds on [IDEA-006](../archive/2026-05-idea-006-review-surface-collapse/IDEA-006-review-surface-collapse.md) (single `/review-loop` entry + N-engine-general dispatch). First **auto-trigger / comment-anchored** engine — a new adapter category worth flagging in `engine-adapter-contract.md`.
