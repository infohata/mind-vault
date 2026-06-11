---
name: shell
description: Base shell layer beneath devops — DRY-RUN/--apply/--verify maintenance scripts, operator precondition gates, SSH fleet sweeps, validator-less config edits, evidence-gated remediation on live hosts.
---

# shell

The vault's **base shell-scripting layer** — patterns for authoring operational
and maintenance bash scripts (fleet rollouts, host probes, config remediation)
that touch **live systems**. What `python` is to the framework skills, `shell`
is to devops work: language-general recipes beneath the `deployment` skill and
the `devops` persona. `deployment` owns the Docker-Compose deploy lifecycle and
machine provisioning; this skill owns the script-engineering mechanics any
operational script needs regardless of what it deploys or fixes — mode
surfaces, operator gates, SSH sweep hygiene, safe config edits, evidence gates.
New shell-general ops patterns land here, not under `deployment` by gravity.

## When to use

**TRIGGER when:** writing or reviewing a maintenance / ops / rollout shell script; user asks to "make this script safe to re-run"; adding or auditing DRY-RUN / `--apply` / `--verify` mode surfaces; sweeping a host fleet over SSH (probes, payload pushes, config remediation); editing system config files (PAM stack, `nsswitch.conf`, login-path or firewall config) from a script; designing precondition checklists for operator tooling.

**SKIP when:** the script is a Docker-Compose deploy / backup / rollback (→ [`deployment`](../deployment/SKILL.md) owns that lifecycle) or a machine-provisioning installer (→ deployment's [`SHELL_INSTALLERS.md`](../deployment/references/SHELL_INSTALLERS.md)); the script only touches the repo checkout (build/test helpers — the live-system safety machinery here is pure overhead for scripts that can't break a host).

## Pattern

### 1. The maintenance-script contract

**Fires when** a script mutates a live host. The house contract:

- **Mode surface**: DRY-RUN default (read-only, prints the plan), `--apply`
  (mutating, often per-target), `--verify` (proves the **effect** — re-measures
  the latency/posture the fix targets — never "the script ran"), `--revert`
  where meaningful, `--check` for CI-style staleness checks.
- **Interactive precondition-acknowledgement gate** (the headline pattern):
  when safe operation depends on operator-side preconditions (break-glass
  access confirmed, a second held session open, a backup taken), print the
  checklist and `read -r ans </dev/tty` requiring a literal `yes` **before the
  first connection or mutation**. A checklist printed while the action already
  runs is decoration, not a gate.
- One-target-at-a-time for risky mutations; idempotent re-runs with a no-op
  fast path; `$HERE`-relative sibling defaults; evidence logs via
  `exec > >(tee -a "$LOG") 2>&1`; `set -euo pipefail`; lockout discipline for
  login-path changes (held second session + fresh-connection post-check).
- **Grep portability hazard**: quiet+invert grep logic (`! grep -qv`,
  `grep -qvx`) is unreliable on non-GNU greps — use positive matches only, and
  parse line *shape* when distinguishing active vs commented config.

✅ DO: `--verify` re-measures the symptom (fresh-connection login latency back under threshold).
❌ DON'T: `--verify` that greps for the config line `--apply` just wrote — that proves execution, not effect.

Full contract, gate snippet, and the post-factum-checklist failure story:
[`references/MAINTENANCE_SCRIPT_CONTRACT.md`](references/MAINTENANCE_SCRIPT_CONTRACT.md).

### 2. SSH fleet sweeps

**Fires when** a script probes or remediates many hosts over SSH.

- **Cold-probe hygiene** for timing-sensitive probes: `-o ControlMaster=no -o
  ControlPath=none -o BatchMode=yes`, plus an **outer** `timeout N` around the
  whole ssh — `ConnectTimeout` bounds only the TCP handshake; post-auth stalls
  (PAM session setup) are invisible to it.
- **One-login apply mux**: when target logins are expensive, the first
  (gate-probe) connection opens a ControlMaster and subsequent scp/ssh ride
  the socket free; teardown trap closes each socket explicitly.
- Jump-host via env-driven `-J`, probe-identity vs operator-identity
  separation (refuse privileged modes under the read-only identity), and the
  scaffold-duplication counter: extract a shared hosts-parser/SSH-opts lib at
  the **5th** copied instance, not before.

Full options, mux teardown gotchas, hosts-file parser:
[`references/SSH_FLEET_PATTERNS.md`](references/SSH_FLEET_PATTERNS.md).

### 3. Editing config files that have no validator

**Fires when** a script edits a system config file with no syntax checker
(unlike `sshd_config`'s `sshd -t`). Worst case is the PAM stack: a corrupt
`/etc/pam.d/common-session` breaks every login path at once — SSH, console,
`su` — and nothing warns you before the next login fails.

The discipline: anchored sed on the exact line shape → `cp -a` `.bak` first →
a **hard post-edit assertion** that the diff vs `.bak` has exactly the
intended shape (one line changed, only by gaining a leading `#`, equal line
counts) — any other shape restores the `.bak` and aborts.

✅ DO: assert the diff shape after the edit; restore + abort on surprise.
❌ DON'T: trust sed's exit code — sed exits 0 whether or not anything matched.

Worked PAM example + the diff-shape assertion snippet:
[`references/SAFE_CONFIG_EDITS.md`](references/SAFE_CONFIG_EDITS.md).

### 4. Gating remediations on evidence, not point-in-time probes

**Fires when** the fault being remediated is intermittent (e.g. a PAM/D-Bus
call that stalls *some* logins). A moment-of-truth probe under-selects (host
measures healthy now, stalls an hour later); a service-liveness probe
(`systemctl is-active`, `busctl status`) over-trusts (the service is up, the
call path is glacial). The reliable cause-gate is the fault's **historical
fingerprint** — the exact log line it writes, checked as root at apply time in
the live log plus the most recent rotation. Pair with a `--preventive` waiver
for provision-time use where no history can exist, and run a gate-equivalence
dry-run when two independent gate definitions exist — candidate-set MISMATCH
is a fail-closed stop, never "pick one".

Full pattern + falsification discipline:
[`references/INTERMITTENT_FAULT_GATING.md`](references/INTERMITTENT_FAULT_GATING.md).

## When NOT to use these patterns

- **A real validator exists** for the file you're editing (`sshd -t`,
  `visudo -c`, `nginx -t`) — run it as the post-edit gate instead of (or in
  addition to) the diff-shape assertion. The assertion is the fallback for
  validator-less files, not a replacement for real validation.
- **One-shot commands a human types interactively** — the mode surface and
  gate are for *scripts* that encode a procedure, not for ad-hoc terminal work.
- **Deploy lifecycle scripts** — `deploy.sh`/`backup_db.sh` shapes belong to
  the [`deployment`](../deployment/SKILL.md) skill; reach down into this layer
  for shared mechanics (evidence logs, idempotency) rather than duplicating.

## References

- [references/MAINTENANCE_SCRIPT_CONTRACT.md](references/MAINTENANCE_SCRIPT_CONTRACT.md) — mode surface (DRY-RUN / `--apply` / `--verify` / `--revert` / `--check`), the interactive precondition-acknowledgement gate (`read … </dev/tty`, literal `yes`, before first connection), one-target-at-a-time, idempotency, evidence logs, lockout discipline, grep portability.
- [references/SSH_FLEET_PATTERNS.md](references/SSH_FLEET_PATTERNS.md) — cold-probe hygiene (no mux, BatchMode, outer `timeout`), the one-login ControlMaster apply mux + per-socket teardown, jump-host + identity separation, the extract-at-5th-copy scaffold rule.
- [references/SAFE_CONFIG_EDITS.md](references/SAFE_CONFIG_EDITS.md) — validator-less config edits: anchored sed, `cp -a` backup, hard diff-shape assertion with restore-and-abort; worked PAM common-session example.
- [references/INTERMITTENT_FAULT_GATING.md](references/INTERMITTENT_FAULT_GATING.md) — historical-fingerprint cause gates (journal/auth-log line, root, current + rotated), `--preventive` waiver, gate-equivalence dry-run with fail-closed MISMATCH handling.
- [deployment skill](../deployment/SKILL.md) — the devops-layer sibling above this one (deploy lifecycle, screen sessions, CI/CD); its [`SHELL_INSTALLERS.md`](../deployment/references/SHELL_INSTALLERS.md) covers provisioning installers specifically.
