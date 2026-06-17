#!/usr/bin/env bash
# IDEA-022 test layers for the claude verdict model-judge.
#
# The claude adapter (tools/find_claude_comments.sh) was reduced from a prose
# REGEX CLASSIFIER to a MATERIAL SURFACER: it no longer computes clean/findings
# from claude's prose; the /review-loop model-judge does (engine-claude.md
# § Verdict judge). A model judgment can't be asserted deterministically in bash,
# so the gate is ASYMMETRIC (architect C2):
#
#   (a) DETERMINISTIC material-surfacing — the adapter extracts the right
#       structural material (STATUS, in-window verdict enumeration, verbatim
#       bodies, inline ids, CLAUDE_VERDICT_SET_PROVEN) from captured payloads.
#   (b) FALSE-CLEAN HARD GATE (structurally-detectable part) — for the dangerous
#       fixtures the adapter MUST (i) surface the blocking concern verbatim so the
#       judge can't be starved of it, (ii) enumerate BOTH bodies on a masking SHA,
#       and (iii) hold VERDICT_SET_PROVEN=false on an unprovable set (forbidding a
#       CLEAN judgment). The semantic NOT-CLEAN *reading* of pure prose is the
#       judge's job — judge-eval / advisory, NOT a bash assertion. bash guarantees
#       the judge SEES the concern + the structural fail-closed holds; the model
#       guarantees it READS the concern correctly.
#   (c) ADVISORY — the CLEAN-vs-NON_BLOCKING boundary (the dogfood clean recap)
#       is a calibration signal, documented here, not gated.
#
# Fixtures: tests/fixtures/claude/<case>/ — captured GitHub API payloads fed via
# the adapter's CLAUDE_FIXTURE_DIR test seam (no network). Run: bash tests/test_claude_material_surfacing.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/tools/find_claude_comments.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/claude"
PASS=0
FAIL=0

# Strip ANSI color so substring asserts match the plain text the script prints.
run_case() {
    CLAUDE_FIXTURE_DIR="$FIXTURES/$1" bash "$SCRIPT" 1 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected to find: %q\n' "$label" "$needle"; FAIL=$((FAIL + 1))
    fi
}

assert_eq() {
    local label="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected: %q  actual: %q\n' "$label" "$expected" "$actual"; FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf '  FAIL  %s\n        expected ABSENT but found: %q\n' "$label" "$needle"; FAIL=$((FAIL + 1))
    else
        printf '  PASS  %s\n' "$label"; PASS=$((PASS + 1))
    fi
}

echo "── (a) Deterministic material-surfacing ──────────────────────────────────"

OUT=$(run_case clean-recap)
assert_contains   "clean-recap: DONE state surfaced"        "$OUT" "STATUS=completed"
assert_contains   "clean-recap: verdict set proven"         "$OUT" "CLAUDE_VERDICT_SET_PROVEN=true"
assert_contains   "clean-recap: 1 in-window verdict"        "$OUT" "CLAUDE_HEAD_VERDICTS=1"
assert_contains   "clean-recap: body surfaced verbatim"     "$OUT" "All findings from both prior review rounds are resolved"
assert_contains   "clean-recap: staleness anchor present"   "$OUT" "CLAUDE_LATEST_REVIEW=4729548936"
# Regex classifier must be GONE — no clean/findings verdict computed by the adapter.
assert_not_contains "clean-recap: no regex findings flag"   "$OUT" "CLAUDE_HAS_FINDINGS="
assert_not_contains "clean-recap: no regex CLEAN= on summary line" "$OUT" "FINDINGS=true"

OUT=$(run_case inline-blocking)
assert_contains   "inline-blocking: inline id+review token"  "$OUT" "(comment id 6010, review 99001)"
assert_contains   "inline-blocking: inline body surfaced"    "$OUT" "is called without"

echo ""
echo "── (b) False-CLEAN hard gate — structurally-detectable part ───────────────"

# summary-body-only blocking finding (the :176 ~30-docstring shape): zero inline,
# the concern lives ONLY in the summary body — adapter MUST surface it verbatim.
OUT=$(run_case summary-body-only-blocking)
assert_contains   "summary-only: body concern surfaced verbatim" "$OUT" "SQL injection in the search endpoint"
assert_contains   "summary-only: 1 in-window verdict"            "$OUT" "CLAUDE_HEAD_VERDICTS=1"
assert_contains   "summary-only: verdict set proven"             "$OUT" "CLAUDE_VERDICT_SET_PROVEN=true"

# dual-verdict masking: newer clean body must NOT hide the earlier findings body —
# adapter MUST enumerate BOTH so the masked verdict reaches the judge.
OUT=$(run_case dual-verdict-masking)
assert_contains   "masking: both verdicts enumerated"           "$OUT" "CLAUDE_HEAD_VERDICTS=2"
assert_contains   "masking: earlier findings body surfaced"     "$OUT" "Missing auth check on /admin/export"
assert_contains   "masking: newer clean body surfaced"          "$OUT" "No issues found. The PR looks good"

# marker-less prose: reads clean ("No bugs found") yet carries a blocking concern
# in plain prose — the false-CLEAN hole the old regex fell into. Adapter MUST
# surface the concern verbatim; the NOT-CLEAN reading is the judge's (advisory).
OUT=$(run_case marker-less-prose)
assert_contains   "marker-less: concern surfaced verbatim"      "$OUT" "no authentication check"
assert_contains   "marker-less: body surfaced (judge reads it)" "$OUT" "anyone can pull the full"

# unprovable verdict set: blank run timestamps → can't prove the whole set was
# seen → VERDICT_SET_PROVEN MUST be false, structurally forbidding a CLEAN judgment.
OUT=$(run_case unprovable-verdict-set)
assert_contains   "unprovable: fail-closed (set NOT proven)"    "$OUT" "CLAUDE_VERDICT_SET_PROVEN=false"
assert_contains   "unprovable: body still surfaced as material" "$OUT" "No issues found"

echo ""
echo "── (c) Regex classifier removed from the adapter (executable code) ────────"
# Meta-assert the EXECUTABLE classifier is gone — the export of the prose patterns
# and their regex usage. (A "we removed X" comment may still NAME them; this checks
# the code, not the prose.)
assert_eq "no CLAUDE_CLEAN_PATTERNS export"  "$(grep -c '^export CLAUDE_CLEAN_PATTERNS'  "$SCRIPT")" "0"
assert_eq "no CLAUDE_FINDING_MARKERS export" "$(grep -c '^export CLAUDE_FINDING_MARKERS' "$SCRIPT")" "0"
assert_eq "no clean_re/finding_re regex use" "$(grep -cE 'clean_re|finding_re'           "$SCRIPT")" "0"
assert_eq "no is_clean prose verdict"        "$(grep -cE '\bis_clean\b'                  "$SCRIPT")" "0"

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
