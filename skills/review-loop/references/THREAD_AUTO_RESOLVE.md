# Thread auto-resolve — closing review threads in step with the fixes

GitHub review threads (inline `pull_request_review_comments`) carry an independent **isResolved** state from the underlying code state. The "Resolve conversation" button is a separate human gesture; when the review-loop applies a fix in Phase 2 and pushes in Phase 3, the GitHub UI thread stays unresolved until someone clicks. Across a sprint of 10-15 review-loop cycles per PR × N PRs, this accumulates into a substantial cosmetic-noise pile that hides the actual unresolved-thread signal.

This reference defines two patterns:

1. **Forward (in-loop) auto-resolve** — the loop resolves threads as it commits the fix. Prevents accumulation going forward.
2. **Retroactive audit + bulk-resolve** — for PRs that accumulated debt before this pattern landed: a focused Explore-agent audit classifies each thread, an adversarial refute pass confirms any STILL-REAL verdicts, and on a clean verdict (zero **confirmed** STILL-REAL) the orchestrator bulk-resolves via GraphQL mutation.

Both rely on the same primitive: the GitHub GraphQL `resolveReviewThread` mutation.

## Why this matters

| Symptom | Without auto-resolve | With auto-resolve |
| --- | --- | --- |
| PR page reads "32 unresolved conversations" | Even though all 32 code-level findings shipped at review-loop time | Reads what's actually live: 0–2 still-open threads requiring action |
| Future readers grepping a merged PR for "what's still broken" | Have to read every thread + diff to triage | Threads are the signal; isResolved == false means open |
| Reviewers walking the PR | Skim past the noise; risk missing the one real finding hidden in the pile | One real finding stands out |
| The "merge cleanly" gesture | Carries 30+ stale unresolved conversations into the merged-PR view | Clean merge state matches the cleared review-loop state |

In one downstream sprint, a single PR accumulated 32 stale Copilot threads across ~6 review-loop cycles before the pattern surfaced. A cohort-wide audit found **129 stale threads across 11 PRs** — accumulated over ~1 week of sprint activity once a Copilot engine was added alongside Bugbot. Verifying then bulk-resolving via the recipe in § *Retroactive audit + bulk-resolve* closed the entire debt in two phases — an audit (one inventory query plus an agent code-read to classify each thread), then a mutation loop (one `resolveReviewThread` per thread).

## The primitive — `resolveReviewThread` mutation

GitHub's GraphQL exposes a single mutation that marks a review thread resolved. Idempotent — re-resolving an already-resolved thread is a no-op.

```graphql
mutation {
  resolveReviewThread(input: { threadId: "PRRT_kwDOQh1-w86E33Iz" }) {
    thread { isResolved }
  }
}
```

The thread ID is a GitHub-internal node ID (the `PRRT_*` form), retrievable from the `reviewThreads` query at PR-load time:

```graphql
query {
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <pr>) {
      reviewThreads(first: 100) {
        nodes {
          id              # PRRT_* node ID — this is the threadId input
          isResolved
          comments(first: 1) {
            nodes { author { login } url path line body }
          }
        }
      }
    }
  }
}
```

Thread ID ≠ comment ID. The `id` field on `reviewThreads.nodes[*]` is the thread node ID (`PRRT_*`). Comments inside a thread have their own `id` (the `PRRC_*` form — `PullRequestReviewComment`) which is NOT what the mutation accepts. Confusing the two returns `Field 'resolveReviewThread' argument 'threadId' is of wrong type`. (Verified on a real thread: thread `PRRT_kwDORBqOk86FLa57` carries comment `PRRC_kwDORBqOk87Fcypm` — both base64-ish but distinct prefixes.)

The mutation requires write access on the repo. From the GitHub CLI, `gh api graphql -f query='mutation { resolveReviewThread(input: { threadId: "..." }) { thread { isResolved } } }'` works with normal user credentials.

## Pattern 1 — Forward (in-loop) auto-resolve

The review-loop already has a per-finding lifecycle: Phase 1 triages a finding into Tier 1/2/3, Phase 2 applies the fix (or reverts if test fails), Phase 3 batches successful fixes into a single commit + pushes. The auto-resolve extends Phase 3 with one final step: for every finding **closed** in this commit, resolve its thread.

### Capture the thread ID at Phase 1 ingest

The engine adapter (`references/engine-<name>.md`) is the source of truth for parsing the engine's output. Today the adapter emits finding lines tagged `(comment id <cid>, review <rid>)` — that's the staleness anchor against `<ENGINE>_LATEST_REVIEW`. The auto-resolve extends the tag with the thread node ID:

```
<finding body line N> (comment id <cid>, review <rid>, thread <tid>)
```

`<tid>` is the `reviewThreads.nodes[*].id` field — the `PRRT_*` form — captured by joining the engine's REST comment output against a GraphQL `reviewThreads` query at fetch time. Adapter implementations should query both endpoints during their fetch step and merge into the emitted finding tag.

Single-comment engines (Bugbot, Copilot) have a one-to-one mapping: comment `id` → thread `id`. Multi-comment-per-thread cases (a human + bot in the same thread) are rare for review-loop-tracked engines but the adapter should pick the **first** comment's thread ID — the thread, not the comment, is what carries the resolve state.

### Track the resolution decision per finding

The Phase 1 triage decision determines the thread fate:

| Triage tier | Phase 2 outcome | Phase 3 action |
| --- | --- | --- |
| Tier 1 (auto-fix) | Fix applied + test passed | Commit includes finding; resolve thread |
| Tier 1 | Fix applied + test failed → reverted | Commit excludes finding; thread stays open |
| Tier 2 (approve-then-fix) | User approved + fix applied + test passed | Same as Tier 1 success |
| Tier 2 | User approved + fix applied + test failed → reverted | Same as Tier 1 failure |
| Tier 2 | User rejected | Commit excludes finding; thread stays open; record reason in hand-back |
| Tier 3 (escalate) | No fix attempt | Thread stays open; escalation surfaced in hand-back |

The scratch file's per-cycle triage table (see § *Scratch-file persistence* in the parent skill) already records the fix outcome. Extend each row with `thread_id` from the Phase 1 capture and a `resolve_after_push: bool` field set during Phase 2.

### Fire the resolve mutations after the push

Phase 3 already pushes the commit and retriggers the engine. The auto-resolve fits between push and retrigger:

```bash
# After `git push origin HEAD` succeeds:
for tid in <thread_ids_to_resolve_this_cycle>; do
    gh api graphql -f query='mutation {
        resolveReviewThread(input: { threadId: "'"$tid"'" }) {
            thread { isResolved }
        }
    }' >/dev/null
done
# Then retrigger engines as before.
```

The mutations are idempotent + independent — failure on one doesn't poison the rest. Log each `OK` / `FAIL` to the scratch file's per-cycle row so the hand-back can surface partial states.

### Don't auto-resolve threads whose finding got declassified

If Phase 2 surfaces that a finding is actually invalid (the bot was wrong; nothing's broken; or the convention says the bot's recommendation is wrong — see § *WON'T-FIX-CONVENTION* in the retroactive pattern), the thread is still a candidate for resolve — but with the rationale recorded in the resolve mutation's associated reply comment, not silently.

For the WON'T-FIX-CONVENTION case, the recommended shape is:

1. Reply to the thread with a one-line comment naming the convention (e.g. _"Project shell-form callsites use literal URL fragments — see [`feedback_shell_no_full_page_reloads.md`](...). The browser JS pattern map is the URL authority; `reverse()` can't produce shell-fragment URLs."_).
2. Then `resolveReviewThread`.

The reply leaves a discoverable rationale; the resolve closes the noise. Per-engine adapter docs may codify common WON'T-FIX-CONVENTION rationales as reusable canned replies.

## Pattern 2 — Retroactive audit + bulk-resolve

For PRs that accumulated stale threads before the forward pattern landed (or before the review-loop tracked thread IDs), the retroactive flow is a one-shot cleanup:

### Step 1 — Inventory the debt

Sweep all PRs targeting the protected base for unresolved threads grouped by reviewer login:

```bash
for pr in $(gh pr list --state merged --base <protected-base> --limit 50 --json number --jq '.[].number'); do
    count=$(gh api graphql -f query="query {
        repository(owner: \"<owner>\", name: \"<repo>\") {
            pullRequest(number: $pr) {
                reviewThreads(first: 100) {
                    nodes {
                        isResolved
                        comments(first: 1) { nodes { author { login } } }
                    }
                }
            }
        }
    }" --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false) | select((.comments.nodes[0].author.login // "" | sub("\\[bot\\]$"; "")) == "<engine-bot-login>")) | length')
    [ "$count" != "0" ] && echo "PR #$pr: $count"
done
```

`<engine-bot-login>` is the engine's **bare** bot slug (no `[bot]` suffix):

- Cursor Bugbot: `cursor` (REST representation `cursor[bot]`; verify on a known thread — Cursor has shipped under `bugbot` too)
- GitHub Copilot: `copilot-pull-request-reviewer` (REST representation `copilot-pull-request-reviewer[bot]`, as named in `references/engine-copilot.md`)
- Other engines: per `references/engine-<name>.md` § *Bot identity*

**Why bare, and why the `sub("\\[bot\\]$"; "")` in the filter:** the same bot carries two login representations depending on the API surface. GitHub's GraphQL `Bot` actor exposes `login` **without** the `[bot]` suffix (`copilot-pull-request-reviewer`), while the REST comment payload — and `engine-copilot.md` / `engine-bugbot.md`, which document the REST view — carry it **with** the suffix (`copilot-pull-request-reviewer[bot]`). These sweeps run over GraphQL, so the bare form is what `author.login` actually returns today — but rather than depend on that holding across GitHub API changes or actor-type quirks (a bot occasionally surfaces as a `User`, which keeps the suffix), the filter **normalises**: `sub("\\[bot\\]$"; "")` strips a trailing `[bot]` before comparing, so the comparison value is always the bare slug and the recipe matches **both** representations. (`// ""` guards a null author from a deleted account.) Cross-check: if a sweep returns zero on a PR you know has stale bot threads, dump one node's raw `author.login` — `gh api graphql ... --jq '...nodes[0].comments.nodes[0].author.login'` — and confirm the bare slug matches.

### Step 2 — Audit before bulk-resolve

Bulk-resolving without verification risks closing a STILL-REAL finding. Dispatch an Explore-class subagent with the thread inventory as input:

> *For each thread, parse PATH + claim from the body, open the file at that path (line drift is normal post-merge — find by symbol/context, not raw line number), verify the specific assertion against the current code on the post-merge protected base. Classify each thread as:*
>
> - *FIXED — the underlying issue was addressed; safe to bulk-resolve*
> - *STILL-REAL — the issue actually exists; NEEDS ACTION*
> - *WON'T-FIX-CONVENTION — the code follows a documented project convention the bot flagged; convention-vs-bot friction, resolve with optional reply*
> - *DOC-DRIFT — claim is about a docs file that's since been updated; verify then resolve*
> - *UNCERTAIN — couldn't determine quickly; defer to human walk*

Emit per-thread verdict + summary count.

The audit prompt should also brief the agent on **project conventions the bot is likely to mis-flag** — past cohort data is the best source for this. Common categories:

- Literal URL fragments vs `{% url %}` in shell-form templates (browser-JS pattern map as URL authority)
- Inline `onclick="Alpine.store('previewSurface').close()"` vs `data-preview-close` (matters when stores are scoped per surface)
- Lazy QuerySet wrapped in `with_public_schema()` (when evaluation actually happens inside the wrapper)
- `mark_safe(json.dumps(...))` inside `<script type="application/json">` (safe parsing context, not XSS)
- "Comment says X, code does Y" claims (often the comment is accurate to a near-by usage the bot missed)

A 30-thread audit completes in 3-5 minutes; the agent reads enough code to give a verdict per thread.

**Shared-worktree hazard — read with `git show`, never `git checkout`.** Audit and refute agents run in the orchestrator's worktree. To inspect post-merge code they MUST read via `git show <ref>:<path>` (e.g. `git show main:skills/foo.md`) — **never** `git checkout <ref>`, which switches the *shared* worktree's branch out from under the orchestrator mid-run. (Observed during this recipe's own dogfooding: an audit agent told "verify against main" ran `git checkout main` and stranded the parent session on the wrong branch.) If an agent genuinely needs a checked-out tree, give it its own `git worktree`; the default is `git show`.

### Step 2.5 — Adversarially verify every STILL-REAL verdict

The Step 2 audit is a single pass, and a single pass **over-flags STILL-REAL** — it reads a finding's claim, half-confirms it against the code, and returns STILL-REAL on anything it can't immediately dismiss. Because Step 3 gates on STILL-REAL count, an over-flag either **blocks a safe cleanup** or emits a **false punch list** that re-creates the noise the recipe exists to clear (see § *Provenance* for the observed rate). So no STILL-REAL verdict reaches the gate unrefuted.

For **each** STILL-REAL from Step 2, dispatch a second, independent agent whose sole job is to **REFUTE** it:

> *Claim: `<finding body + cited PATH>`. Open the file at PATH (via `git show <ref>:<PATH>` per the hazard note above; line drift is normal — find by symbol/context). **Your default verdict is FALSE-POSITIVE.** Flip to CONFIRMED only if the specific broken thing the claim describes is present **verbatim** in the current file. If the file already contains reconciling/defining text — the next line clarifies it, the value is already guarded, the cited string doesn't exist — it's FALSE-POSITIVE. Return `CONFIRMED | FALSE-POSITIVE` + the one line of evidence.*

The refuter's bias is the **opposite** of the auditor's: absence of verbatim evidence of breakage flips the verdict. Only verdicts surviving as **CONFIRMED** count as STILL-REAL for the Step 3 gate and the punch list; everything refuted re-files as FIXED. If Step 2 returned zero STILL-REAL, skip this step. Run the refuters concurrently (one per STILL-REAL — a handful of agents, ~a minute of wall-clock). This is the same high-confidence-before-mutation model Pattern 1 relies on, applied to the retroactive half.

### Step 3 — Bulk-resolve on a clean verdict

If Step 2.5 leaves **zero confirmed STILL-REAL** verdicts, bulk-resolve every audited thread:

```bash
for pr in <PRs-with-stale-threads>; do
    THREAD_IDS=$(gh api graphql -f query="query {
        repository(owner: \"<owner>\", name: \"<repo>\") {
            pullRequest(number: $pr) {
                reviewThreads(first: 100) {
                    nodes {
                        id
                        isResolved
                        comments(first: 1) { nodes { author { login } } }
                    }
                }
            }
        }
    }" --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false) | select((.comments.nodes[0].author.login // "" | sub("\\[bot\\]$"; "")) == "<engine-bot-login>")) | .[].id')
    for tid in $THREAD_IDS; do
        gh api graphql -f query="mutation {
            resolveReviewThread(input: { threadId: \"$tid\" }) {
                thread { isResolved }
            }
        }" >/dev/null
    done
done
```

If Step 2.5 confirms **any STILL-REAL**: do NOT bulk-resolve. Surface the confirmed list to the user as a punch list. Resolution gates on actually fixing those. (Refuted verdicts are not on the punch list — that is the point of Step 2.5.)

The mutations are individually authenticated against the user's GitHub token. No special permissions beyond write access on the repo. The full sweep + audit + resolve cycle for 100+ threads takes under a minute of wall-clock.

### Step 4 — Don't comment on each PR

The temptation is to leave a "bulk-resolved per audit X" comment on each PR for paper-trail discoverability. **Skip it.** Comments are themselves noise — adding 11 PR comments to clean up 129 stale threads recreates the very signal pollution the resolve is trying to clear. The paper trail lives in:

- The compound PR that captured this pattern (this reference's commit history)
- The audit's per-thread verdict log (the agent's task output, persisted in the project's artefacts/ as needed)
- Memory entries naming the cleanup event for future sessions

That's enough provenance. The PR thread pages then read clean.

## Risks + when not to fire

### When forward auto-resolve should NOT fire

1. **The fix is partial.** Test passed but only one of two claims in a multi-part finding was addressed → keep the thread open; record the partial in hand-back.
2. **The fix was the loop itself (no human review).** For Tier 1 auto-fixes the loop's confidence is high enough; this is the design. For Tier 2 the user already approved direction. Neither is at risk.
3. **The thread has a human reply discussing alternative approaches.** Resolving may cut off discussion. Check `reviewThreads.nodes[*].comments.totalCount > 1` AND any non-bot author in comments → leave the thread alone, let the human steer.
4. **Engine in `RUNNING` state** — wait for the engine to reach `DONE` for the post-fix SHA before resolving anything from the prior review. Resolving threads of a still-running review can confuse the engine's own clean-clean count.

### When retroactive audit should NOT auto-resolve

1. **Confirmed-STILL-REAL count > 0** (survived the Step 2.5 refute pass). Stop and surface the punch list. A first-pass STILL-REAL that the refuter flips to false-positive does **not** count here — gating on raw first-pass verdicts is what over-blocks.
2. **UNCERTAIN count > ~10% of total.** The audit isn't confident enough; route to a human walk before bulk-resolving the others.
3. **Cross-engine ambiguity.** The same finding flagged by two engines, one resolved + one not, indicates one engine's signal is healthier than the other. Audit per-engine separately.
4. **PR is still in active review.** Only fire on PRs that are MERGED or have completed their review-loop cycle. Open PRs may still receive fresh findings the audit's snapshot won't catch.

## Adapter contract — what engine-<name>.md should declare

Per the engine adapter contract in `references/engine-adapter-contract.md`, each engine reference now should declare its bot identity for the thread-author filter:

```markdown
## Bot identity (for thread auto-resolve)

- **Comment author login (bare slug)**: `copilot-pull-request-reviewer` (or `cursor`, etc.) — record the bare form; the GraphQL `author.login` drops the `[bot]` suffix the REST payload carries, and the sweep filter normalises with `sub("\\[bot\\]$"; "")` so either representation matches
- **One thread per finding**: yes / no — engines that batch multiple findings per thread need a different mapping
- **Thread reply support**: yes / no — whether the engine reacts predictably to a posted reply (matters for WON'T-FIX-CONVENTION canned replies)
```

These three facts are the minimum the orchestrator needs to wire forward auto-resolve + retroactive audit + clean-rationale-reply flow per engine.

## What this displaces

Earlier versions of the review-loop skill treated thread-resolution as "human follow-up after the loop hands back" — implicitly out-of-scope. That's why the false-positive pattern in `references/engine-copilot.md` doesn't currently address the noise it creates downstream.

This reference makes thread-resolution part of Phase 3 + provides a one-shot retroactive cleanup recipe. The engine-copilot reference should gain a "Bot identity" section per § *Adapter contract* above on next touch; bugbot too.

## Provenance

Pattern surfaced in a downstream sprint where 11 PRs accumulated 129 stale Copilot threads over ~1 week of review-loop activity. A focused Explore-agent audit verified 26 FIXED + 2 DOC-DRIFT-also-FIXED + 4 WON'T-FIX-CONVENTION across the largest PR's 32 threads (0 STILL-REAL); the bulk-resolve cleared all 129 with zero failures. The Forward (in-loop) pattern was the obvious "and never again" follow-on.

**Step 2.5 (adversarial verify) was added after dogfooding the retroactive recipe against mind-vault's own ~250-thread pile (17 merged PRs).** The single-pass Step 2 audit returned a scatter of STILL-REAL verdicts across several PRs — and on hand-verification, **5 of 5 spot-checked STILL-REAL were false positives**: a CHANGELOG line read as a dead reference when it was accurate past-tense history; an `<img>` flagged as live HTML when it was already inside a code span; a contract "contradiction" the very next line reconciles; "absence semantics undefined" that two adjacent lines fully define; and a "see below / spacing" cross-reference that did not exist in the file at all. Because Step 3 gated on raw STILL-REAL count, those phantoms would have blocked the entire safe cleanup (or shipped a noisy false punch list). A second agent prompted to *refute* — defaulting to false-positive absent verbatim evidence — collapses that error class. The lesson generalises: **a lone audit pass is a finder, not a verifier; the retroactive half needs the same adversarial confidence the forward half gets for free.**
