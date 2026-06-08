# IDEA-017 — Verification Log

Date: 2026-06-08
Branch: `feat/idea-017-mind-vault-cc-plugin`
Plan: [`2026-06-07-mind-vault-cc-plugin-plan.md`](./2026-06-07-mind-vault-cc-plugin-plan.md)

## Commits (this work)

| SHA | Step | Summary |
| --- | --- | --- |
| `6aa4bb9` | 1, 2 | Audit agent frontmatter (clean); move `SKILL_CONTRACT.md` → `skills/work/references/`, repoint ~13 referrers, both gates pass |
| `d70d8b1` | 3, 4 | `.claude-plugin/plugin.json` + `marketplace.json` (`name: mv`, `displayName: Mind-Vault`, `version: 5.0.5`, `source: ./`) |
| `637aff6` | 5 | Rule-loading: channel-aware `/mv:load-rules` + `hooks/hooks.json` `SessionStart` auto-inject (Q5 stretch implemented) |
| `45a134c` | 4b | `/wrap` Step 4b multi-location version sync + `/compound` self-mode plugin.json mirror bump |
| `e92f565` | 7 | Best-effort double-load guard in `setup-claude-code-symlinks.sh` |
| `9ed72f4` | 6 | Install-as-plugin docs in README + AGENTS.md + ONBOARDING (namespacing note, coexist note, dev-loop) |

Step 8 (IDEA-014 backref per RULE_cross-idea-amendments) is a `/wrap` action — deferred.

## Automated verification — all green

| Check | Result |
| --- | --- |
| `claude plugin validate ./ --strict` | ✔ Validation passed |
| `jq .name plugin.json` | `mv` |
| Version sync: `plugin.json.version` == top CHANGELOG `## v` | ✔ both `5.0.5` |
| `jq .plugins[0].source marketplace.json` | `./` (plugin id `mv`) |
| `agents/*.md` count | 8 (no `SKILL_CONTRACT.md`) |
| Stale path `git grep agents/SKILL_CONTRACT` (excl. CHANGELOG/archive) | 0 |
| Link-resolution: every `SKILL_CONTRACT.md` link resolves to moved file | 12/12 OK |
| Agent frontmatter `^(hooks\|mcpServers\|permissionMode):` | empty (plugin-safe) |
| 6 commands present | `brainstorm create-pr git-status load-rules review-loop test` |
| CC script `bash -n` + all 6 link trees intact | ✔ coexist intact |
| Non-CC scripts diff vs `main` | none (untouched) |
| `hooks/hooks.json` valid JSON + `load-rules.sh` executable | ✔ |
| Hook on plugin path injects rule bodies via `additionalContext` | ✔ (~13.5 KB, all 4 RULE_* present) |
| Hook fallback (no `CLAUDE_PLUGIN_ROOT` / no rules dir) | ✔ emits `/mv:load-rules` pointer note |

## Manual checks — pending a live CC session / real install

These need a running Claude Code session or a real `/plugin install` and could not be
exercised from the dev shell. Confirm before/after first real install:

- [ ] `claude --plugin-dir ~/projects/mind-vault` → skills discoverable, `/reload-plugins` works, `/plugin` UI shows **"Mind-Vault"**.
- [ ] All 6 commands appear namespaced: `/mv:{brainstorm,create-pr,git-status,load-rules,review-loop,test}`.
- [ ] `SessionStart` welcome/rules hook fires on a plugin-active session (auto-inject path).
- [ ] `/mv:load-rules` resolves rules under `--plugin-dir` (via `${CLAUDE_PLUGIN_ROOT}/rules/`).
- [ ] After a real `/plugin install`, confirm `rules/RULE_*.md` exists under the cached plugin
      root (it's inside the plugin root, so it should copy). If the install prunes non-component
      dirs, the hook's pointer-note fallback covers it and `/mv:load-rules` falls back to repo —
      record which holds.

## Notes / deviations from the plan

- **Q5 stretch implemented, not deferred.** The architect/plan flagged auto-inject of rule
  *content* via `SessionStart additionalContext` as a stretch to verify. The CC docs confirm
  `hookSpecificOutput.additionalContext` is supported for `SessionStart`, so `hooks/load-rules.sh`
  auto-loads the 4 always-on rule bodies (~13 KB) for symlink-channel parity, with a graceful
  fallback to the `/mv:load-rules` pointer note when `jq`/env/dir are unavailable.
- **Plan internal inconsistency (non-blocking).** The plan's Verification line asserts
  `jq .name plugin.json == "mind-vault"`, but Q3 + exec steps 3 & 4 authoritatively resolve
  `name: "mv"` (install `mv@mind-vault`). The stale line predates the Q3 resolution; implemented
  per the authoritative `mv`. Marketplace top-level `name` stays the descriptive `mind-vault`.
