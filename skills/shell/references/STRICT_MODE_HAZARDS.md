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
