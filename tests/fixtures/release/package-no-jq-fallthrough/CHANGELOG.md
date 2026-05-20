# Changelog

## v7.7.7 — fallback header

Verifies that when `package.json` lacks `.version` (jq -e fails), extraction
falls through to the next source — here, CHANGELOG.md — rather than erroring out.
