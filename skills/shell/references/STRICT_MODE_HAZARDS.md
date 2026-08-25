# Strict mode (`set -euo pipefail`) and its holes

**When this fires**: authoring or reviewing any bash script. The house prologue
is `set -euo pipefail` — and the prologue is a tripwire, not a seatbelt. `set -e`
has well-documented holes (BashFAQ/105 class); a script that *relies* on errexit
at a load-bearing point instead of checking the rc explicitly will eventually
sail past a failure. Both halves matter: always set strict mode, never trust it
where failure is expensive.

Legacy note: older installers in consuming repos use `set -eo pipefail` (no
`-u`). New scripts take `-u` and pay the `${var:-}` discipline below.

## Hazard catalog

### 0. Bare `set -e` without `pipefail`

Only the **last** element's rc counts in a pipeline: `curl … | gpg --dearmor -o
keyring.gpg` with a failed curl still exits 0 (gpg happily dearmors empty
input), writing an empty keyring that breaks downstream with an unrelated
error. Any script with `curl | gpg`, `curl | bash`, `… | jq` pipelines needs
`pipefail`. *Provenance: PR #55 cycle 1.*

### 1. Pipeline-in-assignment — silent abort before your error message

```bash
set -eo pipefail
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ]; then
    echo "❌ Could not resolve home for '$TARGET_USER'." >&2; exit 1
fi
```

When `$TARGET_USER` doesn't exist, `getent` exits 2; pipefail makes that the
assignment's rc; `set -e` kills the script **before** the friendly-error `if`
runs. The user sees a silent unexplained exit.

✅ DO: pre-validate the precondition (`id -u "$TARGET_USER" >/dev/null 2>&1 ||
{ …friendly error…; exit 1; }`) before the pipeline-in-assignment; or wrap with
`set +e; VAR=$(…); rc=$?; set -e` when no clean precondition probe exists.

### 2. `head -N` in a pipeline — the SIGPIPE race

```bash
set -eo pipefail
if ufw status | head -1 | grep -qE '^Status:[[:space:]]+active'; then
```

`head -1` closes stdin after one line; the producer takes SIGPIPE writing the
next, exits 141; pipefail propagates it. The `if` goes false even when grep
matched; an `|| echo fallback` masks the real value. Same race with `grep -q`
exiting early mid-long-pipe.

✅ DO: drop a redundant `head` (an anchored regex already selects one line), or
take the first line without a pipe:

```bash
VER=$(tool --version 2>/dev/null || true)
VER_LINE=${VER%%$'\n'*}        # parameter expansion — no pipe, no SIGPIPE
```

### 3. Informative non-zero exits

`diff` (rc 1 = files differ), `grep` (rc 1 = no match): non-zero is *data*,
not an error. Under `set -e` the script dies on a perfectly healthy host.

✅ DO: `out="$(diff a b || true)"` when the output is the point, or capture the
rc explicitly in an `if`/`case` when the rc is the point.
❌ DON'T: blanket-`|| true` a command whose failure you DO need to stop on —
that re-opens the hole strict mode was closing.

### 4. `local var=$(cmd)` masks the rc (SC2155)

`local`/`export`/`declare` is itself a command and returns *its own* rc (0),
swallowing the command substitution's failure. Declare and assign separately:

```bash
local out
out=$(might_fail)              # rc now visible to set -e / explicit checks
```

### 5. Condition contexts disable errexit *transitively*

Inside `if cmd; then`, `cmd && x`, `cmd || x`, `! cmd` — `set -e` is off **for
the entire call tree of `cmd`**, including every function it calls. A helper
that was written assuming errexit-on-failure silently barrels on when invoked
from a condition. This is the single biggest `set -e` hole.

✅ DO: have functions whose failure matters `return`/`exit` explicit rcs and
check them; treat `set -e` as backstop only.
❌ DON'T: refactor straight-line code into a function, call it from an `if`,
and assume its internal failure handling still aborts.

### 6. Command substitution doesn't inherit errexit

`v=$(step1; step2)` — `step1` failing doesn't stop `step2` in the subshell.
Bash ≥4.4: add `shopt -s inherit_errexit` to the prologue. Below 4.4, keep
substitutions single-command.

### 7. `set -u` edges

Optional args/env reads need explicit defaults: `"${2:-}"`, `"${DEBUG:-0}"`.
Empty arrays expand fatally under `-u` on bash <4.4 — `"${arr[@]}"` on a
possibly-empty array needs `${arr[@]+"${arr[@]}"}` there; current bash is fine.

### 8. `cd` without a guard — the wrong-directory catastrophe (SC2164)

```bash
cd generated_files          # fails: typo, permissions, missing mount
rm -r ./*                   # ...runs in the CALLER'S directory
```

✅ DO: `cd /some/dir || exit 1` (`|| return` in functions) on **every** `cd`,
even under `set -e` — condition-context transitivity (hazard 5) means errexit
may be off exactly when the cd fails. The destructive command after a cd is the
canonical shell-bug class; guard the cd, don't trust the mode.

### 9. Arithmetic returning 0 kills the script

`(( i++ ))` when `i` is 0 evaluates to 0 → rc 1 → `set -e` exits. Use
`(( ++i ))` or `i=$((i + 1))`; append `|| true` only when the expression
legitimately evaluates to 0.

### 10. `rc=$?` after `if ! cmd` captures the NEGATED status

`if ! ssh …; then rc=$?; die "failed (rc=$rc)"; fi` always reports **`rc=0`** —
`!` has already inverted the status by the time `$?` is read. A real failure
reports success, and which end of a pipeline broke is hidden. Snapshot
`PIPESTATUS` (hazard 11) or capture errexit-safely — `rc=0; cmd || rc=$?` —
then test `rc`. (A bare `cmd; rc=$?` is itself a strict-mode trap: under
`set -e` the failure exits the script before the capture line runs.)

### 11. Reading `${PIPESTATUS[0]}` RESETS `PIPESTATUS` — snapshot the whole array

```bash
ssh … | gzip -c > out
ssh_rc="${PIPESTATUS[0]}"      # this assignment is itself a command…
gz_rc="${PIPESTATUS[1]}"       # …so PIPESTATUS is now the assignment's 1-element array
                               # -> under `set -u`: "PIPESTATUS[1]: unbound variable" -> ABORT
```

✅ DO: snapshot in one assignment — `st=("${PIPESTATUS[@]}")` — then read
`"${st[0]:-0}"` / `"${st[1]:-0}"`. `PIPESTATUS` is rebuilt after *every*
command, including a variable assignment. The bug only fires on the error path
(the second element is only read when reporting a failure), so it converts an
error *report* into a *crash* — precisely when you least want one.

### 12. A query that returns EMPTY instead of failing poisons every `$( )` that consumes it

`set -euo pipefail` protects you from a command that **fails**. It does nothing about a command that
**succeeds and prints nothing** — and a large class of query tools do exactly that when you ask for a
field that does not exist under the spelling you used.

```bash
# The projection names a field this CLI version does not render under that spelling.
# Exit status 0. Output: empty. Nothing complains.
NUM="$(some-cli describe "$thing" --format='value(project_number)')"

some-cli list --filter="projectNumber=$NUM"    # -> a filter with no operand
rm -rf "$BASE/$NUM"                            # -> rm -rf "$BASE/"   <- catastrophe
```

The second line is the *lucky* case: a strict parser rejects the malformed filter and you find out.
The third is the unlucky one — an empty expansion is a **valid string**, so it silently widens a
path, empties a filter, or writes to the wrong key.

**Guard the assignment, not the use.** `set -u` cannot help here: the variable IS set, to `""`.

```bash
NUM="$(some-cli describe "$thing" --format='value(project_number)')"
[ -n "$NUM" ] || die "could not read the project number for $thing — check the field name; an \
unmatched projection on this CLI returns EMPTY rather than failing"
```

⚠️ **Field spellings drift between CLI versions and between output formats** — `camelCase` in JSON,
`snake_case` in a table renderer, and a targeted projection that silently matches neither. When a
projection comes back empty, **dump the whole object and read the keys** instead of guessing the next
spelling:

```bash
some-cli describe "$thing" --format=json | python3 -c \
  "import json,sys; print(list(json.load(sys.stdin)))"
```

📌 Same class, different dress: `grep` with no match, `jq` selecting a missing key, `awk` printing an
absent field, an API returning `[]`, a `SELECT` matching no rows. **Any `$( )` whose emptiness would
change the meaning of the next command needs a non-empty assertion on the line after it.**

### 13. Identify a destructive target by a RESOLVING TEST, not by its name

Before an operation that creates or destroys, the question is not *"is this the name I expect?"* but
*"does the thing I expect to already be there actually resolve here?"*

This matters because **the failure mode of a wrong target is often creation, not an error.** A
provisioning tool pointed at the wrong account does not fail — it builds a parallel copy of
everything and reports success. A migration pointed at the wrong database creates the schema. You get
a clean exit code and a duplicate universe.

**Worked example.** A provisioning script required an account id passed explicitly, and the account
list held **two entries with the same display name**, differing only by an id suffix. Choosing wrong
would have created a second bucket, a second service account and a second credential — the exact
duplicate the design existed to prevent — and printed success. The resolving test was to ask whether
an *already-existing* resource answered in that account:

```bash
# expected to EXIST -> if it resolves, the target is confirmed by evidence rather than by name
some-cli describe-resource "known-existing-thing" --account="$CANDIDATE" >/dev/null 2>&1 || \
  die "'$CANDIDATE' does not hold the expected resource — refusing to provision into it"
```

Three properties make a resolving test worth having:

- **It asserts something that already exists**, so a wrong target fails instead of being built into.
- **It is read-only**, so it costs nothing and can gate every invocation.
- **It fails closed** — no output is a refusal, not a pass (item 12 is how that goes wrong).

⚠️ **Pick an anchor that actually carries the identity.** In the example the *bucket* could not
answer — its describe output carries no account field at all — so the service account was the anchor.
Verify the anchor can answer the question before building a gate on it, or the gate silently passes.

📌 When the required id is recorded nowhere in the repo, that absence is itself the defect: the next
person re-derives it under time pressure inside a credentialed window. Write it down beside the
script that demands it.

### 14. An assertion that cannot express "empty" asserts NOTHING

`grep -qF -- "$expected" <<< "$actual"` is the usual substring check in a shell test harness. When
`$expected` is the empty string — the natural way to write *"this should produce no output"* — it
searches empty input for an empty pattern, finds **no line**, and reports failure. The case looks
like a caught regression; it is a broken assertion.

Caught while writing tests for a "reports green when it should not" fix — where a test that asserts
nothing is precisely the defect being fixed, one level down:

```bash
# WRONG — reports FAIL on correct behaviour, and would report FAIL on incorrect behaviour too
_case "empty input stays empty" "" "$(fold "" "$payload")"

# RIGHT — emptiness is a property of the string, not a substring of it
out=$(fold "" "$payload")
[ -z "$out" ] || fail "want empty, got: $out"
```

**The general form: a matcher has a domain, and the empty expectation is outside it.** Before
trusting a green harness, feed each assertion a value you *know* should fail it. An assertion never
observed failing has not been tested — it has been written.

## Stance — a judgment call, encoded honestly

The canon itself is split on `set -e` (BashFAQ/105's own contributors disagree:
avoid entirely / use cautiously / handle explicitly and never rely on it). The
house synthesis:

- **Fresh ops scripts**: `set -euo pipefail` prologue, always.
- **Destructive steps** (mutations, gates, verifications): explicit rc handling
  as if `set -e` were absent. The mode is a tripwire for the failures you
  didn't anticipate, never the handler for the ones you did.
- **Never retrofit** `-e` onto an existing working script — it changes control
  flow at every unchecked rc, and the holes above make the result untestable
  by inspection.
- The old "unofficial strict mode" advice to set `IFS=$'\n\t'` in the header is
  deprecated — even its maintained mirror dropped it; quote correctly instead
  ([QUOTING_AND_INPUT_HYGIENE.md](QUOTING_AND_INPUT_HYGIENE.md)).

## Related

- [MAINTENANCE_SCRIPT_CONTRACT.md](MAINTENANCE_SCRIPT_CONTRACT.md) — the ops-script prologue in context (evidence logs, informative-rc note).
- Deployment installers: [`SHELL_INSTALLERS.md`](../../deployment/references/SHELL_INSTALLERS.md) — installer-specific catalog; its strict-mode entries point here.
