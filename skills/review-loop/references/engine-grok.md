# engine-grok — Grok Build adapter

Adapter specification for the **Grok Build** (xAI CLI) review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

**Category:** auto-trigger / comment-anchored (same family as [`engine-claude.md`](engine-claude.md)). Push-triggered via `.github/workflows/grok-code-review.yml`; review state from the Actions job; clean via **model-judge over prose** (IDEA-022 carve-out — no structured severity JSON).

## § Identity

- Vendor: xAI — [Grok Build](https://docs.x.ai/build) (`grok` CLI).
- GitHub user login for the sticky comment: **`github-actions[bot]`** (workflow posts with `GITHUB_TOKEN`).
- Sticky body marker (mandatory BOTH-AND with login): `<!-- grok-code-review -->`.
- Phase 1's comment fetcher filters on login **and** marker — the shared `github-actions[bot]` login alone would over-claim other Actions bots.

> Calibrate identity off a run that **actually posted** a sticky with findings, not a silent/fail run. Until then the adapter keeps the over-broad login tuple (`github-actions[bot]`, plus harmless `grok[bot]` / `xai[bot]` future-proofing) AND the marker.

## § Tool invocations

- `./tools/find_grok_comments.sh <PR_NUMBER>` — probes for `grok-code-review.yml`, synthesizes `GROK_CHECKRUN` from Actions runs, finds the sticky comment, emits contract markers + verbatim sticky body for the model-judge.
- `./tools/grok_retrigger.sh <PR_NUMBER>` — posts the literal comment `grok review` on the PR. Hard-coded body so the script can be pre-approved in agent host settings. Equivalent to `gh pr comment <PR> --body "grok review"`. Triggers the workflow's `issue_comment` path (no Actions:write needed on the caller's PAT).

## § Review-state + clean detection

**Review-state** is synthesized from the `grok-code-review.yml` Actions job (no named check-run):

| Actions `status` | Emitted `GROK_CHECKRUN STATUS` | Orchestrator |
|---|---|---|
| `queued` / waiting | `queued` | RUNNING |
| `in_progress` | `in_progress` | RUNNING |
| `completed` + sticky present | `completed` | DONE |
| `completed` + no sticky yet | downgraded to `in_progress` (+ `GROK_REVIEW_PENDING`) | keep waiting |
| `completed` + success + no sticky after settle | `GROK_REVIEW_SILENT=true` | NOT clean — fail closed |

**Clean is model-judged** over the sticky body (prose-only surface). The adapter emits `GROK_VERDICT_SET_PROVEN=true` when a non-empty sticky with the marker exists; the `/review-loop` judge classifies `{CLEAN | BLOCKING | NON_BLOCKING[]}`. Job `CONCLUSION` is never a verdict (always green on a finished run regardless of findings).

Reachability: missing workflow → `GROK_NOT_INSTALLED=true` + exit 0 (default set self-excludes). Draft PR → `GROK_DRAFT_NOOP=true` (workflow skips drafts).

## § Staleness rule

Single sticky per PR (updated in place). `GROK_LATEST_REVIEW` is the sticky **issue-comment id**. Active material is that sticky's current body for the head SHA's latest completed run. No inline review-comment threads today — Phase 3 thread auto-resolve does not apply unless Grok later posts inline comments.

## § Race-condition caveats

- **Sticky lag after job complete.** The post-sticky step runs after `grok` finishes; a poll in that gap must not read DONE+empty as CLEAN. `find_grok_comments.sh` holds `STATUS=in_progress` until the sticky appears; `GROK_REVIEW_SETTLE_SECONDS` (default 600) only releases a review-less **success** job as `GROK_REVIEW_SILENT` (not clean).
- **Per-commit billing.** Non-draft same-repo pushes auto-run the workflow. `/work` keeps PRs draft until `/review-loop` un-drafts (same cadence as Claude).
- **Retrigger vs push.** Unlike Claude's skip-no-op plugin, Grok re-runs on every `synchronize`. Phase 3 may still fire `grok_retrigger.sh` after a fix push when the push auto-run is unreliable (or for zero-activity bootstrap); concurrent runs cancel via workflow `concurrency`. Prefer the push auto-run when it is healthy; use the comment retrigger when Actions:write is unavailable on the PAT.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| Grok not installed | `GROK_NOT_INSTALLED=true` | Default set self-excludes; explicit `grok` → loud hand-back (`docs/GROK_BUILD.md` + `XAI_API_KEY`). |
| Draft no-op | `GROK_DRAFT_NOOP=true` | Un-draft; never treat as clean/SILENT/HUNG. |
| Job hung | `GROK_CHECKRUN STATUS=in_progress` past ~15–20 min | Proceed with other engines; retrigger post-push; surface if never recovers. |
| Silent success | `GROK_REVIEW_SILENT=true` | NOT clean — retrigger or hand back; check `XAI_API_KEY` / install step logs. |
| Missing API key | Sticky / run log mentions missing `XAI_API_KEY` | Hand back — repo secret required. |
| Rate / quota | Failed sticky body with API errors | Hand back; metered API billing is separate from SuperGrok interactive login. |

## § Common patterns (codified Tier 1)

Shared catalog: [`common-review-findings.md`](common-review-findings.md). No Grok-specific deltas yet — fold empirical findings here after dogfood.

## § Review-state gate

Comment-anchored: DONE gates on **sticky presence** (marker + login), never on job conclusion. See [`engine-adapter-contract.md`](engine-adapter-contract.md) § Review-state gate (comment-anchored divergence).

## § Bugbot comparison note

| | **Cursor Bugbot** | **Grok Build (this engine)** |
|---|---|---|
| Product | Cursor paid PR reviewer | Grok Build = SuperGrok / X Premium+ **interactive** CLI + **metered** `XAI_API_KEY` for CI |
| Trigger | Request-driven (`bugbot run`) | Auto-trigger on PR push + `grok review` comment |
| State | Named check-run | Actions job → synthesized `GROK_CHECKRUN` |
| Findings surface | Inline review comments + structured check | Sticky issue comment (prose) + marker |
| mind-vault role | Optional review-loop engine | **Parallel / fallback** alongside Claude (Claude remains the primary comment-anchored engine already wired in this repo) |

Bugbot is not replaced by Grok; Grok does not replace Claude. Prefer Claude when its action + `CLAUDE_CODE_OAUTH_TOKEN` are provisioned; add Grok when `XAI_API_KEY` is available and you want a second prose reviewer or a Claude-unavailable fallback.
