#!/usr/bin/env bash
# review-loop Phase 4 accelerator — READ-ONLY. Emits ONE event line, then exits 0.
# Used by the /review-loop skill (mind-vault) as the Monitor command; see
# skills/review-loop/references/MONITOR_ACCELERATION.md for the full contract.
#
# Usage (CWD = the project under review — the adapters resolve the repo from it):
#   review_loop_monitor.sh <PR_NUMBER> <ENGINES> <ARM_SHA> [POLL_INTERVAL]
#     ENGINES   comma-separated, e.g. "claude,copilot" (scratch `engines`)
#     ARM_SHA   scratch `last_push_sha` at arm time — the frozen baseline
#
# Emits exactly one of:
#   all-done      every engine's check-run is STATUS=completed for the head SHA
#   sha-changed   live HEAD diverged from ARM_SHA (out-of-band push)
#   engine-error  run-level failure (failure|cancelled|timed_out), or an adapter
#                 that cannot be found — never a silent poll-to-timeout
#   claude-noop   claude completed with 0 head-SHA verdicts and no Claude Code
#                 workflow in flight — the agent should retrigger
#
# It NEVER reads a verdict. It answers only "are the head-SHA runs finished /
# did HEAD move?". No review-comment selection, no `| last`, no summary text in
# the emitted line — the agent reads verdicts only from find_<engine>_comments.sh
# on wake, judging every id in <ENGINE>_VERDICT_IDS oldest-first.
#
# Adapter resolution (per engine, first hit wins): $MV_TOOLS, the project's own
# tools/ port, this script's own directory (the mind-vault install it ships in).
# `./tools/` exists only in mind-vault itself and in projects that ported the
# adapters, so a hard-coded `./tools/` path polls empty output downstream.
#
# NOTE: pipefail only — do NOT add `set -u`. The Monitor's background shell
# sources the host shell-snapshot, which references optional vars (e.g.
# ZSH_VERSION) with no default; under nounset that is a fatal "unbound variable"
# and the poller never reaches its emit. (IDEA-021 dogfood, F-dogfood-4.)
set -o pipefail

PR="${1:-}"
ENGINES="${2:-}"
ARM_SHA="${3:-}"
POLL_INTERVAL="${4:-30}"

if [ -z "$PR" ] || [ -z "$ENGINES" ] || [ -z "$ARM_SHA" ] || [ "$#" -gt 4 ]; then
  echo "engine-error: usage: review_loop_monitor.sh <PR> <ENGINES> <ARM_SHA> [POLL_INTERVAL]"
  exit 0
fi
# A non-numeric PR makes every adapter fail, and `2>/dev/null || true` below would
# hide that as "not done yet" until the Monitor's timeout.
case "$PR" in *[!0-9]*)
  echo "engine-error: PR must be a number, got '$PR'"; exit 0 ;;
esac
# ≥30s — remote API, rate-limit-friendly. A non-integer or smaller value would
# otherwise spin a tight API loop (no errexit: a failed `sleep` just loops again).
case "$POLL_INTERVAL" in ''|*[!0-9]*) POLL_INTERVAL=30 ;; esac
[ "$POLL_INTERVAL" -lt 30 ] && POLL_INTERVAL=30

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "engine-error: not inside a git checkout (run with CWD = the project under review)"
  exit 0
}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Resolve each engine's finder once, up front. A missing adapter is an
# engine-error now, not an empty `out` that never matches and times out.
# FINDERS is an indexed array parallel to ENG — NOT `declare -A`: macOS ships
# bash 3.2, where `declare -A` fails and FINDER[claude] / FINDER[copilot] both
# collapse to index 0, so every engine polls the last-resolved adapter.
IFS=',' read -ra ENG <<< "$ENGINES"
FINDERS=()
for i in "${!ENG[@]}"; do
  e=${ENG[$i]}; f=
  for d in "${MV_TOOLS:-}" "$REPO_ROOT/tools" "$SELF_DIR"; do
    [ -n "$d" ] && [ -x "$d/find_${e}_comments.sh" ] && { f="$d/find_${e}_comments.sh"; break; }
  done
  if [ -z "$f" ]; then
    echo "engine-error: find_${e}_comments.sh not found (looked in \$MV_TOOLS, $REPO_ROOT/tools, $SELF_DIR; set MV_TOOLS)"
    exit 0
  fi
  FINDERS[$i]=$f
done

# Count non-completed runs of every workflow named "Claude Code*" (both the
# auto-review and the @-mention workflow). Queried per status rather than as one
# truncated repo-wide page, so unrelated newer runs can't hide an in-flight one.
# Any read failure ⇒ 1 (assume in flight, never "clear").
claude_inflight() {
  local n=0 st c
  for st in queued in_progress waiting requested pending; do
    c=$(gh run list --status "$st" --limit 100 --json workflowName \
          --jq '[.[] | select(.workflowName|startswith("Claude Code"))] | length' 2>/dev/null) || { echo 1; return; }
    case "$c" in ''|*[!0-9]*) echo 1; return ;; esac
    n=$((n + c))
  done
  echo "$n"
}

while true; do
  cd "$REPO_ROOT" || { sleep "$POLL_INTERVAL"; continue; }   # cd INSIDE the loop (WATCHER_HYGIENE Rule 4)

  # (sha-changed) live HEAD vs the FROZEN arm-time baseline — never two live reads.
  live_sha=$(git rev-parse HEAD 2>/dev/null || echo "$ARM_SHA")
  if [ "$live_sha" != "$ARM_SHA" ]; then
    echo "sha-changed: HEAD now $live_sha (armed at $ARM_SHA)"; exit 0
  fi

  all_done=1
  for i in "${!ENG[@]}"; do
    e=${ENG[$i]}
    out=$("${FINDERS[$i]}" "$PR" 2>/dev/null || true)   # read-only; tolerate transient failure
    # Case-insensitive anchor, no dynamic uppercasing (a `tr` subshell inside the
    # pattern mis-parsed in the Monitor's shell → never matched → silent timeout).
    line=$(printf '%s\n' "$out" | grep -iE "^${e}_CHECKRUN=" | head -1)
    status=$(printf '%s' "$line" | sed -n 's/.* STATUS=\([^ ]*\).*/\1/p')
    concl=$(printf '%s'  "$line" | sed -n 's/.* CONCLUSION=\([^ ]*\).*/\1/p')

    # (engine-error) ONLY run-level failures the multi-engine-sync escape-hatch
    # table acts on. success/neutral/action_required are normal completions —
    # findings or not — and are caught by all-done.
    case "$concl" in
      failure|cancelled|timed_out)
        echo "engine-error: $e CONCLUSION=$concl"; exit 0 ;;
    esac

    # (claude-noop) completed, the adapter PROVES zero head-SHA material (both
    # markers present and 0 — an absent marker is "unknown", never "none"), and no
    # Claude Code workflow of ANY name in flight. Inline-only findings complete the
    # run with CLAUDE_HEAD_VERDICTS=0, so the inline count is load-bearing too. The
    # in-flight guard is load-bearing: the adapter samples only
    # claude-code-review.yml, so a claude.yml retrigger is invisible to it — without
    # the guard this fires mid-retrigger and drives a billed retrigger loop.
    if [ "$e" = "claude" ] && [ "$status" = "completed" ]; then
      hv=$(printf '%s\n' "$out" | grep -iE "^CLAUDE_HEAD_VERDICTS=" | sed -n 's/^[^=]*=\([0-9]*\).*/\1/p')
      hi=$(printf '%s\n' "$out" | grep -iE "^CLAUDE_HEAD_INLINE=" | sed -n 's/^[^=]*=\([0-9]*\).*/\1/p')
      if [ "$hv" = "0" ] && [ "$hi" = "0" ] && [ "$(claude_inflight)" = "0" ]; then
        echo "claude-noop: completed with 0 head-SHA verdicts, nothing in flight — retrigger needed"; exit 0
      fi
    fi

    [ "$status" = "completed" ] || all_done=0
  done

  # (all-done) the multi-engine sync gate, met. Says nothing about the verdict.
  if [ "$all_done" -eq 1 ]; then
    echo "all-done: every engine completed for $ARM_SHA"; exit 0
  fi

  sleep "$POLL_INTERVAL"
done
