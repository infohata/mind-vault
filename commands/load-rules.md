---
description: Load mind-vault behavioural rules (RULE_*.md) — works on both the plugin and symlink channels
agent: general
---

# load-rules

Load the mind-vault behavioural rules into working memory. Works on both
distribution channels:

- **Plugin channel** — rules ship inside the plugin root. The env var
  `${CLAUDE_PLUGIN_ROOT}` points at the installed/dev plugin root; rules live at
  `${CLAUDE_PLUGIN_ROOT}/rules/`. Rules are NOT auto-loaded on this channel (a
  plugin has no always-on rules surface), so this command is how they get in.
- **Symlink channel** — `~/.claude/rules/` is symlinked to the repo's `rules/`
  and surfaced via `~/.claude/CLAUDE.md`. This command reloads them after a
  context compaction.

Steps to follow:

1. **Resolve the rules directory.** In order:

   - If `${CLAUDE_PLUGIN_ROOT}` is set and `${CLAUDE_PLUGIN_ROOT}/rules/` exists,
     use it (plugin channel).
   - Else use the repo-relative `rules/` directory (symlink/dev channel).
   - **Detect + warn:** if neither resolves to a directory containing
     `RULE_*.md`, stop and report that no rules were found — name both paths you
     tried. Do not silently load zero rules.

2. Glob `RULE_*.md` in the resolved directory and read the full content of each.

3. Keep each rule in working memory for this session — its directives apply to
   every subsequent tool call.

4. Display a summary of all loaded rules:

   - The resolved rules directory and which channel it implies
   - Each rule name + a brief description
   - Confirm they are active for enforcement

5. Verify no rules are missing or corrupted.

6. Provide confirmation that rules have been loaded and are ready for use.
