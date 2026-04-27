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
#   ./tools/sprint-auto-bootstrap.sh <slug> <idea_number> --port-offset N
#
# Exit 0 only when the stack is up, all services are running, and the optional
# project-local smoke test has passed. The /sprint-auto skill keys off exit code.
#
# Project-local customisation goes in tools/sprint-auto-hooks.sh (optional).
# Declare bash functions `post_up_init` and/or `smoke_test` there — this script
# sources the file and calls them after `docker compose up` if present.
#
# The --port-offset N override is used by the v3.1 integration phase: the
# integration worktree always uses +30000, regardless of what the per-batch
# slug's idea-number-derived offset would have been. See
# skills/sprint-auto/references/integration-stage.md for the integration
# worktree's lifecycle and the +30000 convention. Without --port-offset,
# the legacy per-IDEA formula `10000 + (idea_number % 100) * 100` is used
# (capped at +19900; the integration phase's +30000 is unreachable via
# that formula, hence the explicit flag).

set -euo pipefail

slug="${1:?usage: sprint-auto-bootstrap.sh <slug> <idea_number> [--port-offset N]}"
idea_number="${2:?usage: sprint-auto-bootstrap.sh <slug> <idea_number> [--port-offset N]}"
shift 2

# Optional flags
port_offset_override=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port-offset)
            port_offset_override="${2:?usage: --port-offset N}"
            shift 2
            ;;
        --port-offset=*)
            port_offset_override="${1#--port-offset=}"
            shift
            ;;
        *)
            echo "[sprint-auto-bootstrap] ERROR: unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

log() { echo "[sprint-auto-bootstrap] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Input validation — refuse anything that could interact badly with sed/sh/jq
# further down. slug lands inside filenames and a compose override (via jq
# --argjson context only, not directly, but still tightened). idea_number
# enters bash arithmetic and sed format strings; non-digit input would
# produce confusing errors or corrupt substitutions.
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
    || die "slug must match ^[a-z0-9][a-z0-9-]*$ (got: $slug)"
[[ "$idea_number" =~ ^[0-9]+$ ]] \
    || die "idea_number must be all-digits (got: $idea_number)"
if [[ -n "$port_offset_override" ]]; then
    [[ "$port_offset_override" =~ ^[0-9]+$ ]] \
        || die "--port-offset must be all-digits (got: $port_offset_override)"
    # 9300 (ES transport) + offset must stay below the registered-port ceiling
    # 49151 (recommended) for safety; refuse offsets that risk port-space
    # overflow or collision with the ephemeral-port range (Linux default
    # 32768-60999). The integration phase's +30000 fits cleanly: max remapped
    # port becomes 9300+30000 = 39300, well in registered range.
    if (( port_offset_override > 39851 )); then
        die "--port-offset $port_offset_override is too high; max remapped port (9300+offset) must stay <= 49151. See skills/sprint-auto/references/integration-stage.md § Port-offset math."
    fi
fi

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
# First pattern must precede the generic credential sentinel above when the
# order ever gets reshuffled — but since the generic sentinel already ran,
# those values are currently `test-not-a-real-key` and get overwritten here.
# Matches SECRET_KEY (bare) and common prefixed variants like DJANGO_SECRET_KEY,
# APP_SECRET_KEY — anything ending in SECRET_KEY at start of line.
sed -i -E "s|^([A-Z0-9_]*SECRET_KEY)=.*|\1=test-$(rand_hex)|" .env
sed -i -E "s#^([A-Z0-9_]*(SALT|HMAC))=.*#\1=test-$(rand_hex)#" .env

# *_URL values with embedded user:pass → neutralise.
# Projects that need inter-service URLs should set them in post_up_init.
sed -i -E 's|^([A-Z0-9_]+_URL)=([a-z]+)://[^:/]+:[^@]+@.*|\1=\2://test:test-not-a-real-key@localhost/test|' .env

log ".env generated (credentials sentinel-replaced)"

# ---------------------------------------------------------------------------
# 2. Generate docker-compose.override.yml with port offset
# ---------------------------------------------------------------------------

if [[ -n "$port_offset_override" ]]; then
    port_offset="$port_offset_override"
    log "Using explicit port offset: +$port_offset (--port-offset)"
else
    port_offset=$(( 10000 + (10#$idea_number % 100) * 100 ))
    log "Computing port offset from idea_number: +$port_offset"
fi

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
#
# Network handling: if the parent compose pins `networks.<name>.ipam.config[*].subnet`
# or any service's `networks.<name>.ipv4_address`, two worktree stacks trying to use
# the same compose project collide at network-create time:
#   "invalid pool request: Pool overlaps with other one on this address space"
# We use `!reset` (compose v2.24+) to drop the parent's IPAM pin + per-service IP
# pin so Docker auto-assigns a fresh subnet from its default pool. Cleaner than
# hand-computing a non-colliding /16, and robust to arbitrary parent compose
# configurations — no hardcoded subnet assumptions.
override_yaml=$(echo "$compose_json" | jq -r --argjson offset "$port_offset" '
  # Per-service: collect (1) port override list, (2) network names to reset if
  # that service pinned any ipv4_address. Empty => no block for this service.
  (.services // {}) as $svcs
  | ($svcs | to_entries | map(
      . as $entry
      | {
          key,
          ports_block: (
            if ($entry.value.ports // []) | length > 0 then
              "    ports: !override\n" +
              ($entry.value.ports | map(
                "      - \"" +
                (if (.host_ip // "") == "" then "127.0.0.1" else .host_ip end) + ":" +
                ((.published | tonumber + $offset) | tostring) + ":" +
                (.target | tostring) +
                (if (.protocol // "tcp") != "tcp" then "/" + .protocol else "" end) +
                "\""
              ) | join("\n"))
            else "" end
          ),
          networks_reset_block: (
            if ($entry.value.networks // {})
               | to_entries
               | any(.value.ipv4_address // null)
            then
              "    networks: !reset\n" +
              ($entry.value.networks | keys | map("      - " + .) | join("\n"))
            else "" end
          )
        }
      | select(.ports_block != "" or .networks_reset_block != "")
    )) as $svc_blocks
  # Top-level: networks that pinned an IPAM subnet need an ipam !reset.
  | ((.networks // {}) | to_entries
     | map(select(.value.ipam.config[0].subnet // null))
     | map(.key)) as $nets_with_ipam
  | if ($svc_blocks | length) == 0 and ($nets_with_ipam | length) == 0 then
      "# No services with host-port bindings or pinned network IPAM — no overrides needed\n"
    else
      "# Auto-generated by sprint-auto-bootstrap.sh — do not commit\n" +
      (if ($svc_blocks | length) > 0 then
        "services:\n" +
        ($svc_blocks | map(
          "  " + .key + ":\n" +
          .ports_block +
          (if .ports_block != "" and .networks_reset_block != "" then "\n" else "" end) +
          .networks_reset_block
        ) | join("\n"))
      else "" end) +
      (if ($nets_with_ipam | length) > 0 then
        (if ($svc_blocks | length) > 0 then "\n\n" else "" end) +
        "networks:\n" +
        ($nets_with_ipam | map("  " + . + ":\n    ipam: !reset null") | join("\n"))
      else "" end)
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
