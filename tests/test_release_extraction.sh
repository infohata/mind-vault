#!/usr/bin/env bash
# Unit tests for `make extract-version` — verifies each of the six version-source
# formats `/wrap` Step 4b detects extracts to the expected value, plus the
# explicit VERSION= override and the no-source-error cases.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/release"
PASS=0
FAIL=0

# Run extract-version from inside the fixture dir so the Makefile's auto-detect
# fires against the fixture's source file — mirrors how `make release` runs in a
# real project root. `make -C $FIXTURES/<name>` doesn't work (no Makefile inside
# each fixture), so we copy the top-level Makefile via `make -f`.
extract() {
    local fixture_dir="$1"
    shift
    (
        cd "$fixture_dir" || return 1
        make -f "$REPO_ROOT/Makefile" --no-print-directory extract-version "$@" 2>/dev/null
    )
}

assert_eq() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$label"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected: %q\n        actual:   %q\n' \
            "$label" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_nonzero_exit() {
    local label="$1" rc="$2"
    if [[ "$rc" -ne 0 ]]; then
        printf '  PASS  %s (exit=%d)\n' "$label" "$rc"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s (expected non-zero exit, got 0)\n' "$label"
        FAIL=$((FAIL + 1))
    fi
}

echo "tests/test_release_extraction.sh — extract-version against six version-source fixtures + edge cases"
echo

echo "Version-source auto-detection:"
assert_eq "VERSION file"            "$(extract "$FIXTURES/VERSION-only")"   "1.2.3"
assert_eq "pyproject.toml"          "$(extract "$FIXTURES/pyproject")"      "2.0.0"
assert_eq "package.json"            "$(extract "$FIXTURES/package")"        "3.1.4"
assert_eq "Cargo.toml"              "$(extract "$FIXTURES/cargo")"          "0.5.0"
assert_eq "setup.py"                "$(extract "$FIXTURES/setup-py")"       "0.9.1"
assert_eq "CHANGELOG.md ## v<N>"    "$(extract "$FIXTURES/changelog-v")"    "v4.0.2"
assert_eq "CHANGELOG.md ## [<N>]"   "$(extract "$FIXTURES/changelog-kac")"  "4.0.2"

echo
echo "Explicit VERSION= override:"
assert_eq "override on VERSION file"   "$(extract "$FIXTURES/VERSION-only" VERSION=v9.9.9-override)" "v9.9.9-override"
assert_eq "override on missing source" "$(extract "$FIXTURES/empty" VERSION=v0.0.1-only)"            "v0.0.1-only"

echo
echo "Error cases:"
# No source file present; no override → must fail
out=$(extract "$FIXTURES/empty" 2>&1)
assert_nonzero_exit "empty dir, no override" "$?"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
