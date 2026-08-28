#!/usr/bin/env bash
# Copilot adapter clean-detection tests.
#
# The adapter decides CLEAN from copilot's review BODY, with a check-run
# synthesis as a fallback for the case where copilot posts a check-run and no
# review body at all. Two ways that goes wrong, both observed live on
# mind-vault PR #240 and both covered here:
#
#   (a) FORMAT DRIFT — copilot's body template moved to emoji buckets
#       ("Approval recommended" / "Changes recommended" / "Needs a closer
#       look"). Neither legacy CLEAN_PHRASE appears in any of them, so body-level
#       clean detection went fully blind and nothing complained: the check-run
#       fallback quietly took over and kept answering.
#   (b) FALSE CLEAN — a body can carry real findings under "Suppressed comments
#       (N)" while reporting "Comments generated: 0 new". Those post no inline
#       comment, so the inline pre-check cannot see them; the fallback then
#       synthesized CLEAN over two genuine findings.
#
# Both fixtures below were verified to FAIL against the pre-fix adapter — the
# suppressed-findings case emitted COPILOT_CLEAN_SIGNAL=checkrun-*, which is the
# bug. A fixture that passes against the bug proves nothing.
#
# Fixtures: tests/fixtures/copilot/<case>/ — payloads fed via the adapter's
# COPILOT_FIXTURE_DIR test seam (no network).
# Run: bash tests/test_copilot_clean_detection.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/tools/find_copilot_comments.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/copilot"
PASS=0
FAIL=0

# Strip ANSI color so substring asserts match the plain text the script prints.
run_case() {
    COPILOT_FIXTURE_DIR="$FIXTURES/$1" bash "$SCRIPT" 1 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected to find: %q\n' "$label" "$needle"; FAIL=$((FAIL + 1))
    fi
}

assert_absent() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf '  FAIL  %s\n        expected NOT to find: %q\n' "$label" "$needle"; FAIL=$((FAIL + 1))
    else
        printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
    fi
}

echo ""
echo "── (a) Emoji-bucket template is recognized as clean ──────────────────────"
OUT=$(run_case approval-recommended)
assert_contains "approval: clean signal emitted"          "$OUT" "COPILOT_CLEAN_SIGNAL=9001"
assert_contains "approval: latest review flagged CLEAN"   "$OUT" "COPILOT_LATEST_REVIEW=9001"
assert_contains "approval: CLEAN=true"                    "$OUT" "CLEAN=true"
# The signal must come from the BODY, not the check-run fallback. A checkrun-*
# value here means body detection is blind again and the fallback is covering.
assert_absent   "approval: not synthesized from check-run" "$OUT" "COPILOT_CLEAN_SIGNAL=checkrun-"

echo ""
echo "── (b) Suppressed findings are NEVER clean (false-CLEAN gate) ────────────"
OUT=$(run_case suppressed-findings)
assert_absent   "suppressed: no clean signal at all"       "$OUT" "COPILOT_CLEAN_SIGNAL="
assert_absent   "suppressed: no check-run synthesis"       "$OUT" "COPILOT_CLEAN_SIGNAL=checkrun-"
assert_contains "suppressed: latest review CLEAN=false"    "$OUT" "CLEAN=false"
# The findings live only in the body, so the body has to reach the loop.
assert_contains "suppressed: non-clean review surfaced"    "$OUT" "review 9002"
# Withholding the clean signal is not enough: the orchestrator derives clean
# structurally and ignores the legacy CLEAN= token, so a detected-but-unsurfaced
# suppressed block is a silent finding. The marker + the items must both reach
# the loop, or there is nothing to triage.
assert_contains "suppressed: marker with count + review"   "$OUT" "COPILOT_SUPPRESSED=2 REVIEW=9002"
assert_contains "suppressed: item 1 surfaced verbatim"     "$OUT" "tools/example.sh:350"
assert_contains "suppressed: item 2 surfaced verbatim"     "$OUT" "CHANGELOG.md:15"
assert_contains "suppressed: item text surfaced"           "$OUT" "The fence only checks created_at."
# The stats list that follows the block is not a finding — the extractor must stop.
assert_absent   "suppressed: stats list not swallowed"     "$OUT" "Files reviewed:"

# No false positives: a clean review must not emit the marker.
OUT=$(run_case approval-recommended)
assert_absent   "approval: no suppressed marker"           "$OUT" "COPILOT_SUPPRESSED="
OUT=$(run_case legacy-clean-phrase)
assert_absent   "legacy: no suppressed marker"             "$OUT" "COPILOT_SUPPRESSED="

echo ""
echo "── (c) The seam really is offline ────────────────────────────────────────"
# The seam's whole promise is deterministic offline runs. Enforce it rather than
# asserting it: run a case with a `gh` that always fails, standing in for no auth
# and no network. Before the repo-identity branch existed, the adapter called
# `gh repo view` unconditionally and died there (exit 127 with gh absent, exit 1
# unauthenticated) before reaching a single fixture — and this suite still passed,
# because the machine running it happened to have gh installed and authed.
SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT
printf '#!/bin/sh\necho "gh: not authenticated" >&2\nexit 1\n' > "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"
OUT=$(PATH="$SHIM_DIR:$PATH" COPILOT_FIXTURE_DIR="$FIXTURES/approval-recommended" \
      bash "$SCRIPT" 1 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g')
assert_contains "offline: still emits a verdict with gh failing" "$OUT" "COPILOT_LATEST_REVIEW=9001"
assert_absent   "offline: no gh error leaks into output"         "$OUT" "not authenticated"

echo ""
echo "── (d) Legacy clean phrasing still recognized (back-compat) ──────────────"
OUT=$(run_case legacy-clean-phrase)
assert_contains "legacy: clean signal emitted"             "$OUT" "COPILOT_CLEAN_SIGNAL=9003"
assert_contains "legacy: CLEAN=true"                       "$OUT" "CLEAN=true"

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
