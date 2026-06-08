# IDEA-020 R1 — plugin-channel name-resolution audit

Date: 2026-06-08 · Host: plugin-only (mind-vault marketplace plugin `mv` @ v5.1.1, symlinks removed)

The keystone fact the fix depends on: **how do the three executed-dispatch mechanisms resolve prefixed-vs-bare names on the plugin channel?** All three were observed live this session (not theorised). Bare resolves for **none** of them.

| Mechanism | Bare form | Plugin-channel result | Required form |
| --- | --- | --- | --- |
| `Skill` tool (skill name) | `Skill(skill="plan")` | host registry exposes mind-vault skills **only** as `mv:<name>` after symlink removal; `Skill(skill="mv:plan")` / `mv:idea` ran | **`mv:<skill>`** |
| `Agent` tool (`subagent_type`) | `Agent(subagent_type="mv-architect")` | **`Error: Agent type 'mv-architect' not found`** — available list shows `mv:mv-architect`, `mv:mv-backend`, … ; `Agent(subagent_type="mv:mv-architect")` resolved | **`mv:mv-<persona>`** (stacked) |
| Literal slash (ScheduleWakeup `prompt`, typed) | `/review-loop …` | did not resolve on plugin-only (the original IDEA-020 bug); `/mv:review-loop 193 …` re-entered correctly | **`/mv:<command>`** |

## Evidence (this session)

- **Skill tool:** `Skill(skill="mv:idea")` and `Skill(skill="mv:plan")` both launched their skills from the plugin cache (`~/.claude/plugins/cache/mind-vault/mv/5.1.1/skills/...`). The post-symlink-removal available-skills list contains `mv:plan`, `mv:work`, … and **no** bare `plan`/`work` entries.
- **Agent tool:** the `/plan` architect handoff called `Agent(subagent_type="mv-architect")` → hard error `Agent type 'mv-architect' not found. Available agents: … mv:mv-architect, mv:mv-backend, mv:mv-curator, mv:mv-devops, mv:mv-documentation, mv:mv-frontend, mv:mv-researcher, mv:mv-test-engineer …`. Retried `Agent(subagent_type="mv:mv-architect")` → resolved, review ran. **The `mv-` subagent prefix `persona-dispatch.md:7` added "to avoid collisions" is itself prefixed by the plugin's `mv:` → the stacked `mv:mv-` form.**
- **Literal slash:** PR #193 (v5.1.2) — bare `/review-loop` re-entry failed on plugin-only; `/mv:review-loop` fixed it. Confirmed again this session: the IDEA-020 review-loop re-entered via `/mv:review-loop`.

## Conclusion

- **No "bare might resolve" branch exists** — bare fails for all three mechanisms on the plugin channel. The fix is gated on a written confirmation (this log), not an open unknown.
- **Detection signal:** the **invocation form** the agent sees (`/sprint-auto` vs `/mv:sprint-auto`, etc.). `${CLAUDE_PLUGIN_ROOT}` is **not** exposed in the agent's Bash shell (`echo "${CLAUDE_PLUGIN_ROOT:-<unset>}"` → `<unset>`), so an env probe is not viable — mirror the invocation prefix and persist it.
- **Symlink channel** keeps the bare forms (`Skill(skill="plan")`, `subagent_type "mv-architect"`, `/review-loop`) — the fix must keep both working, mirroring whichever channel invoked the skill.
