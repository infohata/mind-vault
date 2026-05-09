---
name: compound
description: Route a just-learned lesson to the right destination — project-local solution doc, mind-vault skill/rule/agent/command, or auto-memory. Uses a hybrid narrative-probe + taxonomy-quiz router. Also consumes bugbot-loop output as input. Final stage of the mind-vault sprint workflow; the lever that makes each sprint easier than the last.
---

# compound

Fifth and final stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). The novel piece of the workflow and its entire point: every solved problem becomes a candidate for promotion into mind-vault, compounding the knowledge store so the next project (or the next sprint on the same project) starts with a higher floor.

CE's compound writes project-local only. Mind-vault's compound routes to six destinations because mind-vault *is* the cross-project knowledge store — the routing surface is the whole value.

This skill never commits to `main` and never merges a PR. It stages, commits to feature branches, pushes, and maintains open PRs per `RULE_git-safety`.

## When to use

**TRIGGER when:**

- user says "compound this", "let's capture what we learned", "document this fix", "promote this to mind-vault", "write this up", "save this learning"
- a `/bugbot-loop` just cleared findings and there's a non-trivial lesson worth preserving — the bugbot output file is a first-class input source (see [`references/bugbot-finding-ingest.md`](references/bugbot-finding-ingest.md))
- a bug was just fixed and the root cause is non-obvious / recurring / cross-project
- a pattern that kept coming up across multiple tasks finally got named

**SKIP when:**

- the fix is trivial and the "lesson" is just "I wrote the code" — nothing to compound
- you're mid-implementation (this is a post-incident skill, not a learning ledger)
- the user wants to capture a new improvement idea — that's `/idea`, not `/compound`

## Pattern

### 1. Collect the raw learning

Accept input in this order of preference:

1. **Explicit prompt content** in the skill invocation (`/compound the HMAC flat-payload trap`).
2. **Bugbot-loop output file** at `<project>/.bugbot-loop/<run-id>/findings.md` (or wherever the loop writes its artifact) when recent. See [`references/bugbot-finding-ingest.md`](references/bugbot-finding-ingest.md) for parsing rules — each cleared finding becomes a candidate compound entry.
3. **PR comment thread** when the user points at one (`/compound pr:123#comment-456`).
4. **Interactive prompt** when nothing is supplied: "What did you learn? Give me the one-sentence essence first, then we'll expand."

Capture the raw learning into working memory. Do not write anything yet.

### 2. Hybrid router — Shape C

Per the sprint-workflow plan's Q6 decision. Two modes, probed in order:

**2a. Narrative probe.** Ask up to three questions, one at a time, using the platform's blocking question tool when available:

- "Is this specific to this project, or likely to recur in other projects?"
- "Shape of the learning — fix recipe, guardrail rule, reviewer heuristic, tooling need, or behavioural preference?"
- "If cross-project: is it a *pattern to add* somewhere, or a *guardrail to enforce*?"

After the narrative probe, propose **one destination** with a one-sentence rationale and ask the user to confirm. If they confirm, skip 2b.

**2b. Taxonomy quiz fallback.** If the narrative probe produced ambiguous signal, or the user rejected the proposed destination, present the full 6-way taxonomy from [`references/routing-decision-tree.md`](references/routing-decision-tree.md) as a numbered list and let the user pick.

### 3. Write to the chosen destination

Six destinations, each with its own emit procedure:

| Destination | Target path | Template |
| --- | --- | --- |
| Project-local solution | `<project>/docs/solutions/<topic>.md` | [`assets/solution-template.md`](assets/solution-template.md) |
| Mind-vault skill update | `mind-vault/skills/<name>/SKILL.md` or `.../references/<topic>.md` | merge into existing skill, or emit new scaffold from [`assets/skill-scaffold-template.md`](assets/skill-scaffold-template.md) |
| Mind-vault rule update | `mind-vault/rules/RULE_<name>.md` | append a new bullet / section to an existing rule, or draft a new rule file |
| Mind-vault agent pass | `mind-vault/agents/AGENT_<persona>.md` | append a new bullet to the relevant pass (curator PASS 3, architect PASS 1, etc.) |
| Mind-vault command/tool | `mind-vault/commands/<verb>.md` or `mind-vault/tools/<script>.sh` | emit new file; ask the user whether a slash command or a bash helper is the right shape |
| Auto-memory | `~/.claude/projects/<project-id>/memory/{feedback,project,user,reference}_<topic>.md` + `MEMORY.md` index line | use the canonical memory frontmatter from `CLAUDE.md`'s auto-memory section |

For project-local: write and stop. No branch management — this is the target project's own journal.

For mind-vault destinations: apply step 4 before emitting.

For auto-memory: write into the memory filesystem at `~/.claude/projects/<project-id>/memory/` and update `MEMORY.md`'s one-line index. Honour the type classification (feedback / project / user / reference) from the global `CLAUDE.md` auto-memory rules.

#### Auto-memory vs mind-vault — the THIS-MACHINE-ONLY test

Auto-memory lives in `~/.claude/projects/<project-id>/memory/` on the host machine. It does **not** sync across machines. A user who works from multiple environments — daily workstation + remote VPS for overnight sprint-auto runs + occasional laptop session — will see auto-memory written on machine A vanish from machine B's perspective.

**Routing rule**: when deciding between auto-memory and mind-vault, ask "would this learning still apply if the same person opened a session on a different machine?"

- **Yes (cross-machine value)** → mind-vault. Skill / rule / agent / command. The learning survives the host.
- **No (truly THIS-MACHINE-ONLY)** → auto-memory. Examples: a one-off shell quirk specific to this user's keyboard layout, a path that resolves correctly only because of the user's home-dir layout on this specific machine, a temporary state-file pointer for an in-flight investigation.

The default is mind-vault. Auto-memory is the exception, not the equal-weight alternative the table above might suggest. When the routing is genuinely ambiguous, prefer mind-vault — the cost of an unused mind-vault entry is one extra file in a knowledge store; the cost of a missed cross-machine learning is the user re-discovering the same lesson on every fresh environment.

This includes patterns that *feel* project-local but recur across the user's work: bugbot triage shortcuts, sprint-workflow refinements, debugging-loop conventions. Project-local *content* (a specific bug fix's recipe with project-specific function names) goes to project-local solution docs, not auto-memory; cross-project *patterns* go to mind-vault.

The user direction that surfaced this rule (teisutis 2026-05-05): "When deciding compound local memory vs. mind-vault, always remember that mind-vault survives the machine. I use you remotely as well (especially for overnight sprint-auto work) on VPS. If you think the compound is THIS LOCAL MACHINE ONLY, then it's local memory. All other cases — mind-vault."

### 4. Mind-vault promotion — branch policy

When the destination is inside `mind-vault/`, detect the repo's checkout path and apply the branch policy. Full rules in [`references/mind-vault-promotion.md`](references/mind-vault-promotion.md); short form here.

1. **Detect mind-vault path.** If the skill was invoked from inside a target project, compute the mind-vault repo path (default `~/projects/mind-vault`, user-overridable). If invoked from inside mind-vault itself, use the current directory.
2. **Check branch.** `git -C <mind-vault-path> branch --show-current`.
3. **Branch policy (Q3 resolution):**
   - If the current branch is `main`: `git checkout -b compound/YYYY-MM-DD-<slug> origin/main`. Surface to the user which branch was created.
   - If the current branch is any feature branch (e.g. `ce-inspired-evolution`): stay on it. No new branch. No branch spam.
   - Never modify `production` / `deployment` branches; refuse if on one.
4. **Emit the file(s).** Write the target files per step 3.
5. **Customer-data scrub gate — MANDATORY.** Mind-vault is a cross-project knowledge store and must contain **zero project/customer-identifying data**: no real tenant slugs, customer names, account / conversation / record ids, customer-supplied filenames, customer domain hostnames, internal URLs that could identify a deployment, or any other data that wouldn't be safe in a public repo (mind-vault may be private today and public tomorrow). Run a scrub pass on the staged diff before commit:

   ```bash
   cd <mind-vault-path>
   git diff --no-color --staged | grep -iE \
       '<tenant-slug-pattern>|conversation [0-9]+|record [0-9]+|account [0-9]+|/Users/[^/]+/Downloads/|customer.specific.filename|<deployment-domain>'
   # Project-specific: also grep for customer brand names, product nicknames,
   # internal hostnames, anything in `<project>/.gitignore` that hints at
   # secrets-adjacent paths.
   ```

   Scrub policy:
   - **Tenant identifiers** → drop entirely or replace with generic "production tenant".
   - **Customer record ids / conversation ids / message ids** → drop.
   - **Customer-supplied filenames** → drop or replace with `<filename>`.
   - **Local filesystem paths** (`/Users/<name>/...`, `/home/<name>/...`) → drop.
   - **Customer domain hostnames** → drop or replace with `<tenant-host>`.
   - **PR / IDEA / commit references** → KEEP (these are project provenance, expected in mind-vault per existing convention; matches the "Last Updated" footer style in other mind-vault files).
   - **Module / class / function names** (e.g. `AttachmentSerializer`, `_serialize_batch`, `teisutis_ai/`) → KEEP (these are public-API names that future readers need; they're already grep-able from the cited PR).

   The "would this be safe in a public repo today?" test is the gate. If the answer is "no", scrub before commit.

6. **Commit.** One commit per invocation, using the standard commit-message format (type(scope): description).
7. **Push.** `git push --set-upstream origin <branch>`.
8. **Ensure open PR.** `gh pr view <branch>` to check existence. If no PR exists, `gh pr create --title "..." --body "..."`. If one exists, append a short note to the PR body describing what this `/compound` invocation added — keeps the PR description current.
9. **Report back.** Print the branch, commit SHA, and PR URL. Never suggest the human merge — that's theirs to do.

### 5. Cross-link and index

- Every mind-vault promotion also references the project-local source that triggered it. If the learning started as a bugbot finding on a teisutis PR, the new skill/rule/agent entry cites the PR in its Last Updated / provenance section.
- Project-local solution docs reference any mind-vault assets they generalised from, so future `/compound` invocations can detect duplicates.
- Auto-memory entries include their one-line `MEMORY.md` pointer — that's the index.

### 6. Verification hint (deferred to Phase 2)

Phase 1 does not auto-verify that the new skill/rule/agent is picked up in the next invocation — deferred per the sprint-workflow plan's Q7. Instead, after promotion, print a manual hint:

```text
To verify the new skill fires as expected, start a fresh agent session and
ask for the pattern you just captured. If the skill's description doesn't
match the new trigger, revise the frontmatter and try again.
```

## Bugbot-finding input mode

When the input is a bugbot-loop output file, iterate each cleared finding:

1. Read the finding: category, severity, file, one-line description, fix applied.
2. Decide if it's compound-worthy: if the finding appeared the first time in this project, probably not (noise). If the same category has appeared before — grep solutions and mind-vault for prior matches — promote.
3. Route each compound-worthy finding through the Shape-C router in step 2.
4. Group related findings into a single solution doc or skill-update when they share a root cause.

See [`references/bugbot-finding-ingest.md`](references/bugbot-finding-ingest.md) for the parsing rules and the de-duplication heuristics.

## Interaction rules

- **No project / customer data leaks into mind-vault — ever.** Mind-vault is a cross-project knowledge store and must contain only generic, reusable patterns. Run the customer-data scrub gate (step 5 above) on every mind-vault commit, regardless of the destination (skill / rule / agent / command / tool). The gate is mandatory, not advisory; a leak in a private repo today is a leak in a public repo tomorrow. Identifiers and IDs are out; PR / IDEA / commit references and module names are in.
- **Shape-C narrative probe asks three questions max.** If the user's still unsure after three, fall back to the taxonomy quiz rather than asking a fourth.
- **Never silently promote to mind-vault.** Every mind-vault-destination write is explicit and confirmed.
- **Never auto-merge the mind-vault PR.** `RULE_git-safety` is not negotiable.
- **Report what landed, where, and on which branch.** End-of-invocation summary is load-bearing — the user needs to see the change surface to review it.

## When NOT to use these patterns

- **Mid-work documentation.** `/compound` is a post-incident skill. If you're still implementing, finish (or abort) and come back.
- **Capturing a new improvement idea.** Route to `/idea`.
- **Updating the plan because execution revealed something.** Route to `/plan` with the revision.
- **Debating whether something is worth compounding.** If it's close, compound to project-local (`docs/solutions/`). Promotion to mind-vault is the higher bar — reserve for patterns that actually recur.
- **Bulk-importing historical learnings.** That's a brownfield takeover, not routine compound. Use `/ingest-backlog` (for IDEAs) or hand-write solution docs outside this skill.

## References

- [references/routing-decision-tree.md](references/routing-decision-tree.md) — the 6-destination taxonomy, narrative-probe questions, disambiguation heuristics
- [references/mind-vault-promotion.md](references/mind-vault-promotion.md) — full branch policy, PR maintenance, commit-message conventions for mind-vault destinations
- [references/bugbot-finding-ingest.md](references/bugbot-finding-ingest.md) — parsing rules for bugbot-loop output, de-duplication against prior findings
- [assets/solution-template.md](assets/solution-template.md) — project-local solution doc structure
- [assets/skill-scaffold-template.md](assets/skill-scaffold-template.md) — minimal new-skill scaffold to emit when promoting a cross-project pattern
- [docs/SPRINT_WORKFLOW.md](../../docs/SPRINT_WORKFLOW.md) — full sprint-workflow explainer with the compound-routing table
- [skills/skill-writer/SKILL.md](../skill-writer/SKILL.md) — meta-standard consulted when emitting a new skill
- [rules/RULE_git-safety.md](../../rules/RULE_git-safety.md) — branching and commit contract honoured during mind-vault promotion
- [skills/idea/references/IDEAS_LOCATION_STATUS.md](../idea/references/IDEAS_LOCATION_STATUS.md) — location-by-status routing; `/compound` may trigger the `idea`→archive move when post-incident routing classifies an IDEA as superseded or rejected before any execution started
- [commands/bugbot-loop.md](../../commands/bugbot-loop.md) — the preceding review stage whose output this skill consumes

---

**Last Updated**: 2026-04-30
