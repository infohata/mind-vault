#!/usr/bin/env bash
# Reference cross-anchor guard.
#
# Sections in the review-loop references are cited by GREPPABLE NAMED ANCHOR — a
# phrase that is a literal substring of exactly one heading. Line-number
# citations (§NNN) are banned, because they rot silently: the citation still
# reads like a working reference long after the line it named has moved, and the
# cost lands on whoever follows it (a read of the wrong content, then a hunt).
# A grep costs CPU; a bad pointer costs context.
#
# Measured on engine-claude.md before this guard existed:
#   - merging two branches that had each appended a section moved SIX citations
#     onto unrelated lines, with nothing failing;
#   - one citation (§131 + §140) was wrong in the very commit that wrote it;
#   - one anchor (§Net-capability) never matched anything at all.
#
# Run: bash tests/test_reference_anchors.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFDIR="$REPO_ROOT/skills/review-loop/references"
PASS=0
FAIL=0

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

# Strip the "§ Citing a section of this file" block — it quotes §NNN forms as the
# examples of what NOT to write, so scanning it would flag the rule itself.
without_convention_block() {
    awk '
        /^## § Citing a section of this file/ { skip = 1; next }
        /^## / && skip { skip = 0 }
        !skip { print }
    ' "$1"
}

echo ""
echo "── (a) No line-number citations ──────────────────────────────────────────"
found_numeric=0
for f in "$REFDIR"/*.md "$REPO_ROOT/skills/review-loop/SKILL.md"; do
    hits=$(without_convention_block "$f" | grep -nE '§ ?[0-9]{2,3}' || true)
    if [ -n "$hits" ]; then
        fail "$(basename "$f"): line-number citation(s)" "$(printf '%s' "$hits" | head -3)"
        found_numeric=1
    fi
done
[ "$found_numeric" -eq 0 ] && pass "no §NNN citations in review-loop references"

echo ""
echo "── (b) Named anchors resolve to exactly one heading ──────────────────────"
# Each entry: <file>|<anchor phrase>. The phrase must appear in exactly one
# heading of that file. These are the anchors carrying cross-section weight —
# the ones an agent actually follows.
ANCHORS="
engine-claude.md|dual substantive verdicts
engine-claude.md|install-stability has a counterexample
engine-claude.md|findings-bearing + clean runs
engine-claude.md|findings live in the SUMMARY BODY
engine-claude.md|slow-not-hung
engine-claude.md|A7
engine-copilot.md|Suppressed comments
"
while IFS='|' read -r file phrase; do
    [ -z "${file:-}" ] && continue
    # Select heading lines, then FIXED-STRING match the phrase. No regex is built
    # from the phrase, so there is nothing to escape — the earlier version fed the
    # phrase through a sed escape whose character class contained the substitution
    # delimiter, which is fragile across sed implementations even where it works.
    # `grep -c` prints 0 and exits 1 on no-match; piping it keeps the count clean
    # (`|| echo 0` appended a SECOND zero, so the no-match case evaluated
    # `[ "0\n0" -eq 1 ]` and reported failure via a shell error rather than an
    # assertion — a check that cannot express its own empty case, item 14 again).
    n=$(grep -E '^#+ ' "$REFDIR/$file" 2>/dev/null | grep -cF -- "$phrase")
    n=${n:-0}
    if [ "$n" -eq 1 ]; then
        pass "$file § $phrase"
    else
        fail "$file § $phrase" "matched $n headings (want exactly 1)"
    fi
done <<< "$ANCHORS"

echo ""
echo "── (c) Prose anchors are not dangling ────────────────────────────────────"
# "Net engine capability" is cited as an anchor but is bold prose, not a heading.
# Match the DEFINITION SITE only (bold at start of line) — grepping the whole file
# lets the citation satisfy its own anchor, which is an assertion that cannot fail.
# That bug was in this test's first draft; it is the same shape as
# STRICT_MODE_HAZARDS.md item 14.
if grep -qE '^\*\*Net engine capability' "$REFDIR/engine-claude.md"; then
    pass "engine-claude.md § Net engine capability resolves to its definition"
else
    fail "engine-claude.md § Net engine capability" "cited, but no definition site in the file"
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
