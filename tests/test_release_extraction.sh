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
        # `exit 1` not `return 1` — `return` is invalid in a subshell; a
        # failed `cd` would otherwise continue and run `make` from the
        # wrong directory, producing misleading PASS/FAIL.
        cd "$fixture_dir" || exit 1
        # Defang an inherited shell VERSION env var — without this, every
        # auto-detection assertion would short-circuit to that override
        # value instead of reading the fixture's source file. Explicit
        # override is still tested by passing VERSION=... via "$@" below
        # (each invocation gets its own subshell, so the unset doesn't
        # leak into the caller's environment).
        unset VERSION
        # NOTE: stderr is intentionally NOT suppressed — on extraction
        # failure, the harness lets make's error message flow through so
        # failures have diagnostic context. assert_eq only captures stdout
        # via $(...), so stderr never pollutes the comparison.
        make -f "$REPO_ROOT/Makefile" --no-print-directory extract-version "$@"
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
assert_eq "VERSION file"                       "$(extract "$FIXTURES/VERSION-only")"             "1.2.3"
assert_eq "pyproject.toml (double-quoted)"     "$(extract "$FIXTURES/pyproject")"                "2.0.0"
assert_eq "pyproject.toml (single-quoted)"     "$(extract "$FIXTURES/pyproject-single-quote")"   "5.5.5"
assert_eq "package.json"                       "$(extract "$FIXTURES/package")"                  "3.1.4"
assert_eq "Cargo.toml"                         "$(extract "$FIXTURES/cargo")"                    "0.5.0"
assert_eq "setup.py"                           "$(extract "$FIXTURES/setup-py")"                 "0.9.1"
assert_eq "CHANGELOG.md ## v<N>"               "$(extract "$FIXTURES/changelog-v")"              "v4.0.2"
assert_eq "CHANGELOG.md ## V<N>"               "$(extract "$FIXTURES/changelog-V-upper")"        "V2.1.0"
assert_eq "CHANGELOG.md ## [<N>]"              "$(extract "$FIXTURES/changelog-kac")"            "4.0.2"
assert_eq "package.json no-version → fallthrough to CHANGELOG" \
                                                "$(extract "$FIXTURES/package-no-jq-fallthrough")" "v7.7.7"

echo
echo "Explicit VERSION= override:"
assert_eq "override on VERSION file"   "$(extract "$FIXTURES/VERSION-only" VERSION=v9.9.9-override)" "v9.9.9-override"
assert_eq "override on missing source" "$(extract "$FIXTURES/empty" VERSION=v0.0.1-only)"            "v0.0.1-only"

echo
echo "Error cases:"
# No source file present; no override → must fail. We only care about exit
# code; stdout is discarded. extract()'s stderr flows through (by design
# per the note in its body) so the failure diagnostic still appears in the
# test run log, with no impact on this assertion's correctness.
extract "$FIXTURES/empty" >/dev/null
assert_nonzero_exit "empty dir, no override" "$?"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
