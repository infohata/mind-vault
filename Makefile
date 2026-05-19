# mind-vault — repo-root Makefile
#
# IDEA-003 (release automation): `make release` collapses the post-merge
# tag + push + gh-release sequence into one command. Version-extraction
# honours the six sources `/wrap` Step 4b detects (VERSION, pyproject.toml,
# package.json, Cargo.toml, setup.py, CHANGELOG.md `## v<N>` / `## [<N>]`).
# Pass VERSION=v<N> to override auto-detection — required for projects
# whose CHANGELOG header version differs from the intended tag (mind-vault
# itself: CHANGELOG `## v4` but tags are `v4.0.1`, `v4.0.2`, ...).

SHELL := /usr/bin/env bash
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
    if v=$$(jq -er '.version' package.json 2>/dev/null); then
        printf '%s\n' "$$v"
        exit 0
    fi
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
    line=$$(grep -m1 -E '^## (v[0-9]|\[[0-9])' CHANGELOG.md || true)
    if [[ -n "$$line" ]]; then
        case "$$line" in
            "## v"*) printf '%s\n' "$$line" | sed -E 's/^## (v[^ ]+).*/\1/' ;;
            "## ["*) printf '%s\n' "$$line" | sed -E 's/^## \[([^]]+)\].*/\1/' ;;
        esac
        exit 0
    fi
fi

echo "release: no version source found (looked for VERSION, pyproject.toml, package.json, Cargo.toml, setup.py, CHANGELOG.md '## v<N>' or '## [<N>]' header) and no VERSION= override given" >&2
exit 1
endef
export EXTRACT_VERSION_SH

help: ## Show this help message
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

extract-version: ## Print the version `release` would tag (VERSION=v<N> overrides auto-detect)
	@bash -c "$$EXTRACT_VERSION_SH"

release: ## Tag + push + GH-release the current version (VERSION=v<N> overrides auto-detect)
	@ver=$$(bash -c "$$EXTRACT_VERSION_SH"); \
	if [[ -z "$$ver" ]]; then \
		echo "release: extract-version returned empty; aborting" >&2; \
		exit 1; \
	fi; \
	echo "release: version = $$ver"; \
	if git rev-parse --verify --quiet "refs/tags/$$ver" >/dev/null; then \
		echo "release: tag $$ver already exists — skipping (re-run with VERSION=<new> to tag a different version)"; \
		exit 0; \
	fi; \
	echo "release: creating annotated tag $$ver"; \
	git tag -a "$$ver" -m "Release $$ver"; \
	echo "release: pushing tag to origin"; \
	git push origin "$$ver"; \
	echo "release: creating GitHub release with auto-generated notes"; \
	gh release create "$$ver" --generate-notes

test-release: ## Run the version-extraction test harness against fixture files
	@bash tests/test_release_extraction.sh
