# A green run whose universe was too small

[`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) covers the
check that never looked. This is its neighbour: the check looked,
the run was real, the output is green — and **the environment it ran in could not have
expressed the defect.** No better assertion fixes it. Only a different *state* does.
Tell them apart by asking whether re-pointing or re-wording the check would have caught
it. If yes, it is a false clean; if the check would still pass however carefully it is
written, the run's universe is the problem.

**Every substitute for reality is more forgiving than reality**, and each one converts a
whole class of production defects into a guaranteed pass:

| Substitute | What it guarantees passes |
| --- | --- |
| an un-taken failure branch | everything in it |
| an empty starting state (fresh dir, empty store, single-row table) | any clobber, any collision |
| a weaker data store (in-memory SQLite ignores ENUM/constraints) | every constraint violation |
| a different launch context (host vs in-container, by hand vs scheduler) | anything context-dependent |
| a double built from assumption rather than captured output | wherever the code is wrong |
| a fixture whose blast radius is still empty at the moment of the write | a missing `WHERE` |
| a safety stub that refuses to resolve real context | the real resolution path |
| a target earlier work already made hospitable | every prerequisite it silently supplied |

Two properties make a substitute forgiving — **absent prior state** and an **un-induced
failure** — *not* the disposability of the host. A throwaway box is the right rehearsal
target precisely because you may break it, provided you seed it with a copy of real prior
state and induce the failure. Rehearse re-invocation after a mid-run abort and a reboot.

The degenerate fixture is the invisible one: with an empty store, "render nothing" and
"render everything" emit identical bytes, and a sibling row created *after* the write
leaves nothing to clobber — so an isolation assertion survives a full behavior inversion.
Create every sibling row **before** the operation and comment that **order is load-bearing**.
Make each test assert its own input is non-degenerate.

**To enter an error path, break the TARGET the operation writes to, not the input** — break
the input and the pre-flight guard refuses, so the path is never entered and the vacuous
run looks like a success. Assert an observable side-effect proving the path ran. The error
and rollback paths of your own tooling are the half nobody rehearses at all.

**A script is a different program in each environment it inherits.** PATH, sourced profile
(a non-login shell never reads `profile.d`), stdin wiring, tty and login-shell status all
differ between your terminal and a scheduler unit or a non-login remote command — so "I ran
it by hand" tested a different program, and it bites in **both** directions (the timer path
and the manual path each break while the other works). Two edges recur:

- **A capability probe cannot distinguish "absent" from "did not resolve".** `command -v X`
  failing for PATH reasons is textually identical to the tool being missing, so the tolerant
  `absent → skip` branch quietly omits a step you believed ran — a false clean arriving
  through the environment. Say *"could not RESOLVE"*, never *"is absent"*; log why the branch
  was taken and surface skips in the run summary. Better still, **read the state directly**
  (a `/proc` entry, the config file) — a file read cannot report command-not-found. Do not
  over-correct: a `command not found` is *not* automatically a PATH artifact. The binary may
  be genuinely absent on a minimal image, the identifier may be a service-*unit* name rather
  than a binary name, or the message may be masking a real defect — one parity probe's
  command-not-found was dismissed as PATH noise for months while it masked an unset kernel
  parameter.
- **Capturing output while suppressing the prompt deletes the only signal that a run is
  waiting for input.** It then looks frozen, and the natural response — wait, then kill —
  destroys it mid-flight. Under a forced-tty remote call the command *substitution* is the
  primary swallower, not the stderr redirect. Separate **transport from parse**: run live,
  `tee` per target, parse those files after the loop (this also keeps secrets out of the
  capture). Redirect stdin from `/dev/null` for non-interactive remote calls and bound them
  with a killing timeout.

Pin the environment inside the script rather than inheriting it: export a full PATH
including the `sbin` directories as the **first line** of any remote or non-login sequence,
emitted from one shared helper so every script inherits the fix, or call `sbin` binaries by
absolute path.

## A probe that skips part of the production path cannot see failures there

Synthetic TLS checks across several hundred public endpoints were wired on purpose to
resolve every probed name to an internal address (container `extra_hosts`), because the
production edge drops probe traffic from the monitoring host. The reason was sound; the
consequence was that public name resolution — the skipped segment — became an invisible
failure class across every target. One endpoint's public DNS record was removed, making it
unreachable for everyone outside. The probe reported success on 37 of 37 samples over six
hours and read a valid certificate each time, because it never used public resolution.

**List the segments a probe bypasses, and give each one a watcher of its own** — here, a
resolution check against a public resolver, asserting the answer matches the expected
address. A bypass you add for a good reason still needs its own coverage.

Two further lessons from the same incident, both about alerting:

- **An alert about a downstream consequence hides the upstream failure.** The gap surfaced
  only because certificate renewal started failing (the name no longer resolved) and an
  expiry alert fired about 7 days later, pointing at the certificate subsystem. With 60 days
  left on the certificate, nothing would have reported anything. When an alert's subject is a
  consequence, ask what failed upstream and whether anything watches that directly.
- **Derive an alert threshold from the automated process it backs up.** Renewal is attempted
  at about 30 days remaining; the alert fired at 21. A renewal that starts failing is therefore
  invisible for about 9 days. When a process has its own trigger point, set the alert just
  past it (renewal trigger minus one retry interval), not at an independently chosen round
  number. Same instinct as calibrating with the verdict's own expression
  ([`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md)).

## Write the bound beside the verdict

**A green verdict also has a shelf life.** It certifies the code that existed when it ran,
so a step added later — especially behind a flag the rehearsal never set — is unproven while
the write-up still reads *proven*. Record the commit the verdict covers.

**Write the bound beside the verdict**: (a) the defect classes this run structurally could
not have detected — which branches never executed, which preconditions were absent, which
constraints the substrate cannot enforce, which production-path segments a probe bypasses —
and (b) the commit it covers. **If list (a) is
empty, you have not looked.** Where the substrate is weaker than production, pin what it
*can* check by asserting against the schema or source artifact. Build doubles from output
captured on the real target and make them **strict** — reject unknown arguments, because
real tools do. And prefer a discriminating test to an enumerated one: watch it fail against
the old behavior before you keep it.

Related: [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) ·
[`SAFE_CONFIG_EDITS.md`](SAFE_CONFIG_EDITS.md) ·
[`SSH_FLEET_PATTERNS.md`](SSH_FLEET_PATTERNS.md) for the sweep-side mechanics
(cold-probe opts, outer `timeout`) the transport/parse split above rides on ·
[`../../deployment/references/DARK_DEPLOY_KILL_SWITCH.md`](../../deployment/references/DARK_DEPLOY_KILL_SWITCH.md)
for the rollout-side twin (shadow silence is ambiguous for the same reason).
