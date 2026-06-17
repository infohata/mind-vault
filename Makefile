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

.PHONY: help release extract-version test-release test-claude test

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
        # TOML allows both "..." and '...' for string values.
        printf '%s\n' "$$line" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*/\1/'
        exit 0
    fi
fi

if [[ -f package.json ]]; then
    # Match /wrap Step 4b semantics — only adopt package.json's version
    # when jq is present AND `jq -e '.version'` succeeds. Otherwise fall
    # through to the next source (Cargo.toml / setup.py / CHANGELOG.md).
    # User keeps the explicit VERSION= override as the escape hatch when
    # auto-detect picks the wrong source.
    if command -v jq >/dev/null 2>&1; then
        if v=$$(jq -er '.version' package.json 2>/dev/null); then
            printf '%s\n' "$$v"
            exit 0
        fi
    fi
fi

if [[ -f Cargo.toml ]]; then
    line=$$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=' Cargo.toml || true)
    if [[ -n "$$line" ]]; then
        # TOML allows both "..." and '...' for string values.
        printf '%s\n' "$$line" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*/\1/'
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
    # Require MAJOR.MINOR (a dot) so a bare milestone banner like `## v5`
    # placed above the real `## v5.0.0` release header is SKIPPED, not picked
    # up by grep -m1. Keeps `make release` from ever tagging a truncated `v5`.
    line=$$(grep -m1 -E '^## ([vV][0-9]+\.[0-9]|\[[0-9]+\.[0-9])' CHANGELOG.md || true)
    if [[ -n "$$line" ]]; then
        case "$$line" in
            "## v"*|"## V"*) printf '%s\n' "$$line" | sed -E 's/^## ([vV][^ ]+).*/\1/' ;;
            "## ["*)         printf '%s\n' "$$line" | sed -E 's/^## \[([^]]+)\].*/\1/' ;;
            # Defensive default — the grep regex currently constrains matches
            # to forms the case branches cover, but a future regex change
            # could open a gap. Fail loud rather than silently exit 0 with
            # empty stdout.
            *) echo "version-extract: CHANGELOG.md matched grep but no case branch fired for line: $$line — broaden the case statement to keep up with the grep regex" >&2
               exit 1 ;;
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
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "release: ERROR — \`gh\` CLI not on PATH; install GitHub CLI and authenticate (\`gh auth login\`) before running \`make release\`" >&2; \
		echo "release: hint: the tag step alone (\`git tag -a -m 'Release v<N>' -- v<N> && git push origin -- v<N>\`) works without gh, but skips the GitHub Release surface" >&2; \
		exit 1; \
	fi; \
	ver=$$(bash -c "$$EXTRACT_VERSION_SH"); \
	if [[ -z "$$ver" ]]; then \
		echo "release: extract-version returned empty; aborting" >&2; \
		exit 1; \
	fi; \
	echo "release: version = $$ver"; \
	echo "release: fetching tags from origin (so local-state checks see remote tags)"; \
	git fetch origin --tags --quiet 2>/dev/null || echo "release: warning — git fetch --tags failed (continuing with local state)"; \
	ls_remote_rc=0; \
	ls_remote_out=$$(git ls-remote --tags origin "refs/tags/$$ver" 2>&1) || ls_remote_rc=$$?; \
	if (( ls_remote_rc != 0 )); then \
		echo "release: ERROR — \`git ls-remote origin\` failed (rc=$$ls_remote_rc); cannot reliably determine whether remote tag $$ver exists. Output:" >&2; \
		printf '  %s\n' "$$ls_remote_out" >&2; \
		echo "release: hint: check network/auth (\`git push origin --dry-run\`) and re-run. Aborting to avoid creating a local tag without remote visibility." >&2; \
		exit 1; \
	fi; \
	if printf '%s' "$$ls_remote_out" | grep -q .; then \
		remote_tag_exists=1; \
		echo "release: remote tag $$ver already exists on origin — skipping push"; \
	else \
		remote_tag_exists=0; \
	fi; \
	if git rev-parse --verify --quiet "refs/tags/$$ver" >/dev/null; then \
		echo "release: local tag $$ver already exists — skipping tag create"; \
		local_tag_sha=$$(git rev-parse "refs/tags/$$ver^{commit}"); \
		if [[ "$$remote_tag_exists" -eq 1 ]]; then \
			remote_tag_sha=$$(git ls-remote --tags origin "refs/tags/$$ver" "refs/tags/$$ver^{}" 2>/dev/null | awk 'END {print $$1}'); \
			if [[ -n "$$remote_tag_sha" && "$$local_tag_sha" != "$$remote_tag_sha" ]]; then \
				echo "release: ERROR — local tag $$ver points at $$local_tag_sha but origin's $$ver points at $$remote_tag_sha; aborting to surface tag divergence (git fetch --tags won't overwrite existing local tags)" >&2; \
				echo "release: hint: delete the stale local tag (\`git tag -d $$ver\`) then re-run; the next fetch will pick up the remote tag cleanly" >&2; \
				exit 1; \
			fi; \
		else \
			head_sha=$$(git rev-parse HEAD); \
			if [[ "$$local_tag_sha" != "$$head_sha" ]]; then \
				echo "release: ERROR — local tag $$ver points at $$local_tag_sha but HEAD is $$head_sha; aborting to prevent publishing a stale local tag" >&2; \
				echo "release: hint: delete the stale local tag (\`git tag -d $$ver\`) and re-run, or use \`VERSION=<different>\` to tag a new version" >&2; \
				exit 1; \
			fi; \
		fi; \
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

test-claude: ## Run the claude adapter material-surfacing + false-CLEAN-gate tests (IDEA-022)
	@bash tests/test_claude_material_surfacing.sh

test: test-release test-claude ## Run all test harnesses
