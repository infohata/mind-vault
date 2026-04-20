#!/usr/bin/env bash
# sprint-auto-bootstrap.sh — project-agnostic worktree bootstrap for /sprint-auto
#
# This is the CANONICAL implementation. Projects invoke it via a thin wrapper at
# their own tools/sprint-auto-bootstrap.sh that locates this file and execs into
# it. See mind-vault/skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper
# for the wrapper template.
#
# Why wrappers, not symlinks: a missing or misplaced mind-vault surfaces as a
# clear, actionable error from the wrapper; a broken symlink gives "no such
# file or directory" with no diagnostic path.
#
# Contract: see mind-vault/skills/sprint-auto/references/worktree-lifecycle.md
#
# Invocation (from inside a git worktree, via the wrapper):
#   ./tools/sprint-auto-bootstrap.sh <slug> <idea_number>
#
# Exit 0 only when the stack is up, all services are running, and the optional
# project-local smoke test has passed. The /sprint-auto skill keys off exit code.
#
# Project-local customisation goes in tools/sprint-auto-hooks.sh (optional).
# Declare bash functions `post_up_init` and/or `smoke_test` there — this script
# sources the file and calls them after `docker compose up` if present.

set -euo pipefail

slug="${1:?usage: sprint-auto-bootstrap.sh <slug> <idea_number>}"
idea_number="${2:?usage: sprint-auto-bootstrap.sh <slug> <idea_number>}"

log() { echo "[sprint-auto-bootstrap] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Default smoke: every configured service must be in running state.
# Defined early so both the hooks path and the no-hooks path can call it.
default_smoke_test() {
    local expected running
    expected=$(docker compose config --services | wc -l)
    running=$(docker compose ps --services --filter status=running | wc -l)
    if [[ "$expected" != "$running" ]]; then
        log "Service count mismatch: $running / $expected running"
        docker compose ps >&2
        return 1
    fi
    return 0
}

rand_hex() {
    if command -v openssl >/dev/null; then
        openssl rand -hex 16
    else
        date +%s%N | sha256sum | head -c 32
    fi
}

# ---------------------------------------------------------------------------
# 0. Preflight — refuse obviously unsafe conditions
# ---------------------------------------------------------------------------

command -v docker >/dev/null       || die "docker not found on PATH"
command -v jq >/dev/null           || die "jq not found (required for compose config parsing)"
docker compose version >/dev/null  || die "docker compose plugin not available"

[[ -f .env.template ]]             || die ".env.template missing — cannot bootstrap .env safely"
[[ ! -f .env ]]                    || die ".env already exists in worktree — refusing to overwrite"
[[ ! -f docker-compose.override.yml ]] || die "docker-compose.override.yml already exists — refusing to overwrite"

# Heuristic: worktree's dirname should match the *-auto-<slug> convention the
# sprint-auto skill uses. Soft check — warn, don't die.
cwd_base="$(basename "$PWD")"
case "$cwd_base" in
    *-auto-*) : ;;
    *) log "WARN: cwd does not match *-auto-<slug> naming — proceeding anyway" ;;
esac

log "slug=$slug idea=$idea_number cwd=$PWD"

# ---------------------------------------------------------------------------
# 1. Generate worktree-local .env from template, sentinel-replace credentials
# ---------------------------------------------------------------------------

log "Generating .env from .env.template with sentinel credentials"
cp .env.template .env

# Credential-shaped keys → sentinel.
# Matches *_KEY, *_SECRET, *_TOKEN, *_PASSWORD, *_PASS, *_PWD, *_CREDENTIAL.
sed -i -E 's/^([A-Z0-9_]*_(KEY|SECRET|TOKEN|PASSWORD|PASS|PWD|CREDENTIAL))=.*/\1=test-not-a-real-key/' .env

# Entropy-sensitive fields → fresh random per worktree.
sed -i -E "s/^SECRET_KEY=.*/SECRET_KEY=test-$(rand_hex)/" .env
sed -i -E "s/^([A-Z0-9_]*(SALT|HMAC))=.*/\1=test-$(rand_hex)/" .env

# *_URL values with embedded user:pass → neutralise.
# Projects that need inter-service URLs should set them in post_up_init.
sed -i -E 's|^([A-Z0-9_]+_URL)=([a-z]+)://[^:/]+:[^@]+@.*|\1=\2://test:test-not-a-real-key@localhost/test|' .env

log ".env generated (credentials sentinel-replaced)"

# ---------------------------------------------------------------------------
# 2. Generate docker-compose.override.yml with port offset
# ---------------------------------------------------------------------------

port_offset=$(( 10000 + (10#$idea_number % 100) * 100 ))
log "Computing port offset: +$port_offset"

# `docker compose config --format json` resolves variable substitution and
# merges any existing project-owned overrides into the final spec.
# Keep stderr OUT of the JSON stream — compose emits warnings (undefined vars,
# deprecations, orphan containers) that would corrupt jq parsing if merged.
compose_err=$(mktemp)
if ! compose_json=$(docker compose config --format json 2>"$compose_err"); then
    log "docker compose config failed:"
    cat "$compose_err" >&2
    rm -f "$compose_err"
    die "check compose file + .env"
fi
rm -f "$compose_err"

# Compose normalises port entries into objects: {mode, target, published, protocol, host_ip}
# regardless of source syntax. One service block per service with ports.
override_yaml=$(echo "$compose_json" | jq -r --argjson offset "$port_offset" '
  .services
  | to_entries
  | map(select(.value.ports != null and (.value.ports | length) > 0))
  | if length == 0 then
      "# No services with host-port bindings — no remapping needed\n"
    else
      "# Auto-generated by sprint-auto-bootstrap.sh — do not commit\nservices:\n" +
      (map(
        "  " + .key + ":\n    ports: !override\n" +
        (.value.ports
          | map(
              "      - \"" +
              (.host_ip // "127.0.0.1") + ":" +
              ((.published | tonumber + $offset) | tostring) + ":" +
              (.target | tostring) +
              (if (.protocol // "tcp") != "tcp" then "/" + .protocol else "" end) +
              "\""
            )
          | join("\n"))
      ) | join("\n"))
    end
')

printf '%s\n' "$override_yaml" > docker-compose.override.yml
log "Wrote docker-compose.override.yml"

# ---------------------------------------------------------------------------
# 3. Bring up the stack
# ---------------------------------------------------------------------------

log "docker compose up -d --wait"
up_log=$(mktemp)
if ! docker compose up -d --wait >"$up_log" 2>&1; then
    log "Tail of 'docker compose up' output:"
    tail -n 30 "$up_log" >&2
    rm -f "$up_log"
    die "stack failed to come up"
fi
rm -f "$up_log"

# ---------------------------------------------------------------------------
# 4. Project-local hooks (optional) + smoke test
# ---------------------------------------------------------------------------

hooks_file="tools/sprint-auto-hooks.sh"

if [[ -f "$hooks_file" ]]; then
    log "Sourcing $hooks_file"
    # shellcheck disable=SC1090
    source "$hooks_file"

    if declare -f post_up_init >/dev/null; then
        log "Running post_up_init (from hooks)"
        post_up_init || die "post_up_init failed"
    else
        log "No post_up_init defined in hooks — skipping"
    fi

    if declare -f smoke_test >/dev/null; then
        log "Running smoke_test (from hooks)"
        smoke_test || die "smoke_test failed"
    else
        log "No smoke_test defined in hooks — using default (compose ps sanity)"
        default_smoke_test || die "default smoke test failed"
    fi
else
    log "No $hooks_file — skipping post-up init; using default smoke (compose ps sanity)"
    default_smoke_test || die "default smoke test failed"
fi

log "Bootstrap OK — slug=$slug idea=$idea_number offset=+$port_offset"
