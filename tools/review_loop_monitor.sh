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
POLL_INTERVAL="${4:-30}"   # ≥30s — remote API, rate-limit-friendly

if [ -z "$PR" ] || [ -z "$ENGINES" ] || [ -z "$ARM_SHA" ]; then
  echo "engine-error: usage: review_loop_monitor.sh <PR> <ENGINES> <ARM_SHA> [POLL_INTERVAL]"
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "engine-error: not inside a git checkout (run with CWD = the project under review)"
  exit 0
}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Resolve each engine's finder once, up front. A missing adapter is an
# engine-error now, not an empty `out` that never matches and times out.
IFS=',' read -ra ENG <<< "$ENGINES"
declare -A FINDER
for e in "${ENG[@]}"; do
  for d in "${MV_TOOLS:-}" "$REPO_ROOT/tools" "$SELF_DIR"; do
    [ -n "$d" ] && [ -x "$d/find_${e}_comments.sh" ] && { FINDER[$e]="$d/find_${e}_comments.sh"; break; }
  done
  if [ -z "${FINDER[$e]:-}" ]; then
    echo "engine-error: find_${e}_comments.sh not found (looked in \$MV_TOOLS, $REPO_ROOT/tools, $SELF_DIR; set MV_TOOLS)"
    exit 0
  fi
done

while true; do
  cd "$REPO_ROOT" || { sleep "$POLL_INTERVAL"; continue; }   # cd INSIDE the loop (WATCHER_HYGIENE Rule 4)

  # (sha-changed) live HEAD vs the FROZEN arm-time baseline — never two live reads.
  live_sha=$(git rev-parse HEAD 2>/dev/null || echo "$ARM_SHA")
  if [ "$live_sha" != "$ARM_SHA" ]; then
    echo "sha-changed: HEAD now $live_sha (armed at $ARM_SHA)"; exit 0
  fi

  all_done=1
  for e in "${ENG[@]}"; do
    out=$("${FINDER[$e]}" "$PR" 2>/dev/null || true)   # read-only; tolerate transient failure
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

    # (claude-noop) completed, no head-SHA verdict, and no Claude Code workflow of
    # ANY name in flight. The in-flight guard is load-bearing: the adapter samples
    # only claude-code-review.yml, so a claude.yml retrigger is invisible to it —
    # without the guard this fires mid-retrigger and drives a billed retrigger loop.
    if [ "$e" = "claude" ] && [ "$status" = "completed" ]; then
      hv=$(printf '%s\n' "$out" | grep -iE "^CLAUDE_HEAD_VERDICTS=" | sed -n 's/^[^=]*=\([0-9]*\).*/\1/p')
      inflight=$(gh run list --limit 12 --json workflowName,status \
                   --jq '[.[] | select(.workflowName|startswith("Claude Code")) | select(.status!="completed")] | length' \
                 2>/dev/null || echo 1)   # unreadable ⇒ assume in flight, never "clear"
      [ -z "$inflight" ] && inflight=1
      if [ "$inflight" -eq 0 ] && { [ -z "$hv" ] || [ "$hv" -eq 0 ]; }; then
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
