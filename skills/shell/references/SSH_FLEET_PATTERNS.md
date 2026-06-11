# SSH fleet patterns

**When this fires**: a script probes or remediates many hosts over SSH —
latency sweeps, posture audits, payload push + execute, per-host config fixes.

## Cold-probe hygiene (timing-sensitive probes)

A probe that *measures* login behaviour (latency, PAM stalls, MOTD noise) must
ride a **cold** connection and be bounded **from the outside**:

```bash
PROBE_OPTS=(
    -o ControlMaster=no -o ControlPath=none   # no mux reuse — a warm socket skips
                                              # auth + session setup and measures nothing
    -o BatchMode=yes                          # never hang on a password prompt mid-sweep
    -o ConnectTimeout=5
)
t0=$SECONDS
if timeout 90 ssh "${PROBE_OPTS[@]}" "$host" true; then
    echo "$host login_ok $((SECONDS - t0))s"
else
    echo "$host login_FAIL_or_stall"
fi
```

- **`ControlMaster=no` + `ControlPath=none`** even if your `~/.ssh/config`
  enables multiplexing globally — an inherited warm socket silently turns the
  probe into a no-op measurement.
- **The outer `timeout N` is mandatory.** `ConnectTimeout` bounds only the TCP
  handshake; **post-auth stalls — PAM session setup, slow login shells — are
  invisible to it** and will hang the whole sweep on one sick host.
- Hosts with known intermittent login stalls will *flap* between ok/stall
  across sweeps — that's the fault's signature, not an outage; see
  [INTERMITTENT_FAULT_GATING.md](INTERMITTENT_FAULT_GATING.md) before acting
  on a single probe result.

## The one-login apply mux

When a target's logins are expensive (slow PAM, a far jump path), an apply
path doing gate-probe + `scp` payload + run payload as three separate logins
triples the pain. Instead, let the **first (gate-probe) connection establish a
ControlMaster**; subsequent `scp`/`ssh` ride the socket free:

```bash
MUXDIR="$(mktemp -d)"
MUX_OPTS=(-o ControlMaster=auto -o "ControlPath=$MUXDIR/%r@%h:%p" -o ControlPersist=120)

cleanup_mux() {
    local sock
    for sock in "$MUXDIR"/*; do
        [ -S "$sock" ] || continue
        # ControlPath takes a PATH, not a glob — close each socket individually.
        # The destination token is syntactically required but UNUSED when the
        # given path contains no %-tokens; any placeholder name works.
        ssh -O exit -o "ControlPath=$sock" dummy-host 2>/dev/null || true
    done
    rmdir "$MUXDIR" 2>/dev/null || true
}
trap cleanup_mux EXIT

ssh "${MUX_OPTS[@]}" "$host" 'run-precondition-probe'   # login #1 — pays the cost, opens the master
scp "${MUX_OPTS[@]}" "$PAYLOAD" "$host:/tmp/payload.sh" # rides the socket — free
ssh "${MUX_OPTS[@]}" "$host" 'bash /tmp/payload.sh'     # free
```

Notes:

- `ControlPersist=120` keeps the master alive between commands but
  self-expires if the teardown trap never fires (kill -9, power loss).
- Don't mix the mux opts into *probe* invocations — cold probes and the apply
  mux are opposite requirements; keep two opt arrays.
- The post-apply **fresh-connection check** (lockout discipline,
  [MAINTENANCE_SCRIPT_CONTRACT.md](MAINTENANCE_SCRIPT_CONTRACT.md)) must use
  the cold-probe opts — a check that rides the mux validates the *old*
  session, not the changed login path.

## Jump host + identity separation

```bash
JUMP="${JUMP:-}"                 # e.g. JUMP=ops@jumphost.internal
SSH_OPTS=()
[ -n "$JUMP" ] && SSH_OPTS+=(-J "$JUMP")

PROBE_IDENTITY="${PROBE_IDENTITY:-$HERE/id_probe}"      # read-only automation key
OPERATOR_IDENTITY="${OPERATOR_IDENTITY:-}"              # operator-supplied for --apply
```

- Jump-host via env-driven `-J`, never hard-coded — the same script must run
  from inside and outside the management network.
- **Identity separation**: the probe identity is a low-privilege automation
  key; mutations run under the operator's identity. **Refuse privileged modes
  under the read-only identity** — failing late with a permission error
  mid-mutation is far worse than failing at arg-parse time:

```bash
if [ "$MODE" = "apply" ] && [ -z "$OPERATOR_IDENTITY" ]; then
    echo "refusing --apply under the read-only probe identity; set OPERATOR_IDENTITY" >&2
    exit 1
fi
```

## Hosts-file parser (the per-script scaffold)

```bash
# hosts.txt: "<name> <address>" per line; blank lines + '#' comments ignored
HOSTS=()
while read -r name addr _; do
    case "$name" in ''|'#'*) continue ;; esac
    HOSTS+=("$name=$addr")
done < "$HOSTS_FILE"
[ "${#HOSTS[@]}" -gt 0 ] || { echo "no hosts parsed from $HOSTS_FILE" >&2; exit 1; }
```

## Scaffold duplication: extract at the 5th copy

The hosts-file parser and the SSH-opts blocks get **copied into each script by
design** — operational scripts are self-contained and relocatable (one file to
`scp` to a jump host, no library to ship alongside). That's the right default,
not a smell. But count the copies: at the **5th** duplicated scaffold, extract
a shared `lib.sh` sourced via `$HERE` and accept the relocation constraint
(ship the lib next to the scripts). Earlier extraction buys nothing and costs
the single-file property; later, the copies have drifted and the extraction
becomes a reconciliation project.
