#!/usr/bin/env bash
# SessionStart hook — Mind-Vault plugin channel (IDEA-017).
#
# Auto-loads the always-on behavioural rules (rules/RULE_*.md) into the session
# via SessionStart `additionalContext`, giving the plugin channel parity with
# the symlink channel (where ~/.claude/rules/ is auto-loaded by Claude Code).
# Falls back to a short pointer note prompting /mv:load-rules if the rules
# cannot be read (jq missing, env var unset, or dir absent).
#
# This hook only ever fires when the plugin is active; symlink-path machines
# auto-load rules via ~/.claude/CLAUDE.md and never invoke it.

# Re-exec under bash if a host invoked us via sh/dash. This script uses bash
# arrays + `shopt nullglob` + `set -o pipefail` (all bashisms); under a POSIX sh
# the `set -o pipefail` below aborts with exit 2 ("Illegal option") BEFORE any
# emit_note fallback can run, hard-failing SessionStart instead of degrading to
# the /mv:load-rules pointer note. Keep this guard POSIX-clean and first.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -euo pipefail

emit_note() {
  # Static fallback — no escaping needed.
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Mind-Vault plugin active. Behavioural rules are NOT auto-loaded on the plugin channel — run /mv:load-rules to load them."}}
JSON
}

rules_dir="${CLAUDE_PLUGIN_ROOT:-}/rules"

# Need jq (safe JSON escaping of markdown bodies) and a readable rules dir.
if ! command -v jq >/dev/null 2>&1 || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -d "$rules_dir" ]; then
  emit_note
  exit 0
fi

shopt -s nullglob
rule_files=("$rules_dir"/RULE_*.md)
if [ "${#rule_files[@]}" -eq 0 ]; then
  emit_note
  exit 0
fi

header="Mind-Vault plugin active — the following behavioural rules are loaded and apply to every tool call this session (plugin-channel parity with ~/.claude/rules/). Their rationale docs (docs/rules/*-rationale.md) are not bundled on the plugin channel; load them from the repo if an edge case needs the full discussion."
body="$(cat "${rule_files[@]}")"

# Build the rules payload; if jq fails for any reason (encoding, size, runtime),
# fall back to the pointer note rather than letting `set -e` exit with no output
# — a bare non-zero exit emits neither the rules nor a note, silently breaking
# SessionStart instead of degrading to /mv:load-rules.
if ! jq -n --arg ctx "$header"$'\n\n'"$body" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'; then
  emit_note
fi
