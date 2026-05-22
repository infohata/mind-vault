# Compound routing decision tree

The 6-destination taxonomy and the heuristics for picking the right one. Load on demand at `/compound` step 2.

## The six destinations

| # | Destination | When | Example |
| --- | --- | --- | --- |
| 1 | Project-local solution | Specific to one project, won't recur elsewhere | A webhook HMAC mismatch due to a flat-payload edge case |
| 2 | Mind-vault skill update | Cross-project pattern or technique | "Always wrap async tenant context: `with tenant_context(tenant):`" → extends `skills/django/` |
| 3 | Mind-vault rule update | Hard guardrail — "never do X", "always do Y" | "Never hand-edit `.po` files" (already in `RULE_i18n-workflow`) |
| 4 | Mind-vault agent pass | Reviewer heuristic that a persona should catch | "Dictionary key collisions silently swallow overrides" → curator PASS 3 |
| 5 | Mind-vault command/tool | Repeatable action worth a slash command or script | Regex sweep for `format_html(_(...))` migration drift |
| 6 | Auto-memory | User-behavioural preference or cross-conversation context | "User prefers bundled PR over split for refactors in X area" |

## Narrative-probe question playbook

Ask these one at a time, in order. Stop when the destination is clear.

### Q1. Scope

> "Is this specific to this project, or does it apply to any Django / Celery / Docker Compose project we'd work on?"

- Project-only → Destination 1 (solution doc).
- Cross-project → continue to Q2.
- User not sure → assume project-only. If it recurs elsewhere later, a second `/compound` invocation promotes it then. Don't over-promote on first contact.

### Q2. Shape

> "Shape of the learning — is it a fix recipe, a guardrail to always enforce, a reviewer heuristic, a tooling need, or a behavioural preference?"

- Fix recipe or pattern → Destination 2 (skill).
- Guardrail ("never X", "always Y") → Destination 3 (rule).
- Reviewer heuristic ("the review should catch Z") → Destination 4 (agent pass).
- Tooling need ("we kept running the same query") → Destination 5 (command/tool).
- Behavioural preference ("user prefers X") → Destination 6 (memory).

### Q3. Disambiguation (when Q2 is fuzzy)

Only ask Q3 if Q2's answer sits between two destinations.

- Skill vs. rule: "Does the learning describe a *technique to apply* (skill) or a *behaviour to prevent* (rule)?"
- Skill vs. agent pass: "Is this a pattern the implementer needs (skill), or something the reviewer needs to catch (agent)?"
- Rule vs. agent pass: "Is this a hard 'never' that applies everywhere (rule), or a pattern a reviewer should flag but a skilled author might legitimately violate (agent)?"

## Disambiguation heuristics

### Skill vs. agent pass

- **Skill** = the implementer reads it while deciding how to build. Example: "To add a new DRF viewset, inherit from `BaseModelViewSet` and register the filter class." → `skills/django/`.
- **Agent pass** = the reviewer reads it while catching mistakes. Example: "If the PR introduces a ViewSet, confirm `filterset_fields` doesn't include removed model fields." → `AGENT_curator` pass 4.

A learning can belong in both (skill tells how, agent verifies). Emit both when the distinction is that clean — but only if the reviewer dimension is load-bearing, not decorative.

### Rule vs. skill

- **Rule** = absolute, agent-enforced hard stop. The agent refuses to proceed when the rule would be violated. Example: `RULE_git-safety` — "never commit to main".
- **Skill** = best-practice convention that the agent applies by default but a thoughtful human can override. Example: `skills/django/` — "use `select_related` on list views".

If the learning's violations require a conversation ("why did you do it this way?"), it's a skill. If violations require an apology, it's a rule.

### Command vs. script

- **Slash command** (`/compound`, `/bugbot-loop`) = user-facing, interactive, part of the workflow.
- **Script** (`tools/bugbot_retrigger.sh`) = headless utility, usually called from another command or a human-run shell.

### Body vs. reference vs. asset (within mind-vault)

Once destination 2 (skill) or 3 (rule) is selected, the second-pass placement question is **load-on-demand vs always-on**. Default to load-on-demand (`references/` for prose, `assets/` for non-prose payloads). The full decision algorithm lives in `compound/SKILL.md` § *Mind-vault placement*; this is the disambiguation summary:

- **`skills/<owner>/references/<TOPIC>.md`** — prose patterns, gotchas, recipes, mechanics. Default for any skill addition that isn't part of the skill's first-paragraph trigger surface.
- **`skills/<owner>/assets/<filename>`** — templates, scaffolds, shell scripts, sed-substitution recipes. Anything multi-line + non-prose.
- **SKILL.md body** — only when the addition is the canonical "what is this skill for" framing (a brand-new skill's first concept), or a 2-paragraph stub-with-pointer that names firing conditions and links to a reference for mechanics. Stubs are body-light; the heavy content always lands in references/.
- **`rules/RULE_<name>.md`** (top-level) — only when the guardrail fires across multiple skills / stages / stack types. The PR #106 split is the criterion: always-on tier vs domain-bound. Domain-bound guardrails go to skill references, even when they're hard "always do X" rules.

The reflex is: when in doubt, **prefer the load-on-demand surface**. The cost of an unused reference file is one extra file in the tree; the cost of every-session-paid bloat is paid forever, on every invocation, by every consumer. PR #106 + IDEA-002 paid −1,731L combined to remove that bloat — don't re-introduce it on first-promotion.

## Anti-patterns in routing

- **Over-promoting.** If a pattern has appeared once, it's project-local until proven otherwise. First-occurrence promotions pollute mind-vault with noise.
- **Under-promoting.** If the same finding has been captured in three different `docs/solutions/` files, that's a missed promotion — grep for duplicates before writing a fourth.
- **Misclassifying behavioural preferences as skills.** "User prefers terse summaries" is memory, not a skill. Skills are about *what to do*; memory is about *how this user wants it done*.
- **Creating a new rule when an existing one can be extended.** Prefer appending to `RULE_i18n-workflow` over creating `RULE_po-files-readonly`. One rule per concern.
- **Inlining mechanics into SKILL.md body.** A skill's body is paid on every `Skill <name>` invocation. New mechanics belong in `references/<TOPIC>.md` — the body gets a stub-with-pointer at most. Re-introducing body bloat is the failure mode IDEA-002 spent three PRs cleaning up; don't reverse that work on a single compound run.
- **Adding a new top-level rule when the guardrail is domain-specific.** Rules in `rules/` load every session. Domain-bound guardrails (Django i18n, Playwright baselines, parallel worktrees) belong in `skills/<owner>/references/` and load only when the owning skill activates. PR #106 already drew this line — respect it.

## De-duplication before writing

Before writing to any mind-vault destination, grep for prior matches:

```bash
rg -l "<keyword-from-learning>" mind-vault/skills mind-vault/rules mind-vault/agents
```

If a match exists:

- Prefer extending the existing file over creating a new one.
- If the existing content is stale (the learning supersedes it), update in place and note the provenance.
- Surface the duplicate to the user — "found `skills/django/references/MULTI_TENANT.md` mentions this; extend it or write new?" Default extend.

## When the probe produces "all of the above"

If a learning genuinely applies to multiple destinations (e.g. a new pattern + a reviewer catch + a user-facing command), emit multiple destinations in order:

1. **Skill first** (the "how").
2. **Agent pass second** (the "catch").
3. **Command third** (the "shortcut").

One compound invocation, multiple destination commits — they share the same provenance and end up on the same mind-vault PR.
