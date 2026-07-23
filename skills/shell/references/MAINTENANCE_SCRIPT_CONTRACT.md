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

## A recovery recipe must be RUNNABLE in the session that prints it

A guard's entire value is the recipe it hands over. Its characteristic failure is not being wrong
about the diagnosis — it is being **plausible but unusable**: advice that reads correctly, gets
copy-pasted at the worst possible moment, and fails. Every instance below shipped, was reviewed, and
still had to be found by executing it:

- **Wrong identity.** A script that guards `[ "$(id -u)" -ne 0 ]` — i.e. *knows* it is unprivileged —
  then emits `sudo rm -rf …`. If that account has no sudo (the usual case for a rootless service
  account), the recipe cannot run where it is printed. Say **where**: *"run this from a separate
  operator login, not this session."* Note `sudo -iu <svc> … && sudo …` does not rescue it — the
  second `sudo` runs in the pre-`sudo` session.
- **Wrong state.** `git restore <file>` cannot clear a **staged addition** (`A` in porcelain): the
  path is not in `HEAD`, so there is nothing to restore it to. It needs `git restore --staged` **and**
  `rm`. Emitting the generic recipe for an `A` entry sends the operator in a circle.
- **Not a pathspec.** Porcelain renders a rename as `old -> new` — a *description*. Splice it into a
  recipe and you emit `git restore a.css old -> new`, which dies on `pathspec '->' did not match`.
- **Actively destructive.** Unmerged entries (`DD/AU/UD/UA/DU/AA/UU`) match naive "is it added?" /
  "is it modified?" tests, so an unresolved merge gets offered `git restore` — which **discards**
  in-progress work. Worse than useless: harmful if obeyed.

Two habits prevent the whole class:

1. **Classify before advising, and refuse when no single command fits.** Partition state into buckets
   and give each its own recipe — or explicitly *none*, with the reason. "No recipe is offered on
   purpose: no single command undoes a rename; finish or abort the merge first" is a better output
   than a fabricated command. Silence beats a plausible wrong answer.
2. **Execute the recipe you emit, against real state.** Reasoning about a format's documentation does
   not catch these; a throwaway fixture exercising every status/edge simultaneously does. `eval` the
   emitted string in a scratch repo and assert the tool accepts it.

### Parse structured tool output by its documented COLUMNS, not by whitespace fields

`git status --porcelain` is `XY PATH` — two status characters, **no separator between them**, path at
column 4. `awk`'s default splitting also strips leading whitespace, so ` M path` yields `$1 == "M"`
(fine) but `AM path` yields `$1 == "AM"`, matching neither an `== "A"` nor an `== "M"` test and
falling silently into whichever bucket is the default. Use `substr($0,1,1)` / `substr($0,4)`. Column
parsing also keeps renames whole and survives paths containing spaces, which `$2` truncates.

Then **do not undo it downstream**: an unquoted `$paths` re-splits on `IFS` at the point it reaches
the operator. Split on newline into an array (`mapfile -t arr < <(…)`) and expand quoted. And do not
re-quote what the tool already quoted — porcelain C-quotes paths that need it (`"dir with space/f"`),
and those double quotes are already valid shell; running them through `printf %q` escapes the tool's
own quotes into a pathspec it can never match.

## A generated artifact on a fixed path outlives the code that generated it

A script that emits a runnable artifact (`--emit-setup`-style: bake the environment's real values into
a self-contained script, hand it to an operator to run as root) is a good pattern — it removes
placeholder-substitution errors and multi-line copy-paste across a privilege hop. It has two failure
modes, both of which look like success:

- **Staleness.** The artifact is a *snapshot*. When the checkout gains a new step, the copy sitting in
  `/tmp` from last month happily applies everything *except* it, exits 0, and prints a plausible
  summary — the missing section is the only tell, and only if you know to look for it. Stamp the
  artifact with the commit it was generated from and have it **warn at run time** when the checkout has
  since moved. Warn, don't hard-fail: the checkout may legitimately have advanced after a deliberate
  emit, and refusing to run is worse than saying so.
- **Foreign ownership.** A fixed per-project path (`/tmp/<proj>-setup.sh`) is a *shared* name. Another
  account — an audit/read-only user, a colleague, a prior session — may already own it, and the write
  then dies with a bare `Permission denied` from the redirect, with nothing pointing at why. Default to
  a **per-user** path (`/tmp/<proj>-setup-$(id -un).sh`), and pre-flight the target so the failure
  explains itself: name the owner, and distinguish *"someone else owns it"* (remove as them or root)
  from *"you own it but the mode denies write"* (`chmod u+w`).

Ordering trap when the artifact is generated from the checkout it configures: emitting it **before**
the deploy that updates that checkout bakes in the *old* logic. Deploy first, then re-emit, then run.

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
codes="$(seq 1 500 | xargs -P50 -n1 sh -c 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 "<url>" 2>/dev/null || true' _)"
n429="$(printf '%s\n' "$codes" | grep -c '^429$' || true)"   # expect > 0
```

The trailing `_` occupies `sh -c`'s `$0` slot, so the xargs-fed token lands in `$1` — deliberately
unused here (`seq` only drives the request *count*); the `_` keeps the token out of `$0` and leaves
`$1` free for adaptations that do consume it (a per-URL probe list).
Single-quote the `sh -c` script so the *outer* shell can't expand anything in it (a real URL's `$`
or query string stays literal until the inner `sh` sees it). The inner `|| true` keeps one timed-out
`curl` (rc ≠ 0 → `xargs` rc 123) from killing a strict-mode (`set -e`) caller mid-probe — failed
requests still surface as `-w`'s `000` lines. Gate
`RATELIMIT_PROBE=1` (it floods the target; on a shared/global limiter it briefly throttles *all*
clients — run against a sandbox / off-hours).

### `openssl x509` has no `-notBefore` flag

To read a served cert's validity window: `openssl x509 -noout -startdate` (prints `notBefore=…`) or
`-dates` (both `notBefore=`/`notAfter=`). **`-notBefore` is not an option** — it errors `x509: Unknown
option`. Cheap to get wrong when hand-writing a "did the cert change?" (reused-vs-re-issued) check.
