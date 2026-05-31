# Large-PR escalation — don't trust a single fast-bot clean pass

A fast review engine (Bugbot / Copilot) that returns **CLEAN on a very large PR in a single pass** is
a weak signal, not a strong one. Fast bots sample and summarize; on a diff spanning dozens of commits
and thousands of changed lines, a one-shot clean verdict can mean "reviewed shallowly and found
nothing obvious" rather than "reviewed thoroughly and it's sound." Treat a large-PR clean pass as
*necessary but not sufficient*.

## When to escalate to an independent deep review

Heuristic threshold (tune per project): the PR is **large** when it crosses roughly any of —

- **≥ ~25 commits**, or
- **≥ ~2,000 net changed lines**, or
- it touches a **high-blast-radius surface** (WebSocket/streaming lifecycle, auth/permission gates,
  embed/security model, a monolithic file with hardcoded DOM ids, schema/migration).

When a large PR gets a single-engine clean pass (or one engine cleared and the other errored/was
shelved), escalate: dispatch an **independent deep reviewer** on the net PR diff
(`git diff <base>...HEAD` — three-dot = merge-base diff, review the final state, not each commit).

## Two distinct lenses (run in parallel, non-overlapping mandates)

Splitting the review by lens avoids redundant token spend and gives broader coverage than one
reviewer doing everything:

1. **Correctness / security** (a dedicated code-review subagent) — line-level bugs, logic errors,
   races, security vulnerabilities, regressions. Confidence-filtered: high-priority real issues only.
   Point it at the high-blast-radius areas explicitly.
2. **Architecture / convention / doc-accuracy** (a curator / architecture subagent) — dead or
   half-wired code (especially around anything *descoped* to a follow-up), convention adherence,
   rename-before-drop / hardcoded-id risk, and whether reference docs match the shipped code (decisive
   when the same PR rewrote docs).

Each returns a structured findings report (file:line + why-it's-real + suggested fix) and is asked to
state explicitly when a high-risk area is *clean* — silence isn't confirmation; an explicit
"checked X, clean" is. Then triage the findings through the normal loop tiers (auto-fix / approve /
escalate) and fold the fixes into the PR before merge.

## Why this earns its cost (observed)

On one ~50-commit / ~8k-line surface-migration PR a fast bot cleared in one pass, the independent
two-lens review surfaced three real items the bot missed: a teardown handler that left one socket
callback attached (stale-callback race on the next re-mount), a fragment endpoint that leaked record
existence via a 403-vs-404 distinction (vs the leak-resistant single-query-404 a sibling endpoint
already used), and a never-wired skeleton function whose docstring described it as live
infrastructure. None were style nits; all three were worth fixing before merge. The lesson: the cost
of two subagent reviews is far smaller than the cost of shipping a real bug a shallow pass waved
through on a big diff.

## Relationship to the loop

This is a **hand-back-time escalation**, not a replacement for the engine loop. Run the normal
`/review-loop` first; when it hands back CLEAN on a PR that meets the large-PR threshold, do the
independent pass before declaring the PR merge-ready. The independent findings re-enter the loop as a
fresh fix cycle (commit → push → re-trigger engines on the new SHA), so the engines still get a final
look at the fixes.
