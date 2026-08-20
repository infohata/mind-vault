# Cross-box agent handoff — the target repo's issues are the channel

An agent on the dev laptop diagnosed an infrastructure incident (a fail2ban jail on an estate
box banning normal users) whose fix belonged to agents running on a different machine. No shared
filesystem, no live agent-to-agent link between the boxes. The handoff that worked: **open a
GitHub issue on the repo that owns the problem** (the estate's infra-docs repo), then post each
subsequent finding as a **comment** — culprit identified, a corrected analysis, the final
confirmation. The human's entire relay burden was one line typed into the other box's agent
terminal: *"handle issue #N — the brief is in the body."*

## Why issues beat the alternatives

| Channel | Why it loses |
| --- | --- |
| Relaying through the human's chat | Human becomes a copy-paste proxy; evidence arrives paraphrased and un-ordered; nothing survives the session |
| A docs PR with the brief | A PR wants review-and-merge semantics; a task wants assign-and-resolve; parking a task as an unmergeable PR confuses both |
| Notes on a shared box / scratch files | Machine-scoped — the exact thing that fails when agents live on different boxes |
| Direct agent messaging | Only works when both sessions are live and linked; an issue is consumable hours later by whichever session picks it up |

Issues are repo-scoped (context travels with the code that owns the fix), both ends are already
authenticated (`gh` works everywhere the agents work), threads are durable across machines and
sessions, and the human can audit the whole exchange in the same place the work lands.

## The shape

1. **Issue body = the brief**: incident/timeline, blast radius, evidence gathered so far, and a
   numbered list of concrete asks. Written so a fresh agent needs *nothing else* to start.
2. **Comments = the evidence chain, append-only.** Post corrections as new comments, never edit
   the earlier analysis away — a consuming agent (or human) must be able to replay how the
   understanding evolved. A worked thread runs: hypothesis → hypothesis withdrawn with the
   corrected mechanism → final confirmation from logs. Each step names its evidence command so
   the other side can re-run it.
3. **Cross-reference from the work records**: the originating project's record cites the issue
   (`the infra follow-up: <repo>#N`); the issue cites the originating IDEA/PR. Either end of the
   thread finds the other.
4. **The human's part is one line**: point an agent at the issue. If the target repo's agents
   sweep open issues on their own, even that line is optional.

## When NOT to use it

- Both agents on the same box → local channels (files, sessions) are simpler.
- The "task" is really a decision only the human can make → that's a question, not a handoff.
- Secrets in the evidence → issues are as visible as the repo; scrub credentials/tokens the same
  way you'd scrub a commit.
