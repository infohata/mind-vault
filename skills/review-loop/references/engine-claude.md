# engine-claude — Claude Code Review adapter (action + `code-review` plugin)

Adapter specification for the Claude review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## ⚠️ READ THIS FIRST — the action + `code-review` plugin is NOT the managed Claude Code Review App

This engine drives `anthropics/claude-code-action@v1` running the **`code-review` plugin** via a self-hosted `.github/workflows/claude-code-review.yml` workflow (OAuth/subscription-billed). It is **NOT** Anthropic's managed *Claude Code Review* GitHub App.

| Surface | Managed App (we do NOT use) | Action + `code-review` plugin (what we drive) |
| --- | --- | --- |
| Named check-run | ✅ `Claude Code Review` check-run | ❌ none — only the GitHub **Actions job** status |
| Machine-readable verdict | ✅ severity JSON | ❌ findings are plain inline + summary comments |
| Clean signal | severity JSON empty | summary-comment body substring OR zero head-SHA inline comments |

✅ **DO** read review-state off the **Actions job** of the `claude-code-review` workflow run, and clean off comment structure.

❌ **DON'T** look for a `Claude Code Review` check-run or severity JSON — anything you read at `code.claude.com/docs` describing those describes the *managed App* and **does not apply here**. There is no named check-run to poll; polling for one returns nothing and the loop hangs to HUNG.

## § Identity

- Vendor: Anthropic — `anthropics/claude-code-action@v1` running the `code-review` plugin.
- Install path: **do NOT rely on `/install-github-app`'s default template — it ships `pull-requests: read` / `issues: read`, which silently blocks the action from POSTING findings** (a findings-bearing run posts nothing → `find_claude_comments.sh` reads a FALSE CLEAN via the zero-inline arm). Onboard by committing **our own write-perm templates** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) + [`../assets/claude.yml`](../assets/claude.yml)) to the **default branch**, porting `find_claude_comments.sh` + `claude_retrigger.sh` into `tools/`, and wiring `CLAUDE_CODE_OAUTH_TOKEN`. Full procedure + the anti-tampering bootstrap catch-22 (why the perms change can only take effect from the default branch): [`engine-claude-onboarding.md`](engine-claude-onboarding.md). The drop-the-two-workflows part of `/install-github-app` is fine as a starting point — but immediately replace the perms + add the guards.
- GitHub UI surface — **comment-anchored, no named check-run**:
  - Inline findings on `/pulls/<N>/comments`.
  - A top-level summary comment on `/issues/<N>/comments`.
  - The only RUNNING/DONE surface is the **GitHub Actions job** of the `claude-code-review` workflow run (`/actions/workflows/claude-code-review.yml/runs`).
- **Identity — CONFIRMED `claude[bot]`** for posted reviews (findings-bearing run, downstream non-draft PR, 2026-06-03). When the action actually POSTS a review — inline findings **and** a top-level **"Code review" summary comment** — the author login is **`claude[bot]`**.
  - ⚠️ **The PR #167 dogfood "confirmed `github-actions[bot]`" was WRONG** — it calibrated on a CLEAN run that posted *no claude content*, mistaking the workflow's PR-size-check / `github-actions[bot]` comment for claude's review. Never calibrate identity off a run that posted nothing. `find_claude_comments.sh`'s `CLAUDE_LOGINS` includes `claude[bot]` (plus `github-actions[bot]` / `claude-code-action[bot]` as harmless over-coverage), so detection was robust either way — but the doc was wrong.
  - **Inline review comments → login-only** (login ∈ `CLAUDE_LOGINS`). Review output by construction; the safe direction (over-count → keep polling, never a false clean).
  - **Summary issue comment → BOTH-AND** (login AND body signature). A findings-bearing run **does** post a "Code review" summary (e.g. "N issues found … No bugs detected" / "No bugs or security issues found"), so this arm is **live, not dead backup** — and the body signature stops a stray bot "no issues" comment faking a clean.

## § Tool invocations

- `./tools/find_claude_comments.sh <PR_NUMBER>` — probes engine reachability (below), then synthesizes the contract-shape stream: `CLAUDE_CHECKRUN=... STATUS=<queued|in_progress|completed>` from the **Actions job** (latest run by `run_started_at` for the head SHA), `CLAUDE_LATEST_REVIEW=...` anchored on the summary-comment id (or newest head-SHA inline comment id if no summary), inline finding blocks each carrying the mandatory `(comment id <cid>, review <rid>)` token, **summary-BODY finding blocks** carrying `(comment id <cid>, review summary)` when the `## Code review` summary itself is findings-bearing (the C1 surface — see § calibration update — findings live in the SUMMARY BODY), and an optional legacy `CLAUDE_CLEAN_SIGNAL=...` (non-authoritative). May also emit `CLAUDE_NOT_INSTALLED=true` (reachability), `CLAUDE_DRAFT_NOOP=true` (draft PR — no review), or `CLAUDE_REVIEW_PENDING=...` (race guard).
- `./tools/claude_retrigger.sh <PR_NUMBER>` — **fallback only.** Posts the hard-coded `@claude review once` comment. Pre-approvable in `~/.claude/settings.json`. See § Push-triggered model below — Phase 3 does NOT call this after a fix push.

**Reachability probe (A2 / R4).** `find_claude_comments.sh` probes `gh api .../actions/workflows` for `claude-code-review.yml` by filename. If the workflow is absent it emits `CLAUDE_NOT_INSTALLED=true` and exits 0, so the orchestrator's default-engine resolution can **self-exclude** claude rather than poll an un-provisioned engine to HUNG.

✅ **DO** let claude self-exclude from the *default* set on repos where the action isn't installed.

❌ **DON'T** treat `CLAUDE_NOT_INSTALLED=true` on an *explicit* `/review-loop <PR> claude` as a silent skip — it degrades **loudly**: hand back with a clear "claude action not installed (run `/install-github-app`)" message. Loud-not-silent is the contract.

## § Push-triggered for the FIRST review; EXPLICIT retrigger for every review after (A7 — CORRECTED, PR #169 self-dogfood)

The `claude-code-review.yml` action auto-runs on every push (`synchronize`), **but the `code-review` plugin skips the auto-run once claude has already posted a review on the PR** — it posts a `## Code review\n\nSkipping review — Claude has already posted a code review comment` no-op instead of a fresh review. So the push is the retrigger **only for the first review**:

- The **push auto-run produces a real review ONLY the first time** claude sees the ready PR (any push before claude has commented). 
- Every **subsequent push auto-SKIPS** → no fresh verdict (a "Skipping review …" no-op, caught by `CLAUDE_NOOP_PATTERNS`). Verified PR #169: pushes `06b3a3b` + `16e6dd4` both skip-no-op'd after the first review on `7399749`.
- An **explicit `@claude review`** (`claude_retrigger.sh`) **overrides the skip and forces a fresh review.** Verified PR #169: the explicit retrigger produced a full 3-minute review where the two prior pushes had skipped. Note the explicit path posts in the **@-mention / task format** ("Claude finished @user's task … ### Code Review …") — a different shape than the auto "## Code review" summary; the catch-everything classifier (§ Review-state + clean detection) handles both.

✅ **DO** let the **FIRST** claude review come from the push / un-draft auto-run (no explicit retrigger needed before claude has commented).

✅ **DO** fire `claude_retrigger.sh` after a Phase-3 fix push **once claude has already reviewed the PR** — the push auto-run will skip, so the explicit `@claude review` is the only thing that gets a fresh verdict on the fix. **This REVERSES the prior "the push IS the retrigger, don't double-fire" guidance, which was wrong for the 2nd+ review** (the feared double-run race doesn't occur: the auto-run skips, so the explicit retrigger is the sole review).

❌ **DON'T** expect a fix push alone to re-review after claude's first comment — it skip-no-ops, and the loop will read the stale prior verdict (or a no-op) until you explicitly retrigger.

The retrigger script also covers the **zero-activity bootstrap**: no Actions run at all for the head SHA (fresh PR / just-installed workflow).

**Dedup.** `find_claude_comments.sh` always selects the **latest Actions run by `run_started_at`** + the newest summary comment for the head SHA, so any auto-run / fallback overlap collapses to one authoritative signal.

### ⚠️ DRAFT PRs get NO posted review — the action runs but posts nothing

**On a draft PR, the Actions run fires (`synchronize` fires on draft pushes) and concludes `success`, but claude POSTS NOTHING** — no inline findings, no summary. So a draft PR reads as **SILENT / false-clean-vector**, *not* clean. Confirmed by an A/B on one commit (downstream, 2026-06-03): the same tree read SILENT while draft and posted a full review (summary + 2 inline findings) the instant the PR was marked **ready for review**. This — not `#1087` — was the actual cause of every "ran but posted nothing" result during the engine's bring-up; the `#1087` post-session-capture bug is a *separate*, rarer failure.

✅ **DO** ensure the PR is **ready-for-review (not draft)** before trusting a claude verdict; the workflow already lists `ready_for_review` in its trigger types, so un-drafting auto-fires a real review.

❌ **DON'T** read a draft PR's silence as a finding about the code — it's the draft no-op.

**Adapter belt-and-suspenders:** `find_claude_comments.sh` now probes `gh ... pulls/<PR> .draft` up-front and, on a draft PR, emits **`CLAUDE_DRAFT_NOOP=true`** + exits early (instead of fetching runs → eventually SILENT). So even if `/review-loop`'s pre-flight un-draft is skipped or fails, the loop sees a clear "no claude verdict until ready (un-draft the PR)" signal, never a misattributed SILENT/HUNG/clean. In normal flow the pre-flight un-drafts before Phase 1, so this never fires.

**✅ Use the draft no-op as a deliberate lever — the recommended sprint cadence.** claude is the only **push-triggered** engine (bugbot/copilot are on-demand inside the review-loop), so a non-draft PR auto-runs — and bills — a claude review on **every** `/work` commit push. Keep the PR in **draft during `/work`** to suppress that, iterate freely, and **flip to ready-for-review after `/wrap`** — that single un-draft fires one intentional claude review on the finalized state, which the `/review-loop` then drives alongside bugbot/copilot. Net: one billed review per cohesive change instead of one per WIP push, and no SILENT-on-WIP noise. (If you *want* a mid-`/work` claude pass, momentarily mark ready or trigger bugbot/copilot, which don't need the un-draft.)

## § Review-state + clean detection

**Review-state is synthesized from the Actions job, not a check-run.** `find_claude_comments.sh` filters `claude-code-review.yml` runs to the head SHA, picks the latest by `run_started_at`, and maps `queued`/`in_progress` → **RUNNING**, `completed` → **DONE**. The Actions `CONCLUSION` is **green whether claude found 0 or 5 issues** — it is a RUNNING/DONE signal only, NEVER a verdict.

**Clean requires a POSITIVE posted signal — never zero-inline alone (A6 / LAYER 2).**

```text
clean    ⟺  claude POSTED a clean summary (body contains case-insensitive
            substring "no issues found")  AND  zero inline findings
findings ⟺  inline comments posted on the head SHA
SILENT   ⟸  run `success` (DONE) but NOTHING posted after settle
            → NOT clean (held RUNNING; see § Failure modes)
```

**Why not "zero inline = clean" (the original A6 belt-and-suspenders, reversed by verified research).** A claude run can report `success` having posted **nothing** — action issue [#1087](https://github.com/anthropics/claude-code-action/issues/1087): the plugin buffers inline comments for a post-session step whose result-capture grabs a `TodoWrite` response instead of the review → empty → no comment. "success + silent" is **indistinguishable from genuinely-clean** ([#1054](https://github.com/anthropics/claude-code-action/issues/1054)) by run status, so zero-inline is a **false-CLEAN vector**, not a clean signal. Clean now demands a posted clean summary; the **fixed workflow** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) — `classify_inline_comments:false` + `claude_args` post-during-run + a prompt that forces a posted summary *even when clean*) is what makes a genuinely-clean run actually post that summary. The substring (not the full sentence) follows the copilot lesson (`find_copilot_comments.sh:182-189`).

The legacy `CLAUDE_CLEAN_SIGNAL` line is corroboration only; the orchestrator derives clean structurally (DONE + zero active findings) — which is correct ONLY because the adapter holds a no-verdict run RUNNING (so DONE is reached only with a posted clean summary or posted findings).

✅ **DO** read clean off a POSTED clean summary + zero inline findings.

❌ **DON'T** read clean off zero-inline alone, nor off the Actions `CONCLUSION`. Both pass on a #1087 silent drop → false CLEAN.

## § Staleness rule

Keyed on **comment ids** (synthesized anchor), not a review id. `CLAUDE_LATEST_REVIEW` = the summary-comment id, or the newest head-SHA inline comment id when no summary exists. Each inline finding carries `(comment id <cid>, review <rid>)`; whether the inline comments share a single `pull_request_review_id` is **unconfirmed** (Q1, § residual open questions) — the anchor keys on the comment id either way, so the rule is safe regardless. When `<rid>` is null/absent the orchestrator tolerates an empty review token for comment-anchored engines.

## § Race-condition caveats

**The settle valve releases on comment PRESENCE, not Actions conclusion (A3 — load-bearing).** This is the divergence from copilot's `CONCLUSION=success` settle gate. claude's Actions job flips to `completed` *before* its summary/inline comments post — a poll in that gap sees DONE + zero findings → false CLEAN.

So a `completed` Actions run with **no readable verdict** (no posted findings AND no clean summary) is held at `STATUS=in_progress` (RUNNING) so the orchestrator's "DONE + zero findings = CLEAN" can't fire on it. The settle window (`CLAUDE_REVIEW_SETTLE_SECONDS`, default **180**) only picks the marker — it never releases a no-verdict run to DONE:

- **within window** → `CLAUDE_REVIEW_PENDING` (comments may still be landing — race).
- **window elapsed** → `CLAUDE_REVIEW_SILENT` (nothing came → **NOT clean**: #1087 drop / read-only perms / un-fixed workflow). Stays RUNNING; the loop hands it back as uncertain (re-trigger / verify perms), never auto-clean.

**Settle window is 180s, not copilot's 600 (calibrated PR #167).** claude-code-action posts its inline comments *synchronously within the job* — the post step runs **before** the run reports `completed`, so comments (if any) already exist at completed-time. The window only covers GitHub API read-consistency after that in-job post, not copilot's minutes-long async-review lag.

✅ **DO** treat `CLAUDE_REVIEW_SILENT` as uncertain/needs-retrigger — never clean.

❌ **DON'T** copy copilot's `CONCLUSION=success` settle gate, and DON'T release a no-verdict run to DONE on settle-elapse (the original "zero-inline arm" — that's the #1087 false-CLEAN). claude concludes `success` even WITH findings, so conclusion is never consulted.

Settle age is computed in Python `datetime` (cross-platform), never `date -d`.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| claude action not installed | `CLAUDE_NOT_INSTALLED=true` (no `claude-code-review.yml` workflow on the repo) | Self-exclude from the **default** set (bare `/review-loop`); on an **explicit** `claude` run, degrade **loudly** — hand back with "run `/install-github-app`", never HUNG, never silent. |
| **Draft PR (no review posted)** | `CLAUDE_DRAFT_NOOP=true` — the PR `.draft` is `true` (adapter early-exits) | Not a verdict — the draft no-op. `/review-loop` pre-flight should have un-drafted (`gh pr ready`); if this still fires, un-draft and re-poll. NEVER read as clean/SILENT/HUNG. |
| claude stalled | Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` — **but claude's normal latency is long (up to ~17 min on a large PR); confirm genuinely wedged, not merely slow — see § slow-not-hung** | Proceed with other engines' findings if any; do NOT explicitly retrigger (push-triggered — the next fix push re-runs it). **Before treating it as stalled, run the § slow-not-hung checks (step-progress + verdict re-fetch).** Surface in hand-back if it doesn't recover within the idle-poll budget. |
| Actions job unreadable | `actions: read` blocked for the user's `gh` auth — `WORKFLOW_RUNS` empty, no `CLAUDE_CHECKRUN` (Q3) | Degrade to summary-comment-only state (lose the RUNNING signal) with a logged warning. Do NOT hard-fail the loop. |
| **Silent run (success + nothing posted)** | `CLAUDE_REVIEW_SILENT=...` — run `completed`/`success` but NO findings and NO clean summary after settle (held RUNNING) | **NOT clean.** Hand back as uncertain: re-trigger once, and verify the workflow has the reliability fixes + `pull-requests: write` (LAYER 1/2). Most likely the #1087 buffer-drop, a read-only-perms posting block, or an un-fixed/old workflow — never read as a clean pass. Don't wait for the full idle-timeout; the SILENT marker is the terminal signal. |

**Robust-mode alternative (record-only).** #1087 is an *open* upstream bug — the workflow fixes *mitigate* (post-during-run) but don't *guarantee* (the model can still end on a `TodoWrite` before posting). For guaranteed reliability, Anthropic's **managed Code Review GitHub App** (`@claude review`, Team/Enterprise) writes findings to **check-run annotations** independent of the comment buffer — but it's paid (~$15–25/review), research-preview, and unavailable under Zero Data Retention. If a project hits persistent SILENT despite the fixes, the managed App is the escalation path (a different adapter — it *does* post a named check-run, unlike this action path). Tracked in IDEA-012.
| Review-pending race | Actions job `completed` but no head-SHA summary/inline comment yet | Downgraded to RUNNING + `CLAUDE_REVIEW_PENDING` (§ Race-condition caveats). Keep waiting; never a premature CLEAN. |

## § slow-not-hung — don't escape-hatch a long claude run on elapsed time alone

claude's review legitimately runs **much longer than bugbot/copilot** — observed up to **~17 min** on a large multi-file PR (vs the ~1–9 min seen on small diffs). The multi-engine stall escape-hatch ([`multi-engine-sync.md`](multi-engine-sync.md) § Trade-off escape hatch) must therefore **not** fire on elapsed wall-time alone — that's how a still-working run gets abandoned one beat before it posts.

Field near-miss (the source of this note): a ~17-min run was treated as hung and superseded by a fix push; it then posted real findings essentially immediately after — the supersede had thrown them away, and a human surfaced the missed findings by hand. Two findings were lost to the loop.

Before tripping the escape-hatch on claude:

1. **Confirm genuinely wedged, not just slow.** Read the Actions job's *step progress*, not just elapsed time: `gh run view <run-id>` (or `--json jobs`). A job advancing through steps is working; a job parked on one step well past its normal duration is wedged. *No step movement* is the wedged signal — elapsed-since-start is not.
2. **Re-fetch for a late-posted verdict FIRST.** Re-run `find_claude_comments.sh` immediately before superseding — claude posts its summary/inline comments synchronously near the **end** of the job (§ Settle window), so a run that was verdict-less five minutes ago may have just posted. A supersede that skips this re-check is the exact shape of the near-miss.
3. **Raise the stall ceiling for claude specifically.** Whatever per-engine stall threshold the loop carries, claude's must sit comfortably above its ~17-min observed worst case — a ceiling tuned to copilot/bugbot's minutes mis-classifies a healthy claude run as hung.

This pairs with the RUNNING-state machine (§ Review-state gate): a `completed` Actions run with no readable verdict is held at RUNNING precisely so the loop can't read a no-verdict run as CLEAN — and the same discipline says **don't read a still-RUNNING run as hung** until step-progress proves it. (It also pairs with the C1 calibration: even once it posts, claude's findings often live only in the summary BODY, so a too-early supersede skips them twice over — never fetched, never surfaced.)

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No claude-specific deltas at present; claude's behavioural quirks live in § Review-state + clean detection and § Race-condition caveats above. (claude's comment-body finding markers are now calibrated — see § calibration update — findings live in the SUMMARY BODY; the severity stamp on a summary-body finding is a heuristic, re-triaged by the loop.)

## § Review-state gate

claude exposes its review-state as `CLAUDE_CHECKRUN ... STATUS=<status>` **synthesized from the Actions job** (there is no native check-run — see the trap banner at the top). `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**; `CONCLUSION` is never a verdict.

**Clean for claude**: Actions job DONE AND (summary-comment body contains "no issues found" OR zero active head-SHA inline findings matching `CLAUDE_LATEST_REVIEW`). The review-pending guard (§ Race-condition caveats) holds the loop in RUNNING until a head-SHA comment posts, so the DONE-before-comments gap cannot fire a false CLEAN. The orchestrator retriggers only from the zero-activity bootstrap (push-triggered otherwise) and never while RUNNING, so no inter-retrigger interval exists.

## § calibration update — findings-bearing + clean runs (downstream non-draft, 2026-06-03)

Two runs on the SAME commit, non-draft, settled the open questions:

- **Findings-bearing run → POSTS a full review.** ~9-minute run; posted inline findings + a top-level **"Code review" summary** ("N issues found … No bugs detected") under **`claude[bot]`**. So claude **does** post findings reliably on a ready-for-review PR — the long-pending findings-path question is answered YES.
- **Clean run → SILENT (still).** After the findings were fixed, the re-review on the clean tree finished in **~1 minute** and posted **nothing** — no inline, no summary — well past settle → `CLAUDE_REVIEW_SILENT`. **The LAYER-2 forced-summary prompt does NOT fire on a clean run**: the action short-circuits ("nothing to flag") and exits without posting the "no issues found" summary it was instructed to post. So the mitigation works for *findings* but not for *clean*.

**Net engine capability (action + `code-review` plugin):** posts **findings** reliably. ⚠️ **The "never posts a positive clean verdict — a clean PR reads SILENT" claim below is OUTDATED as of 2026-06-08 — see § COUNTER-OBSERVATION** (clean verdicts now post on both trigger paths; likely an upstream fix). The historical claim, preserved for context: a clean PR read SILENT (correctly held non-clean by the detection, so SAFE, but never a green "claude says clean"), so claude contributed findings only, never a CLEAN signal. That was the basis for IDEA-012 keeping the **managed Claude Code Review App** (named check-run, verdict independent of the comment buffer) as the robust-mode answer — still the most reliable, but the action path now does usually post clean.

## § calibration update — findings live in the SUMMARY BODY (downstream, 2026-06-03)

The first *high-volume* findings-bearing run (13 `claude[bot]` summary comments across a long iteration) exposed that the prior "findings = inline comments + a short summary" model **undercounts where claude puts findings**. CALIBRATED against the real bodies; the adapter (`find_claude_comments.sh`) was fixed to match (the **C1** fix). Corrections (the last two added by the PR #169 self-dogfood — running this engine on the PR that ships C1):

- **Findings often post ONLY in the summary BODY, not inline.** claude's convention findings (CLAUDE.md docstring violations) and cross-file findings it can't line-anchor (privilege-escalation spanning a form + a view) are written as a structured report **inside the `claude[bot]` "## Code review" issue-comment body** — `### Bugs / Security`, `#### 1. …`, `### CLAUDE.md compliance / Docstrings missing …` — with **zero inline comments**. The old adapter only read the summary body for the clean substring, never surfaced its findings → claude's convention review was **invisible to the loop** (the user surfaced ~6 URL + ~30 docstring findings by hand). Fix: the adapter now surfaces a findings-bearing summary body as a finding block carrying `(comment id <cid>, review summary)`.
- **The summary heading is literally `## Code review` (space), which the old `code-review` (hyphen) signature did NOT match** → the whole summary was unrecognized. Signature widened to `code[ -]?review`.
- **Clean is WHOLE-REVIEW, not substring-anywhere.** claude clears sections independently: a single review says **"Bugs: No issues found."** in one section AND lists **"Docstrings missing"** in another. A bare `'no issues found' in body` test **false-cleans** that mixed review (the dangerous direction). Clean requires a positive clean phrase (`no issues/bugs/problems found`) AND the **absence of any finding marker** (structural, not security-keyword: a genuinely-clean review NAMES the concepts it checked, e.g. *"the privilege-escalation guard looks correct"*, so `privilege`/`escalation` as markers false-positive on clean prose). Re-validated against all 13 downstream bodies (2026-06-03): **3 NOOP, 9 FINDINGS** (incl. every mixed clean-bugs-but-dirty-compliance review), **1 CLEAN** (the final whole-review verdict) — **zero false-cleans** (the PR body's "2 NOOP / 10" was an off-by-one miscount; all three `Skipped` bodies are genuine no-ops).
- **No-op skip bodies must be filtered — ANCHORED.** claude posts `## Code review\n\nSkipped — …draft status` and `## Code review\n\nSkipped: …already reviewed this PR` issue comments that match the signature but are **not verdicts**. Anchored to the heading-then-`Skipped` shape (`^##\s+code[ -]?review\s*\n+\s*skipped`, `re.MULTILINE`) — **not** a bare search-anywhere — so a real findings body whose *prose* merely says "already reviewed in PR #N but regressed" is not false-filtered (PR #169 self-dogfood caught the old unanchored `already (posted|reviewed)` arm dropping exactly that — claude's finding body literally contained "already reviewed").
- **Surface is CATCH-EVERYTHING, marker-INDEPENDENT (PR #169 self-dogfood).** Review format is **non-deterministic** — count-line ("One issue found.") + ``### `file` `` headers in one run, `#### 1.` numbered + `### Bugs` sections in another, future runs may differ again. So the adapter does **not** require a matched marker to surface findings: a posted, non-no-op summary is **either provably-clean OR surfaced-as-findings** (`findings = posted ∧ ¬clean`). Markers now only gate the *clean* determination + severity. An unseen future finding shape therefore can never read SILENT. (The dogfood: claude posted "One issue found." under ``### `file` `` while reviewing this adapter; the marker-only logic read SILENT and dropped it — the inversion + anchored no-op are the fix.)

This does **not** change the findings-side capability: claude posts findings reliably; the C1 fix only stops claude's *findings* — when they exist and live in the body — from being silently dropped. (The "never a positive clean verdict / clean reads SILENT" half of this is **outdated as of 2026-06-08** — see § COUNTER-OBSERVATION; clean verdicts now post on both paths.)

## § COUNTER-OBSERVATION — clean trees DO post a positive clean verdict, on BOTH paths (PR #190 + #192, 2026-06-08)

Two independent, reproducible data points **against** the "clean always reads SILENT" claim above — now confirmed on **both** trigger paths, so the §158 SILENT-on-clean behaviour is no longer the whole story:

- **Observation 1 — explicit-retrigger path (PR #190).** First claude run fired on `ready_for_review` over a tree with one real (bugbot-found) finding → claude went **SILENT** (run `completed`, posted nothing — the expected #1087 / short-circuit behaviour). The finding was fixed, pushed, and claude was **explicitly retriggered via `claude_retrigger.sh`** (`@claude review` / `claude.yml`). On the clean post-fix tree it posted a **positive whole-review clean summary** — `find_claude_comments.sh` read `CLAUDE_SUMMARY_ID=… CLEAN=true FINDINGS=false`, loop terminated structurally **CLEAN** off claude.
- **Observation 2 — push / auto-run path (PR #192).** On the *first* claude review of a clean tree (the PR-open auto-run on `claude-code-review.yml`, **no retrigger**), claude **again posted a positive clean summary** → `CLEAN=true FINDINGS=false`, structurally CLEAN. This is the path §158 said short-circuits to SILENT on clean — and here it did not.
- **What this changes.** The **push-vs-retrigger asymmetry hypothesis is WEAKENED** — claude posted a positive clean verdict on *both* paths within the same day. The §158 "clean run → SILENT (still)" + §Net-capability "never posts a positive clean verdict" claims are at minimum **no longer reliably true**; the most likely explanation is **upstream improvement to the action's clean-path posting** (a `code-review`-plugin or `claude-code-action` update between the §158 calibration and 2026-06-08), not a path-specific quirk. Still possible: SILENT-on-clean recurs intermittently (the #1087 buffer-drop is an *open* upstream bug), so this is "clean verdicts now usually post" — NOT "SILENT-on-clean is impossible."
- **Loop consequence (unchanged for safety).** Detection is structural (clean = DONE + posted clean summary + zero finding markers), so a posted clean verdict reads CLEAN correctly and any residual SILENT run still reads NOT-clean. The adapter needs no change to be *safe*. What changes is *reliance*: claude **can now usually be a CLEAN source** (both paths observed). Treat a clean claude verdict as a real signal; but because SILENT-on-clean can still recur (open #1087), do **not** hard-depend on claude being the *sole* clean gate — keep a second engine (bugbot) when a definitive clean matters. Promote further (drop the "usually") only if SILENT-on-clean goes unseen across a longer run of clean PRs.

## § residual open questions (post-downstream calibration)

The §131 + §140 downstream blocks supersede the PR #167 first-run calibration — identity (`github-actions[bot]` → **`claude[bot]`**), the dead "zero-inline-only, no summary" posting model, and `CLAUDE_BODY_SIGNATURES` wording are all now confirmed. Two items survive it:

- **Never calibrate "clean" off a read-only (`pull-requests: read`) run.** The PR #167 run read clean only because it had nothing to flag; read-only silently **cannot post**, so a *findings-bearing* read-only run would fail to post → false CLEAN. Fix is `pull-requests: write` + `issues: write` (§ Identity + onboarding reference).
- **Still open:** **Q2** — the `claude_retrigger.sh` `@claude review once` fallback is unexercised (the action auto-runs on push); confirm if a future auto-run fails to fire. **Q1** — whether inline findings share a `pull_request_review_id` is unobserved; the anchor keys on comment id either way (§ Staleness), so safe regardless.
