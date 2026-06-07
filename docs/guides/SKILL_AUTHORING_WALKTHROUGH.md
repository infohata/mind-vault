# Skill authoring — process walkthrough

The mechanical spec for a skill lives in [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md). The operational rules live in [`skills/skill-writer/SKILL.md`](../../skills/skill-writer/SKILL.md). This doc covers the *process* — how a recurring pattern in your work becomes a skill, when it shouldn't, and how to keep the skill body lean.

## When does a pattern earn its own skill?

Most patterns don't. The decision tree:

```text
Recurring pattern noticed
  └─ Always true (every project, every session)?
       ├─ YES → Author as RULE (rules/RULE_<slug>.md, auto-loaded)
       └─ NO  → Domain-specific (Django, frontend, Laravel, etc.)?
                 ├─ YES → Author as SKILL with domain-matching description
                 └─ NO  → Workflow stage that user/agent triggers?
                           ├─ YES → Author as COMMAND (commands/<name>.md)
                           └─ NO  → Persona/role with multi-pass workflow?
                                     ├─ YES → Author as AGENT profile (agents/AGENT_<role>.md)
                                     └─ NO  → Probably doesn't belong in mind-vault — keep as project doc
```

**Tie-breakers when it could be skill OR rule:**

- Token cost. Rules pay forever; skills pay per-invocation. If the pattern is invoked in <50% of sessions, skill.
- Probabilistic trigger. Can you write a one-sentence description an LLM can match against the task? If yes → skill. If you need conditional logic ("apply only when X AND not Y") → rule.

**Tie-breakers when it could be skill OR command:**

- Does the human invoke it explicitly? Command.
- Does the agent decide when it applies? Skill.
- Hybrid (`/wrap` is both — user-triggered command that loads as a skill body): author as command, give it a skill-quality description.

## Anatomy of a good skill

```
skills/<name>/
├── SKILL.md              # ≤500 lines, frontmatter + body
├── references/           # load-on-demand deep content
│   ├── PATTERN_X.md
│   └── PATTERN_Y.md
└── assets/               # templates, snippets, fixtures (rare)
```

**SKILL.md frontmatter** — mandatory `name` (must match directory) + `description` (the probabilistic trigger). Optional: `version`, `maintainer`, `last_updated`.

**SKILL.md body structure** — five sections, in this order:

1. **Overview** — one paragraph: what this skill does + the principle behind it.
2. **When to use** — bullet list of trigger scenarios. Mirror the wording an LLM might encounter in a task description.
3. **The pattern** — the actual content. Concrete steps, code, tables, examples. This is what gets loaded into the agent's context when the skill fires.
4. **When NOT to use** — anti-triggers. Equally important — keeps the skill from firing on edge cases that bite.
5. **References** — bullets pointing at `references/*.md` for content too detailed for the main body.

## The 500-line budget — and why progressive disclosure matters

Every invocation of a skill loads its SKILL.md body into the agent's context. A 1000-line skill body costs 4× more tokens per fire than a 250-line one. Across a sprint with dozens of skill fires, the difference is real.

The discipline:

- **SKILL.md body**: the patterns that apply ~80% of the time. Concrete, prescriptive.
- **`references/<pattern>.md`**: the patterns that apply <20% of the time. Linked from SKILL.md ("for the multi-tenant case, see `references/MULTI_TENANT_PATTERNS.md`"). The agent reads it only when relevant.
- **`assets/`**: copy-paste templates the skill body links to — `assets/Makefile.template`, `assets/docker-compose.override.yml.template`.

IDEA-002 (May 2026) debloated the three biggest mind-vault skills (`wrap`, `django-frontend`, `django`) by extracting 748 lines into `references/` — meaningful token savings at sprint-auto-scale invocation rates. The pattern stuck: new skills are written reference-first.

### The line count is a smell, not the rule — three refinements

The 500-line budget is a *trigger to look*, not a target to hit. Three things sharpen it:

**1. Progressive disclosure pays off ONLY for minority-read content.** Extraction saves tokens when the reference is read in a *minority* of fires: extract content read ~20% of the time → you save its tokens the other 80%. But extracting content the skill needs on *every* fire is a **net negative** — the agent must `Read` it back each time anyway, so you now pay (a) the trimmed body, (b) the full reference, *plus* (c) the Read tool-call overhead (the result re-includes the whole file with line-number gutters), *plus* a round-trip — and you've added a failure mode: if the agent doesn't read the extracted ref, the skill **loses function**. Split conditional content; keep always-needed orchestration inline. "Must not lose function" is the binding constraint, and for core orchestration it's incompatible with extraction.

**2. Measure the *real* number — both axes, with a working tool.** Two different size axes have very different economics:

- **`description` frontmatter** loads *every session* (it's the probabilistic-trigger surface the agent scans to decide whether to fire). This is the expensive axis. Keep it tight on CC; OpenCode hard-caps it at 1024 chars (see [`AGENT_PORTABILITY.md`](AGENT_PORTABILITY.md)).
- **SKILL.md body** loads *only when the skill fires*. A long body on a rarely-fired skill is cheap; the cost is intermittent.

Measure before you cut — and trust the measurement only if the tool is correct. `tools/validate-skills.sh` once over-reported descriptions by an order of magnitude (`work` "12492 chars" vs the real **308**) because its parser read *past the closing `---`* into the body. A phantom number nearly triggered a pointless debloat. Run `validate-skills.sh <name>` (CC checks) or `--opencode` (fork audit), and sanity-check any surprising count against the actual frontmatter.

**3. Exemplar — `skills/plan`.** At 181 lines it sits *under* budget while still being a large workflow skill, because it extracted exactly the conditional 20% and kept the always-needed 80% inline:

- **Extracted (minority-read):** `references/thin-input-bootstrap.md` (fires only on thin input), `references/architect-handoff.md` (only when the reviewer pass runs), `references/batching-for-sprint-auto.md` (only in batch mode).
- **Kept inline (every fire):** resume/scope, research, draft, architect pass, the IDEA `git mv`, plan emit.

That's the template. `skills/work` (242 lines) is similar — both are healthy. Neither is a debloat target despite *feeling* big; the feeling came from the phantom description count, not the real body. Resist decomposing a skill on a raw line count or a single scary metric: confirm the content is genuinely minority-read first, or you trade tokens you weren't spending for a function-loss risk you didn't have.

## What a skill should NOT have

- **Project-specific paths or commands.** A skill that says `cd ~/projects/project-x && make test` is broken for every other project. Use placeholders + describe the convention (`cd <project-root> && make test` + "this skill assumes a Makefile with a `test` target").
- **Long verbatim code blocks copied from another file.** Link to the file instead. Skills rot when the source moves; links update naturally on rename.
- **Decision matrices that should be rules.** "Always wrap in a transaction" — that's a rule. "When migrating a foreign key, here's a 5-commit sequence" — that's a skill.
- **History / changelog inline.** Verbose "Last Updated 2026-05-10 — fixed bug found by Bugbot PR #87" trailers cost tokens on every fire. Route to [CHANGELOG.md](../../CHANGELOG.md) instead — every line in a SKILL.md body is paid for on every activation, and incident narrative has nothing to do with how the skill fires.
- **Multi-paragraph rationale.** One sentence per *why*. Reader-level skill = junior dev with the spec open in the other window, not someone needing a tutorial.
- **Defensive language ("always carefully", "thoughtfully consider", "be aware that").** Junk tokens. Either prescribe the action or don't.

## The lesson → skill route via `/compound`

The most common origin story for a mind-vault skill: a sprint review surfaced a recurring fix-up that should have been automatic. `/compound` is the routing tool.

```text
/compound

> What did you learn this sprint that should outlive it?

(paste the lesson — what went wrong, what you wished was true, what fix you want next time)

> [hybrid narrative-probe + taxonomy-quiz router decides among 6 destinations]
```

The six destinations:

1. **Project-local solution doc** — the lesson is unique to one project.
2. **mind-vault skill** (new or existing) — domain-specific, agent-decides-when.
3. **mind-vault rule** — always true, every project, auto-load.
4. **mind-vault agent profile** — persona-shaped (a new reviewer pass, a new orchestrator stance).
5. **mind-vault command** — user-triggered workflow stage.
6. **auto-memory** — context for future sessions, not a reusable artefact.

`/compound` doesn't author the artefact itself — it tells you *where* the lesson belongs and (for skills/rules) drops a skeleton you fill in. Use `/skill-writer` to flesh out the body.

## The `/skill-writer` skill

A skill that authors skills. It enforces the SKILL_SPECIFICATION.md schema, validates frontmatter, lints body length, checks for the five required body sections, suggests `references/` extractions when body grows >500 lines.

```text
/skill-writer create skills/my-new-skill
/skill-writer audit skills/django/      # checks existing skill against spec
```

For a new skill from scratch: `/compound` first (to confirm it should be a skill), then `/skill-writer create` (to scaffold), then edit by hand.

## Anti-patterns surfaced in mind-vault's own history

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Skill body keeps growing | SKILL.md hits 800+ lines, slow to load | Extract domain-specific sections to `references/`; SKILL.md becomes a dispatcher |
| Description too generic | Skill fires on unrelated tasks | Tighten `description` field with specific triggers; add a "When NOT to use" section |
| Description too specific | Skill never fires when it should | Broaden the trigger phrases; mirror language the agent encounters |
| Duplicate skills with overlap | Two skills both fire on Django ORM work | Merge into one OR clarify which handles which subset (e.g., `django` = backend, `django-frontend` = templates) |
| Rule used where skill would fit | Permanent context budget for a pattern that's rarely needed | Move to `skills/`, write a good description |
| Hardcoded project paths | Skill broken on every other project | Replace with placeholders + assumption block |

## The author's checklist before merging a new skill

- [ ] Frontmatter has mandatory `name` + `description`; name matches directory.
- [ ] Description reads like a one-sentence trigger an LLM can match.
- [ ] Five-section body structure present (Overview → When → Pattern → When NOT → References).
- [ ] SKILL.md body ≤500 lines; >500 → extract to `references/`.
- [ ] No project-specific paths/commands; placeholders + convention notes instead.
- [ ] No history/changelog trailer (route to CHANGELOG.md).
- [ ] Anti-patterns and edge cases captured in "When NOT to use".
- [ ] If the skill replaces something existing, the old artefact is removed (not left orphaned).

## See also

- [SKILL_SPECIFICATION.md](SKILL_SPECIFICATION.md) — the mechanical spec.
- [`skills/skill-writer/SKILL.md`](../../skills/skill-writer/SKILL.md) — operational rules + the create/audit workflow.
- [`skills/compound/SKILL.md`](../../skills/compound/SKILL.md) — the lesson-router.
- [`rules/RULE_self-sweep-before-push.md`](../../rules/RULE_self-sweep-before-push.md) — the inspiration for cheap-pre-commit-checks-rather-than-expensive-CI-round-trips, applies to skill quality too.
