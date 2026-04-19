---
description: Fifth stage of the sprint workflow — route a just-learned lesson to the right destination (project-local solution, mind-vault skill/rule/agent/command, or auto-memory); the lever that makes each sprint easier than the last
agent: general
---

Invoke the `compound` skill to route a post-incident learning to the right home. The novel piece of the sprint workflow and its entire compound-effect payoff.

Behaviour:

1. Collect the raw learning: explicit prompt content, a `/bugbot-loop` findings file, a PR comment thread, or interactive prompt.
2. Run the hybrid Shape-C router: narrative-probe questions first (scope → shape → disambiguation), then propose one destination and confirm; fall back to explicit 6-way taxonomy quiz when ambiguous.
3. Route to one of six destinations:
   - Project-local solution doc at `<project>/docs/solutions/<topic>.md`
   - Mind-vault skill update (`mind-vault/skills/<name>/SKILL.md` or `references/`)
   - Mind-vault rule update (`mind-vault/rules/RULE_<name>.md`)
   - Mind-vault agent pass extension (`mind-vault/agents/AGENT_<persona>.md`)
   - Mind-vault command or tool (`mind-vault/commands/<verb>.md` or `mind-vault/tools/<script>.sh`)
   - Auto-memory entry (`~/.claude/.../memory/{feedback,project,user,reference}_<topic>.md` + `MEMORY.md` index)
4. For mind-vault destinations: apply the branch policy — create a fresh `compound/YYYY-MM-DD-<slug>` branch if on `main`; extend the current feature branch otherwise (no branch spam). Commit, push, ensure an open PR on the branch. Never merges; human reviews and merges.
5. Report branch, commit SHA, PR URL back to the user.

When invoked after `/bugbot-loop`, reads the loop's findings file and walks each cleared finding as a compound candidate (ingest mode).

See `skills/compound/SKILL.md` for full pattern; `skills/compound/references/routing-decision-tree.md` for the taxonomy; `skills/compound/references/mind-vault-promotion.md` for the branch-and-PR procedure.
