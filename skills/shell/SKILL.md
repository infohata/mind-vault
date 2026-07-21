---
name: shell
description: Base shell-language layer beneath deployment + the devops persona — strict-mode hazards, quoting/input hygiene, trap cleanup + locking, plus live-host ops machinery (DRY-RUN/--apply/--verify contracts, operator gates, SSH fleet sweeps, validator-less config edits, evidence-gated remediation).
---

# shell

The vault's **base shell-language layer** — what `python` is to the framework
skills, `shell` is to ops work: language-general recipes beneath the
`deployment` skill and the devops persona. Two tiers live here:

- **Language mechanics** (patterns 1–3 + the non-negotiables): true of *any*
  bash script — deploy tooling, installers, cron jobs, CI steps, maintenance
  scripts.
- **Live-host ops machinery** (patterns 4–7): scripts that mutate live systems
  — mode surfaces, operator gates, SSH sweep hygiene, safe config edits,
  evidence gates.

`deployment` owns the Docker-Compose deploy lifecycle and machine provisioning;
its references point *down* into this layer for the language-general mechanics
rather than restating them. New shell-general patterns land here, not under
`deployment` by gravity.

## When to use

**TRIGGER when:** writing or reviewing any bash/sh script — ops/maintenance/rollout tooling, cron jobs, CI steps, entrypoints; user asks to "make this script safe to re-run"; adding or auditing DRY-RUN / `--apply` / `--verify` mode surfaces; sweeping a host fleet over SSH; editing system config files (PAM stack, `nsswitch.conf`, login-path or firewall config) from a script; designing precondition checklists for operator tooling.

**SKIP when:** the script is a Docker-Compose deploy / backup / rollback (→ [`deployment`](../deployment/SKILL.md) owns that lifecycle) or a machine-provisioning installer (→ deployment's [`SHELL_INSTALLERS.md`](../deployment/references/SHELL_INSTALLERS.md) leads and reaches down into this layer); one-shot commands a human types interactively.

## Language mechanics

### 1. Strict mode and its holes

**Fires when** authoring any script. `set -euo pipefail` (+ `shopt -s
inherit_errexit` on bash ≥4.4 — without it multi-step command substitutions
sail past a failing first step) is the house prologue AND a known-leaky
tripwire: pipeline-in-assignment aborts before your friendly
error, `head -N` SIGPIPE races, informative non-zero rcs (`diff`, `grep`),
`local var=$(cmd)` masking failure (SC2155), condition contexts disabling
errexit transitively (`if f; then` turns `-e` off inside all of `f`), unguarded
`cd` (SC2164), `(( i++ ))` at zero. Explicit rc handling at every destructive
step, as if `-e` were absent; never retrofit `-e` onto a working script.
Full catalog + the honest judgment-call stance:
[`references/STRICT_MODE_HAZARDS.md`](references/STRICT_MODE_HAZARDS.md).

### 2. Quoting and input hygiene

**Fires when** a variable expands into a command line, a loop reads lines, a
flag value needs validation, or a heredoc gets written. Quote every expansion;
lists are arrays; `"$@"` always; `printf '%s\n'` over `echo` for variable data;
`IFS= read -r` fed by `< <(…)` (never pipe into `while read` for state);
validate untrusted values with `case`, not `grep -E` (newline injection);
validate `$2` before `shift 2`; never external `getopt(1)`; heredoc quoting
matches its comment; anchor status greps both ends (`active`/`inactive`).
Full rules + the getopts-vs-manual judgment call:
[`references/QUOTING_AND_INPUT_HYGIENE.md`](references/QUOTING_AND_INPUT_HYGIENE.md).

### 3. Cleanup traps, temp files, locking

**Fires when** a script acquires anything that outlives a crash. `mktemp` +
`trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM` registered immediately after
acquisition; one composed cleanup function per script (a second `trap` on the
same signal silently replaces the first); `flock -n` on a held fd for
single-instance cron/deploy scripts (lock dies with the process — no stale
locks, unlike check-then-create or `ps | grep`); kill + `wait` background
children. Full recipes:
[`references/CLEANUP_TRAPS_AND_LOCKING.md`](references/CLEANUP_TRAPS_AND_LOCKING.md).

### Non-negotiables (one-liners)

- Every script passes **shellcheck** before merge (SC2086/SC2155/SC2164
  mechanically enforce patterns 1–3); suppressions are per-line directives
  with a justification comment, never global.
- `[[ ]]` over `[ ]` in bash; `$(…)` over backticks; `(( … ))` for arithmetic
  (`[[ $x > 7 ]]` is *string* comparison).
- Never `sed … file > file` — truncates before read.
- `main "$@"` as the last line of any script with functions.

### Judgment calls (decide per script, don't legislate)

- **bash vs POSIX sh**: host-side ops scripts → `#!/bin/bash` and use bash
  features freely; container entrypoints → match the image's shell
  (alpine/dash/BusyBox) and enforce with `shellcheck --shell=sh`. Never
  bash-isms under `#!/bin/sh`.
- **bats-core tests**: only past the real-logic threshold (branching arg
  parsing, parsing functions, a shared `lib.sh`); below it the question is
  "why is this still shell, not Python?". Never for five-line wrappers.

## Live-host ops machinery

### 4. The maintenance-script contract

**Fires when** a script mutates a live host. Mode surface: DRY-RUN default,
`--apply` (per-target for risky changes), `--verify` (proves the **effect** —
re-measures the symptom — never "the script ran"), `--revert`, `--check`.
**Interactive precondition-acknowledgement gate** (the headline pattern): when
safety depends on operator-side preconditions (break-glass verified, second
held session, off-box backup), `read -r ans </dev/tty` requiring a literal
`yes` **before the first connection or mutation** — a checklist printed while
the action already runs is decoration. Plus: one-target-at-a-time, no-op fast
path, `$HERE`-relative siblings, evidence logs via `exec > >(tee -a "$LOG")
2>&1`, lockout discipline for login-path changes, grep portability (positive
matches only; parse line *shape* for active-vs-commented).

✅ DO: `--verify` re-measures the symptom (fresh-connection login latency back under threshold).
❌ DON'T: `--verify` that greps for the config line `--apply` just wrote — that proves execution, not effect.

Full contract, gate snippet, post-factum-checklist failure story:
[`references/MAINTENANCE_SCRIPT_CONTRACT.md`](references/MAINTENANCE_SCRIPT_CONTRACT.md).

### 5. SSH fleet sweeps

**Fires when** a script probes or remediates many hosts over SSH. Cold-probe
hygiene for timing-sensitive probes (`ControlMaster=no`, `BatchMode=yes`,
**outer** `timeout N` — `ConnectTimeout` can't see post-auth stalls); one-login
ControlMaster apply mux when logins are expensive; env-driven jump host;
probe-identity vs operator-identity separation (refuse privileged modes under
the read-only identity); extract shared scaffold at the **5th** copy, not
before. Full options, mux teardown, hosts parser:
[`references/SSH_FLEET_PATTERNS.md`](references/SSH_FLEET_PATTERNS.md).

### 6. Editing config files that have no validator

**Fires when** a script edits a system config file with no syntax checker
(worst case PAM: a corrupt `common-session` breaks every login path at once).
Anchored sed on the exact line shape → `cp -a` `.bak` → **hard post-edit
diff-shape assertion** (exactly one line changed, only by gaining `#`, equal
line counts) — any other shape restores the `.bak` and aborts.

✅ DO: assert the diff shape after the edit; restore + abort on surprise.
❌ DON'T: trust sed's exit code — sed exits 0 whether or not anything matched.

Worked PAM example: [`references/SAFE_CONFIG_EDITS.md`](references/SAFE_CONFIG_EDITS.md).

### 7. Gating remediations on evidence, not point-in-time probes

**Fires when** the fault is intermittent. A moment-of-truth probe under-selects
(healthy now, stalls later); a liveness probe over-trusts (service up, call
path glacial). Gate on the fault's **historical fingerprint** — the exact log
line, checked as root at apply time, live log + most recent rotation. Pair with
a `--preventive` waiver for provision-time use, and a gate-equivalence dry-run
when two gate definitions exist — candidate-set MISMATCH is fail-closed, never
"pick one". Full pattern:
[`references/INTERMITTENT_FAULT_GATING.md`](references/INTERMITTENT_FAULT_GATING.md).

## When NOT to use these patterns

- **A real validator exists** (`sshd -t`, `visudo -c`, `nginx -t`) — run it as
  the post-edit gate; the diff-shape assertion is the validator-less fallback.
- **One-shot interactive commands** — the mode surface and gates are for
  scripts that encode a procedure, not ad-hoc terminal work.
- **Deploy lifecycle scripts** — `deploy.sh`/`backup_db.sh` shapes belong to
  [`deployment`](../deployment/SKILL.md); reach down into this layer for the
  shared mechanics rather than duplicating.

## References

- [references/STRICT_MODE_HAZARDS.md](references/STRICT_MODE_HAZARDS.md) — `set -euo pipefail` hazard catalog (pipeline-in-assignment, SIGPIPE race, SC2155, condition-context transitivity, SC2164 cd guards, arithmetic-at-zero, negated-rc capture after `if !`, PIPESTATUS reset-on-read) + the never-retrofit / explicit-rc-at-destructive-steps stance.
- [references/QUOTING_AND_INPUT_HYGIENE.md](references/QUOTING_AND_INPUT_HYGIENE.md) — quoting/arrays/`"$@"`, `printf` over `echo`, `IFS= read -r` + subshell trap, `case`-not-`grep` validation, arg parsing (`$2` guard, getopts vs manual, no `getopt(1)`), heredoc quoting, anchored status greps.
- [references/CLEANUP_TRAPS_AND_LOCKING.md](references/CLEANUP_TRAPS_AND_LOCKING.md) — mktemp + EXIT-trap pair, composed single cleanup function, `flock` single-instance locking, background-child reaping.
- [references/MAINTENANCE_SCRIPT_CONTRACT.md](references/MAINTENANCE_SCRIPT_CONTRACT.md) — mode surface (DRY-RUN / `--apply` / `--verify` / `--revert` / `--check`), the interactive precondition-acknowledgement gate, one-target-at-a-time, idempotency, evidence logs, lockout discipline, grep portability.
- [references/SSH_FLEET_PATTERNS.md](references/SSH_FLEET_PATTERNS.md) — cold-probe hygiene, one-login ControlMaster apply mux + per-socket teardown, jump-host + identity separation, extract-at-5th-copy scaffold rule.
- [references/SAFE_CONFIG_EDITS.md](references/SAFE_CONFIG_EDITS.md) — validator-less config edits: anchored sed, `cp -a` backup, diff-shape assertion with restore-and-abort; worked PAM example.
- [references/SUDOERS_WHITELIST_FENCES.md](references/SUDOERS_WHITELIST_FENCES.md) — NOPASSWD whitelists on mixed-age fleets: stat-dead entry paths (pre-usrmerge `/bin` vs `/usr/bin`), fnmatch argument fences (no path templates / regex metachars + offline round-trip test), denial-vs-absence rc ambiguity, dot-staged visudo-first deploy + content-hash parity verify, guard-skip cron classification.
- [references/INTERMITTENT_FAULT_GATING.md](references/INTERMITTENT_FAULT_GATING.md) — historical-fingerprint cause gates, `--preventive` waiver, fail-closed gate-equivalence dry-run.
- [references/PRIVILEGE_DROP_PORTABILITY.md](references/PRIVILEGE_DROP_PORTABILITY.md) — unqualified `runuser` dies off-PATH in automated contexts (Debian homes it in `/usr/sbin`); use `setpriv --reuid … --regid … --init-groups -- env HOME=… <cmd>` (argv-preserving) or `su -s /bin/bash <user> -c` (shell-string, mind the quoting/password-context) — both `/usr/bin`-homed — and add the chosen tool to the dep preflight.
- [references/INTERACTIVE_SUDO_LOGIN_SHELL.md](references/INTERACTIVE_SUDO_LOGIN_SHELL.md) — the *interactive* sibling of `PRIVILEGE_DROP_PORTABILITY.md`: `sudo -iu <user>` / `sudo -i` / `su -` opens a login shell that blocks until it exits, so `&&`/`;`-chained commands run in the PRE-sudo session, not the target user's (and a pasted/stdin-fed multi-line block splits nondeterministically between the two shells). Fix: put the become-user command on its own line (everything after runs *inside* that session), or one-shot `sudo -iu <user> bash -lc '…'` (`-l` sources the login env — PATH, `XDG_RUNTIME_DIR`, rootless `DOCKER_HOST`). Common when writing rootless-docker service-user runbooks.
- [deployment skill](../deployment/SKILL.md) — the devops-layer sibling above this one; its [`SHELL_INSTALLERS.md`](../deployment/references/SHELL_INSTALLERS.md) keeps the installer-specific catalog and points down here for the language-general entries.
- Upstream canon (verified 2026-06): Greg's Wiki BashPitfalls + BashFAQ 105/045/062/035, ShellCheck wiki, Google Shell Style Guide, bats-core docs.
