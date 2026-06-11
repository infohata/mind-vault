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
