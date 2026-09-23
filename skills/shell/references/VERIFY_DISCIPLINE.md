# Verify discipline — proving a maintenance script worked

**Fires when** writing the `--verify` half of a maintenance script, a post-change smoke test, or
any check whose job is to prove a change took effect. The mode surface and the rule that
`--verify` proves the **effect**, never "it ran", live in
[`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md); this file is the craft of
making that proof honest: assert the positive, break the target rather than the input, check the
exact file you changed, and prove the instrument can see a hit before trusting a zero.

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
# opt-in: this floods the target, and a shared/global limiter throttles ALL clients meanwhile
# not opted in = COULD-NOT-RUN, which a verify must never score as a pass
[ "${RATELIMIT_PROBE:-}" = 1 ] || { echo "COULD-NOT-RUN: set RATELIMIT_PROBE=1 to run the flood probe" >&2; exit 2; }
# the URL comes from the environment, never edited into shell source
: "${PROBE_URL:?set PROBE_URL to the target URL}"; export PROBE_URL
codes="$(seq 1 500 | xargs -P50 -n1 sh -c 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 "$PROBE_URL" 2>/dev/null || true' _)"
n429="$(printf '%s\n' "$codes" | grep -c '^429$' || true)"   # grep -c exits 1 on a zero count
[ "$n429" -gt 0 ] || { echo "FAIL: 0 of 500 requests got 429 — limiter not engaged, or probe too slow" >&2; exit 1; }
```

The URL is supplied in the environment (`PROBE_URL='…' RATELIMIT_PROBE=1 ./probe.sh`, or read
from a file) and reaches the inner `sh` only as a variable expanded inside double quotes, so a `$`,
backtick or quote in a real query string stays data at both levels. Pasting it into the block
instead is injectable twice: into the inner `sh -c` program text, and — through an apostrophe in
the URL — into the outer shell's own quoted assignment. The trailing `_` fills `sh -c`'s `$0` slot, so the
xargs-fed token lands in `$1`, unused here (`seq` only drives the request *count*). The inner
`|| true` keeps one timed-out `curl` (rc ≠ 0 → `xargs` rc 123) from killing a strict-mode caller
mid-probe; failed requests still surface as `-w`'s `000` lines. The opt-in guard is part of the
block, not advice beside it, and a skipped probe exits non-zero as COULD-NOT-RUN — a verify that
did not run must not report green
([`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) § An assertion that
COULD NOT run). Run it against a sandbox or off-hours.

### `openssl x509` has no `-notBefore` flag

To read a served cert's validity window: `openssl x509 -noout -startdate` (prints `notBefore=…`) or
`-dates` (both `notBefore=`/`notAfter=`). **`-notBefore` is not an option** — it errors `x509: Unknown
option`. Cheap to get wrong when hand-writing a "did the cert change?" (reused-vs-re-issued) check.

## Test the operation, not its guard — break the TARGET, not the input

To prove an error path works, the failure has to land **at the stage you mean to test**. Feeding the
script bad *input* usually trips an earlier precondition, so the stage never executes and the test
passes while proving nothing.

A real instance: to test that a failed mid-apply install restores the previous file, the payload was
made unreadable (`chmod 000`). That failed **pre-flight** — the apply never started, the target was
never touched, and "restored correctly" was vacuously true. The test was reported as a pass.

The version that actually exercised the path made the **target** unwritable instead, so pre-flight
passed, step 3 installed, step 4 failed, and the restore ran for real.

```bash
# ❌ DON'T: breaks the input -> dies at validation, later stages never run
chmod 000 "$SRC/payload"

# ✅ DO: input is valid, so we reach the stage under test; the TARGET is what fails
chmod 555 "$APP/lib"      # install of file 2 fails; assert file 1 was rolled back
```

Assert on **observable end state**, not on the script's own exit code: capture the target's checksum
before, induce the failure, and compare after. And assert the intermediate temp files are gone —
a restore that leaves `*.new.$$` behind is a half-finished operation.

## Error paths obey the same contract as the happy path

Whatever discipline the success path uses — atomic rename, lint-before-swap, permission preservation
— **the restore-on-failure path must use it too.** It is the path that runs while the system is
already in a bad state, and it is the one nobody exercises.

The recurring shape: an installer stages to a `mktemp` sibling of the target, lints it, then `mv`s it (a single
`rename(2)`, so no reader ever sees a partial file) — and then its own failure branch restores with a
plain `cp` **directly over the live file**, reintroducing exactly the torn-read hazard the design
existed to prevent.

```bash
restore_atomic() {            # $1 = backup, $2 = live target
    local tmp
    # mktemp in the target's own directory: same filesystem, so the mv stays one rename(2);
    # an unpredictable name, so nobody can pre-plant a symlink there (never "$2.restore.$$")
    tmp=$(mktemp "$2.restore.XXXXXX") || return 1
    if cp -p -- "$1" "$tmp" && mv -f -- "$tmp" "$2"; then
        return 0
    fi
    rm -f -- "$tmp"; return 1
}
```

Register `$tmp` with the script's composed cleanup trap as well if a signal could land between the
`mktemp` and the `mv` — see [`CLEANUP_TRAPS_AND_LOCKING.md`](CLEANUP_TRAPS_AND_LOCKING.md).

Three more properties for a `--rollback` mode:

- **Copy the backup, never move it.** A `mv` consumes the only copy, so a second rollback has nothing
  to restore.
- **Validate the backup before installing it** (`php -l`, `nginx -t`, whatever applies). Restoring a
  corrupt backup turns a bad deploy into an outage.
- **A rollback restores the file's prior MODE too.** If the deploy also tightened permissions, rolling
  back re-loosens them. Fix permissions *before* the deploy so the backup captures the good mode.

## Verify the file you edited — never a glob

A verification step that fails for a reason unrelated to your change is worse than no verification,
because it reads as a failure *of your change*.

```bash
# ❌ DON'T: pulls in siblings you never touched; one of them has been broken since 2021,
#           the && short-circuits, and the real check never runs
php -l "$APP"/config_*.php && run_verify

# ✅ DO: assert on exactly the file that was modified
php -l "$APP/config_${SITE}.php" && run_verify
```

The instance behind this: the glob hit an unrelated tenant config with a five-year-old syntax error.
The lint failed, the `&&` short-circuited, the verify never printed — and the edit had in fact landed
correctly. Minutes were spent investigating a change that was fine.

Corollary: in a shared tree, **a red lint over a glob may be pre-existing.** Check the file's mtime
before treating it as a regression you introduced.

## A zero is only evidence if the method can produce a non-zero

"We found none" is worthless without a **positive control**: the same query, same parser, same log
files, run against something known to be present. Ship the control in the same output.

```bash
# the question — grep -c exits 1 on a zero count; under set -e that would end the
# script before the control below ever runs
hits=$(grep -c '/api/target_endpoint' "$LOG" || true); echo "target hits: $hits"   # -> 0

# the control, SAME method: what IS being hit? (awk, not head: no SIGPIPE under pipefail)
awk -F'"' '{split($2,a," "); print a[2]}' "$LOG" | cut -d'?' -f1 | sort | uniq -c | sort -rn | awk 'NR <= 15'
```

If the control lists busy endpoints and the target is absent, the zero is real. **If the control is
also empty, the instrument is broken — not the traffic.** This generalises past logs: any "no
matches / no findings / no differences" claim should carry evidence that the method can produce a
hit.

Related failure this prevents: a filter that hides what it looks for — counting `POST`s for an API
that creates over `GET` returns a confident, wrong zero.

## Prove a log line LANDS before letting the log inform a decision

Before any decision rests on "the log is empty", write a line and see it arrive — **as the user the
runtime runs as, on every host.**

The trap is that a language's default log destination is not a property of the language, it is a
property of the host's config. Same code, two hosts: one has an explicit `error_log` path set and
records everything; the other has it unset, so output goes to the service manager's log and is
effectively discarded. The host that swallowed the messages carried ~98% of the traffic — and the
resulting silence would have read as *"no differences found"*.

Two rules:

1. **Write to an explicit path** the deployment controls, identical on every host, rather than
   inheriting whatever the runtime defaults to. Fall back to the default logger if that write fails —
   losing the *destination* is survivable, losing the *message* silently is not.
2. **Smoke-test it as the runtime user**, because the log directory is usually not writable by that
   user (`root:syslog` on Debian/Ubuntu), and the file must be pre-created:

```bash
# create only when absent — install over an existing log would truncate its history
[ -e /var/log/<app>.log ] || sudo install -o www-data -g adm -m 640 /dev/null /var/log/<app>.log
sudo chown www-data:adm /var/log/<app>.log && sudo chmod 640 /var/log/<app>.log
marker="deploy-smoke-$(hostname | tr -cd 'A-Za-z0-9.-')-$$-$(date +%s)"   # unique, source-safe chars only
# pass it as data (environment), never spliced into the -e source
sudo -u www-data env SMOKE_MARKER="$marker" <runtime> -e 'log(getenv("SMOKE_MARKER"))'
sleep 1                                                   # let an async logger flush
sudo grep -F -- "$marker" /var/log/<app>.log \
  || { echo "FAIL: marker never landed" >&2; exit 1; }    # on EVERY host
```

Also check **timezone** before correlating across hosts: two boxes with the same system zone can
still stamp differently if the runtime overrides it, so the same instant appears hours apart. Emit
timestamps **with the offset** (ISO-8601 `date('c')`-style) and entries stay unambiguous and sortable
regardless.

Related: [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) ·
[`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) (read-only checks
that report success without having looked) ·
[`GREEN_RUN_UNIVERSE_TOO_SMALL.md`](GREEN_RUN_UNIVERSE_TOO_SMALL.md) (a check that ran honestly but
could not see the defect).
