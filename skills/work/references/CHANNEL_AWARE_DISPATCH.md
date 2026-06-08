# Channel-aware executed dispatch

When a mind-vault skill **executes a sibling** — another skill, a slash command, or a persona — it passes a *name* to a tool's lookup. mind-vault ships on two install channels (IDEA-017), and that name resolves differently on each:

- **Symlink channel** — bare names: `Skill(skill="plan")`, `/review-loop`, `Agent(subagent_type="architect")`.
- **Plugin channel** — the marketplace plugin namespaces everything under `mv:`, so bare names **do not resolve** (verified: IDEA-020 resolution-audit log).

A self-invoking dispatch is a **literal lookup, not a description-invoke** — so it does NOT fire by description and the wrong prefix fails, usually **silently** (a ScheduleWakeup wakes into a non-existent command; a stage no-ops; a persona dispatch errors or degrades to generic-Claude). This is the scoped carve-out from IDEA-017 Q3's "don't rewrite bodies channel-aware": prose stays bare, **executed dispatch must mirror the active channel.**

## The three mechanisms (all must be covered)

| Mechanism | Symlink form | Plugin form | Notes |
| --- | --- | --- | --- |
| `Skill` tool | `Skill(skill="plan")` | `Skill(skill="mv:plan")` | skill name |
| Literal slash (ScheduleWakeup `prompt`, typed) | `/review-loop` | `/mv:review-loop` | command token |
| `Agent` tool `subagent_type` | `architect` | **`mv:architect`** | persona name. (Personas were originally named `mv-architect` to dodge registry collisions; IDEA-020 **dropped that `mv-` prefix** — the plugin's `mv:` namespace already disambiguates, and `mv:mv-architect` was redundant/verbose. So the bare name is now `architect`, the plugin form the clean `mv:architect`.) |

## Detection — mirror the invocation form, persist it

`${CLAUDE_PLUGIN_ROOT}` is **not exposed in the agent's shell** (verified — an env probe won't work). The reliable signal is **how the skill was invoked**: `/sprint-auto` → bare channel; `/mv:sprint-auto` → `mv:` channel. Derive the prefix from that, and **persist it wherever it must survive a boundary**:

- **`ScheduleWakeup` / wake-loops** → the scratch file (review-loop's `reentry_command`). Survives compaction.
- **Long unattended runs across worktrees/subshells** → the batch state file (sprint-auto's `channel_prefix`, written at setup time — same rail as `SPRINT_AUTO_PLAYWRIGHT_AVAILABLE`, because env vars don't survive subshells).

The persisted value is the **prefix** (`""` symlink, `mv:` plugin) or the resolved token directly — either is fine as long as both channels keep working.

## The executed-vs-prose test (and the dual-mode exception)

For every reference to a sibling command/skill/persona, ask: **does the skill *itself* programmatically pass this token to a tool's lookup (`Skill` / slash / `subagent_type`)?**

- **Yes → executed.** Make it channel-aware (prefix per the table).
- **No → prose.** Leave it bare. Human-facing instructions ("run `/wrap NNN` first"), refuse-messages, doc examples, and description-invokes are all channel-agnostic — the human types the prefix their host needs; description triggers don't care about namespacing. (Examples that **stay bare**: `land/SKILL.md` "run `/wrap NNN`", `wrap/SKILL.md` "run `/land NNN`", `skill-writer` `commands/X.md` examples.)
- **Dual-mode → prefix the token, keep the path fallback.** A dispatch that can run *either* by `subagent_type` *or* by inline-invoke from a filesystem path (`plan/references/architect-handoff.md` — `subagent_type: architect` **or** read `agents/AGENT_architect.md`) has a built-in channel-agnostic backstop: the **filesystem path resolves through the repo, not the command registry**. Prefix the token form, but **never remove the inline-path fallback** — it's the fail-safe (mirrors review-loop's "loud degrade"). Don't let a sweep flatten it into a hard `mv:architect`.

## Worked instances

- **review-loop** (`review-loop/SKILL.md` Phase 4 + scratch `reentry_command`) — the literal-slash mechanism. The wake-loop re-invokes itself via `ScheduleWakeup(prompt="/<reentry_command> …")`, `reentry_command` mirrors the invocation prefix, persisted to scratch.
- **/work persona dispatch** (`persona-dispatch.md` + `work/SKILL.md` matrix) — the `subagent_type` mechanism (`architect` symlink → `mv:architect` plugin). Reached transitively by every sprint-auto IDEA (`sprint-auto/SKILL.md` — "/work dispatches personas"), so the unattended persona layer rides this one fix.
- **sprint-auto stage dispatch** (`sprint-auto/SKILL.md` S1/S2/S5/S6/S12) — `Skill`-tool + literal-slash; `channel_prefix` persisted to the batch state file at setup.
