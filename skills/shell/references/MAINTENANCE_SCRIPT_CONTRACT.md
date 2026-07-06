# The maintenance-script contract

**When this fires**: any shell script that mutates a live host — fleet config
remediation, login-path changes, service tuning, firewall edits. The contract
makes the script safe to hand to a tired operator (or a future you) who runs
it without re-reading the source.

## Mode surface

| Mode     | Flag        | Behaviour                                                                                                                                |
| -------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| DRY-RUN  | *(default)* | Read-only. Measures current state, prints the per-target plan. Running with no args must be safe against production.                      |
| Apply    | `--apply`   | Mutating. For risky changes, per-target (`--apply --host <name>`), never fleet-wide in one invocation.                                    |
| Verify   | `--verify`  | Proves the **effect** the fix targets — never "it ran".                                                                                   |
| Revert   | `--revert`  | Undo, where the change is meaningfully reversible (restore the `.bak`, re-enable the line). Omit when revert is a different procedure.    |
| Check    | `--check`   | CI-style staleness probe: exit 0 = posture holds on all targets, non-zero = drift. Suitable for cron/pipeline scheduling.                 |

```text
✅ DO:   --verify re-measures the symptom: time a fresh, un-multiplexed SSH login
         and assert it's back under the threshold the fix promised.
❌ DON'T: --verify greps for the config line --apply wrote. That proves the script
         executed, not that the fault is gone — config can be present and inert
         (wrong file order, service not reloaded, fault cause elsewhere).
```

**Poll the served effect; don't one-shot it.** When `--apply` ends in a *graceful*
reload (`systemctl reload`, `nginx -s reload`, any drain-then-swap) or any change
that takes effect with eventual-consistency lag, the old state can still answer for
a window after the command returns 0 — old workers finish in-flight requests on the
*previous* config before the new ones take over. A single probe fired immediately
after the reload can read the **pre-change** state and report a false failure (or, in
`--apply`, abort a later step that depended on the effect being live). Poll until the
effect is observed or a bounded timeout elapses:

```bash
MAX_TRIES="${MAX_TRIES:-15}"; POLL_S="${POLL_S:-2}"
for attempt in $(seq 1 "$MAX_TRIES"); do
    if probe_shows_new_state; then ok=1; break; fi    # measure the SERVED state
    sleep "$POLL_S"
done
[ "${ok:-0}" = 1 ] || { echo "effect not live after $((MAX_TRIES*POLL_S))s" >&2; exit 1; }
```

The drain window scales with how much the daemon reloads — a proxy with hundreds of
vhosts (config re-parse + name-hash rebuild) can take several seconds to fully cut
over. One-shot probing is the classic intermittent false-negative on busy hosts.

## The interactive precondition-acknowledgement gate

When a script's safe operation depends on **operator-side** preconditions the
script cannot check itself — break-glass/console access verified working
today, a second held SSH session open on each target, a backup taken off-box —
the script must **block** on explicit confirmation **before the first
connection or mutation**:

```bash
confirm_preconditions() {
    # Escape hatch ONLY if unattended use is a designed mode of this script.
    [ "${ALLOW_UNATTENDED:-0}" = "1" ] && return 0
    cat <<'EOF'
PRECONDITIONS — confirm each before this script touches any host:
  [ ] A second SSH session to each target is open and STAYS open until post-checks pass.
  [ ] Out-of-band (console/break-glass) access is verified working TODAY, not "should work".
  [ ] A copy of every file this run edits exists OFF the target.
Type 'yes' to proceed (anything else aborts):
EOF
    local ans
    read -r ans </dev/tty
    [ "$ans" = "yes" ] || { echo "Aborted: preconditions not acknowledged." >&2; exit 1; }
}
```

Three load-bearing rules:

1. **Gate before the first connection or mutation.** A checklist printed while
   the action already runs is decoration, not a gate — this exact failure
   shipped once: the checklist printed post-factum and scrolled by mid-apply,
   acknowledged by nobody. The gate's value is the forced pause *before*
   anything irreversible.
2. **Read from `/dev/tty`, not stdin.** Evidence-log wrappers (next section)
   redirect stdout/stderr through `tee`, and callers often redirect stdin too;
   a bare `read ans` then EOFs instantly or eats piped input and the "gate"
   silently passes. `/dev/tty` reaches the operator's terminal regardless of
   stdio plumbing — and fails loudly when there is no terminal, which is
   correct: an unattended run that hits the gate *should* die unless
   unattended operation was designed in (the env hatch above).
3. **Require the literal `yes`.** Not `y`, not Enter. The token cost is the
   point — it defeats reflex-Enter.

## One target at a time for risky mutations

Never loop a whole fleet through a login-path, PAM, or firewall change in one
`--apply`. Apply to one host, run the post-check (fresh login from a *new*
connection), only then proceed.

```text
✅ DO:   ./remediate.sh --apply --host alpha   # verify, then beta, then ...
❌ DON'T: for h in $(cat hosts.txt); do ./remediate.sh --apply --host "$h"; done
         A bad change now locks you out of N hosts instead of one — and the
         held-session safety net only realistically covers the host you're watching.
```

## Idempotency: safe re-run + no-op fast path

Detect desired state **first**; if already applied, print
`already applied — nothing to do` and exit 0 before any backup/mutation
machinery runs. Re-running a completed rollout must be boring. This also makes
`--apply` resumable mid-fleet after an interruption.

## `$HERE`-relative defaults

```bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${HOSTS_FILE:-$HERE/hosts.txt}"
PAYLOAD="${PAYLOAD:-$HERE/payload.sh}"
```

Siblings resolve relative to the *script*, not the caller's cwd — the script
survives being invoked from anywhere. Corollary: the defaults **re-anchor when
the script is relocated**, so a post-move smoke test must execute past the
preflight (a `--help` run proves nothing about sibling resolution).

## Evidence logs

```bash
LOG="$HERE/run-$(date -u +%Y%m%dT%H%M%SZ).log"   # *.log is git-ignored
exec > >(tee -a "$LOG") 2>&1
echo "== $0 mode=$MODE started $(date -u -Is) =="
```

Every run leaves a timestamped transcript next to the script — the paper trail
for "what exactly did the rollout do on host N". **This wrapper is why the
precondition gate must read `/dev/tty`**: after the `exec`, stdio is owned by
the log plumbing.

**Keep the full stream in the log; filter known-benign floods off the terminal.**
A validator or reload that emits *one benign warning per managed item* (a config
test on a host with hundreds of vhosts, a linter walking thousands of files) can dump
hundreds of lines into the operator's scrollback in a single step — blowing the
terminal buffer and burying the real errors. Don't suppress at the source (you lose
the evidence) and don't let it flood the operator. Tee the **full** stream to the log,
but filter the *named, known-benign* lines off the terminal only:

```bash
# one benign warning per vhost (deprecation notes, hash-size tuning) drowns real errors
readonly NOISE='directive is deprecated|could not build optimal .*_hash|conflicting server name'
exec > >(tee -a "$LOG" | grep --line-buffered -vE "$NOISE") 2>&1
```

The log keeps everything; the terminal shows only what the operator must act on.
Filter by an explicit allow-known-benign list (real errors still surface) — never a
blanket `2>/dev/null`.

## `set -euo pipefail`

Standard prologue on every ops script. One non-obvious interaction: commands
whose non-zero exit is *informative*, not an error (`diff`, `grep` with no
match), need explicit handling (`|| true`, or capture rc in an `if`) or the
script dies on a healthy host.

## Lockout discipline for login-path / SSH changes

Any change that can affect authentication or session setup (PAM, `sshd`
config, firewall rules touching :22):

1. Open and **hold** a second session on the target before `--apply`.
2. After the change, test a **fresh** connection (new TCP, no ControlMaster
   socket — see [SSH_FLEET_PATTERNS.md](SSH_FLEET_PATTERNS.md)). The held
   session reuses pre-change state and proves nothing about new logins.
3. Only after the fresh-connection check passes, close the held session.

## Grep portability hazard

Never build logic on quiet+invert grep (`! grep -qv …`, `grep -qvx …`).
Non-GNU greps — e.g. a box whose `/usr/bin/grep` is ugrep — handle the
quiet+invert combination order-dependently and unreliably. **Positive matches
(`-q`, `-qiE`, `-qx`, `-qF`) are portable**; invert in shell logic, not in
grep flags.

Second trap in the same area: grep's return code can't distinguish an active
config line from a commented one — a commented line still *contains* the
string. Parse line **shape**:

```bash
# ❌ DON'T: "is the module enabled?" via bare substring rc
grep -q 'pam_examplemod\.so' "$f" && state=enabled    # '#session … pam_examplemod.so' matches too

# ✅ DO: distinguish active vs commented vs absent by anchored line shape
if   grep -qE '^[[:space:]]*[^#[:space:]].*pam_examplemod\.so' "$f"; then state=active
elif grep -qE '^[[:space:]]*#.*pam_examplemod\.so'            "$f"; then state=commented
else                                                                      state=absent
fi
```

The three-way state matters: DRY-RUN reports it, `--apply`'s no-op fast path
keys off it, and `--revert` refuses to "un-comment" a line that was never
commented by this script.

## Locate by exact token; refuse on ambiguity

A script that finds the thing it will mutate by matching an **identifier** must match
a whole delimited token, not a substring. A word-boundary regex (`\bname\b`) is *not*
exact-token: punctuation is a word boundary, so `\bexample\.com\b` matches the
`example.com` inside `sub.example.com` — the locator silently targets a *subdomain's*
config when it meant the apex (or any superstring entry). Split on the field
delimiter and compare whole tokens:

```bash
# ❌ DON'T: substring/word-boundary — matches sub.example.com, api.example.com, …
grep -lE 'server_name[^;]*\bexample\.com\b' "$dir"/*

# ✅ DO: whole-token compare (awk splits the directive's value into fields;
#        strip the trailing ';' so the last name on the line still matches)
awk '/^[[:space:]]*server_name/ { for (i=2;i<=NF;i++) { t=$i; sub(/;$/,"",t); if (t=="example.com") f=1 } }
     END { exit(f?0:1) }' "$file"
```

And when the located target turns out to be **shared** — the file/block also serves
unrelated entries, so mutating or disabling it would take out bystanders — the script
must **refuse and exit non-zero with a clear message** ("X is shared with Y/Z; split
it or apply by hand"), not guess. A blind operator-side run is exactly where a
greedy match silently does the wrong thing; the fail-safe converts that into a stop.
(This is the locate-side twin of the precondition gate: when the script can't be sure
it's about to touch *only* the intended target, it doesn't proceed.)

## Detect the mechanism; don't hardcode one variant

The same capability ships under different unit/tool names across installs, and a check
that asserts **one** name false-FAILs (or false-PASSes) on the others. The canonical
case: a scheduled certificate renewer is `certbot.timer` on the distro package,
`snap.certbot.renew.timer` on the snap, and `/etc/cron.d/certbot` on older setups —
a `--verify` that only tests `systemctl is-active certbot.timer` reports "renewal not
scheduled" on a perfectly healthy snap host. Probe for **any** known variant:

```bash
renewal_scheduled() {            # echo which mechanism; return 0 if any is active
  systemctl is-active --quiet certbot.timer            && { echo certbot.timer; return 0; }
  systemctl is-active --quiet snap.certbot.renew.timer && { echo snap.certbot.renew.timer; return 0; }
  [ -f /etc/cron.d/certbot ]                           && { echo cron.d/certbot; return 0; }
  return 1
}
```

Same shape for "which firewall is active" (ufw / firewalld / nftables / raw iptables),
"which init owns this service", "apt vs dnf vs apk". The DRY-RUN should *report the
detected variant* so the operator sees which mechanism the host actually uses.

## Remote black-box `--verify`: assert the POSITIVE code, so an unreachable target fails CLOSED

A verify script that probes a service over the network (`curl … || true` to tolerate a down target)
captures **`000`** in the status var when curl can't connect. The trap is asserting the *negative*:

```bash
code="$(curl -s -o /dev/null -w '%{http_code}' … || true)"   # 000 when unreachable
[ "$code" != 404 ] && ok "path served"      # ❌ 000 != 404 → FALSE-PASSES while the edge is DOWN
```

A whole edge can be offline and this check reports green. **Assert the positive expected code** so
`000` (and a wrong code) both fail:

```bash
[ "$code" = 200 ] && ok "path served" || no "want 200 — broken, or edge unreachable"   # ✅ fails closed
```

Same discipline as `--verify` re-measuring the symptom: a black-box probe must **prove the good state**
(`= 200`), never merely **fail to observe the bad one** (`!= 404`). `= 404` assertions are inherently
safe (`000 ≠ 404` correctly fires the failure); it's the negated ones that false-pass.

### Load-testing a rate-limit needs CONCURRENCY (a serial loop won't trip it)

To assert a rate-limiter engages, a **sequential** `curl` loop over the network is **slower than the
limit** (each request pays RTT + a fresh TLS handshake), so it never drains the burst → false "0 got
429". Fire the requests **concurrently and in volume** (drain `burst` faster than `average` refills):

```bash
codes="$(seq 1 500 | xargs -P50 -n1 sh -c 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 "<url>" 2>/dev/null' _)"
n429="$(printf '%s\n' "$codes" | grep -c '^429$' || true)"   # expect > 0
```

The trailing `_` gives `sh -c` a `$0` so the xargs-fed item isn't interpolated into the command.
Single-quote the `sh -c` script so the *outer* shell can't expand anything in it (a real URL's `$`
or query string stays literal until the inner `sh` sees it). Gate
`RATELIMIT_PROBE=1` (it floods the target; on a shared/global limiter it briefly throttles *all*
clients — run against a sandbox / off-hours).

### `openssl x509` has no `-notBefore` flag

To read a served cert's validity window: `openssl x509 -noout -startdate` (prints `notBefore=…`) or
`-dates` (both `notBefore=`/`notAfter=`). **`-notBefore` is not an option** — it errors `x509: Unknown
option`. Cheap to get wrong when hand-writing a "did the cert change?" (reused-vs-re-issued) check.
