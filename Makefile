# mind-vault — repo-root Makefile
#
# IDEA-003 (release automation): `make release` collapses the post-merge
# tag + push + gh-release sequence into one command. Version-extraction
# honours the six sources `/wrap` Step 4b detects (VERSION, pyproject.toml,
# package.json, Cargo.toml, setup.py, CHANGELOG.md `## v<N>` / `## [<N>]`).
# Pass VERSION=v<N> to override auto-detection — required for projects
# whose CHANGELOG header version differs from the intended tag (mind-vault
# itself: CHANGELOG `## v4` but tags are `v4.0.1`, `v4.0.2`, ...).

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

.PHONY: help release extract-version test-release

# Shared extraction body — sourced by `extract-version` and `release`.
# Defined once, executed via `bash -c "$$EXTRACT_VERSION_SH"` so both targets
# stay in lockstep. The double-$$ escapes are Make → bash; the recipe receives
# the script via the exported env var below.
define EXTRACT_VERSION_SH
if [[ -n "$${VERSION:-}" ]]; then
    printf '%s\n' "$$VERSION"
    exit 0
fi

if [[ -f VERSION ]]; then
    tr -d '[:space:]' < VERSION
    echo
    exit 0
fi

if [[ -f pyproject.toml ]]; then
    line=$$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=' pyproject.toml || true)
    if [[ -n "$$line" ]]; then
        printf '%s\n' "$$line" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
        exit 0
    fi
fi

if [[ -f package.json ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "version-extract: package.json present but jq is not installed — install jq or pass VERSION=v<N> explicitly" >&2
        exit 1
    fi
    if v=$$(jq -er '.version' package.json 2>/dev/null); then
        printf '%s\n' "$$v"
        exit 0
    fi
    echo "version-extract: package.json found but jq could not parse '.version' — pass VERSION=v<N> explicitly or fix package.json" >&2
    exit 1
fi

if [[ -f Cargo.toml ]]; then
    line=$$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=' Cargo.toml || true)
    if [[ -n "$$line" ]]; then
        printf '%s\n' "$$line" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
        exit 0
    fi
fi

if [[ -f setup.py ]]; then
    line=$$(grep -m1 -E 'version[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']+' setup.py || true)
    if [[ -n "$$line" ]]; then
        printf '%s\n' "$$line" | sed -E 's/.*version[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*/\1/'
        exit 0
    fi
fi

if [[ -f CHANGELOG.md ]]; then
    line=$$(grep -m1 -E '^## ([vV][0-9]|\[[0-9])' CHANGELOG.md || true)
    if [[ -n "$$line" ]]; then
        case "$$line" in
            "## v"*|"## V"*) printf '%s\n' "$$line" | sed -E 's/^## ([vV][^ ]+).*/\1/' ;;
            "## ["*)         printf '%s\n' "$$line" | sed -E 's/^## \[([^]]+)\].*/\1/' ;;
        esac
        exit 0
    fi
fi

echo "version-extract: no version source found (looked for VERSION, pyproject.toml, package.json, Cargo.toml, setup.py, CHANGELOG.md '## v<N>' / '## V<N>' / '## [<N>]' header) and no VERSION= override given" >&2
exit 1
endef
export EXTRACT_VERSION_SH

help: ## Show this help message
	@grep -hE '^[a-zA-Z_-]+:[^#]*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":[^#]*## "} {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

extract-version: ## Print the version `release` would tag (VERSION=v<N> overrides auto-detect)
	@bash -c "$$EXTRACT_VERSION_SH"

release: ## Tag + push + GH-release the current version (VERSION=v<N> overrides auto-detect)
	@ver=$$(bash -c "$$EXTRACT_VERSION_SH"); \
	if [[ -z "$$ver" ]]; then \
		echo "release: extract-version returned empty; aborting" >&2; \
		exit 1; \
	fi; \
	echo "release: version = $$ver"; \
	echo "release: fetching tags from origin (so local-state checks see remote tags)"; \
	git fetch origin --tags --quiet 2>/dev/null || echo "release: warning — git fetch --tags failed (continuing with local state)"; \
	if git ls-remote --tags origin "refs/tags/$$ver" 2>/dev/null | grep -q .; then \
		remote_tag_exists=1; \
		echo "release: remote tag $$ver already exists on origin — skipping push"; \
	else \
		remote_tag_exists=0; \
	fi; \
	if git rev-parse --verify --quiet "refs/tags/$$ver" >/dev/null; then \
		echo "release: local tag $$ver already exists — skipping tag create"; \
	elif [[ "$$remote_tag_exists" -eq 1 ]]; then \
		echo "release: ERROR — remote tag $$ver exists but is not local after fetch (network issue?); aborting to prevent divergent local tag at HEAD" >&2; \
		exit 1; \
	else \
		echo "release: creating annotated tag $$ver"; \
		git tag -a -m "Release $$ver" -- "$$ver"; \
	fi; \
	if [[ "$$remote_tag_exists" -eq 0 ]]; then \
		echo "release: pushing tag to origin"; \
		git push origin -- "$$ver"; \
	fi; \
	if gh release view -- "$$ver" >/dev/null 2>&1; then \
		echo "release: GitHub release for $$ver already exists — skipping create"; \
	else \
		echo "release: creating GitHub release with auto-generated notes"; \
		gh release create --generate-notes -- "$$ver"; \
	fi

test-release: ## Run the version-extraction test harness against fixture files
	@bash tests/test_release_extraction.sh
