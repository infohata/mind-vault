# IDEA-020 — Channel-aware inner command/skill references (plugin-route correctness)

**Status:** ✅ Complete (2026-06-08) · **PR:** [#194](https://github.com/infohata/mind-vault/pull/194) · **Release:** v5.1.3

## What shipped

The workflow skills' **executed** sibling dispatches (a skill programmatically spawning a sibling skill/command/persona) are now channel-aware — they resolve under the plugin's `mv:` namespace as well as the symlink channel. This closes the silent-failure class surfaced by going plugin-only: a bare-name dispatch doesn't resolve when only the `mv:`-namespaced plugin is installed (e.g. an unattended sprint-auto run dead-ending at 3am).

- **Shared convention** — `skills/work/references/CHANNEL_AWARE_DISPATCH.md`, covering all three executed-dispatch mechanisms: `Skill` tool (`mv:<skill>`), literal slash (`/mv:<command>`), `Agent` `subagent_type` (`mv:<persona>`). Detection mirrors the invocation form (`${CLAUDE_PLUGIN_ROOT}` is not in the agent shell); the prefix is persisted where it must survive a boundary (review-loop scratch `reentry_command`; sprint-auto batch-state `channel_prefix`). Includes the executed-vs-prose test and the dual-mode (token-OR-inline-path) fail-safe.
- **Persona dispatch** (`work/persona-dispatch.md` + `work/SKILL.md` matrix + `plan/architect-handoff.md`) — channel-aware + host-availability inline fallback. The highest blast radius: reached transitively by every sprint-auto IDEA via `/work`.
- **sprint-auto stage dispatch** — `channel_prefix` detected + persisted at S(-1).
- **Docs** — sprint-auto-VPS plugin-safety caveat (README + ONBOARDING).

## Notable deviations from the plan

- **Scope expansion (architect + live failure).** The first plan draft scoped only sprint-auto's stage dispatch (2 mechanisms × 1 skill). The architect review — and a live failure where *this IDEA's own `/plan` architect handoff* errored on bare `mv-architect` — widened it to 3 mechanisms × 4 skills, with `/work`'s persona dispatch the load-bearing surface.
- **Agent rename folded in (amendment).** Post-execution, the plugin persona form `mv:mv-architect` was judged over-verbose. All 8 agent profiles were renamed `name: mv-<persona>` → `name: <persona>`; the plugin form is now the clean `mv:<persona>`. The `mv-` prefix had existed to dodge shared-registry collisions, but the plugin's own `mv:` namespace already does that. Trade-off: symlink-channel agents are bare in the shared `~/.claude/agents/` (low collision risk; plugin-channel primary).

## Out of scope

Prose cross-references stay bare (IDEA-017 Q3) — `land`/`wrap`/`skill-writer` untouched. review-loop's `reentry_command` (PR #193) only gained a pointer at the shared convention.

## Related

- [Plan](./2026-06-08-channel-aware-inner-references-plan.md) · [Resolution-audit log](./2026-06-08-resolution-audit-log.md)
- Precedent: review-loop `reentry_command` (PR #193, v5.1.2)
- Amends/depends-on: [IDEA-017](../2026-06-idea-017-mind-vault-cc-plugin/) (the plugin route that introduced the namespacing)
