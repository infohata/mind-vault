# Intermittent-fault gating: evidence, not point-in-time probes

**When this fires**: a remediation script must decide *which hosts to fix*,
and the fault is intermittent — e.g. a PAM/D-Bus activation call that stalls
*some* logins, not all, on certain container platforms (an OpenVZ guest, a
minimal VM image without a session bus). Intermittency defeats both naive gate
shapes:

- **A moment-of-truth probe under-selects.** A box can measure healthy NOW and
  stall an hour later. A latency sweep that happens to land between stalls
  quietly drops an affected host from the candidate set — the fix skips it and
  the fault "mysteriously" persists.
- **A service-liveness probe over-trusts.** `systemctl is-active dbus`,
  `busctl status`, a process check — all can succeed while the *specific call
  path* (PAM session setup calling into logind) is glacial. Liveness is not
  latency, and not call-path health.

## The reliable cause-gate: the fault's historical fingerprint

An intermittent fault that matters has *happened*, and when it happened it
wrote a log line. The exact line is the gate — it integrates over time where a
probe samples an instant:

```bash
# Run AS ROOT on the target at --apply time.
# Generic shape; substitute the exact line YOUR fault writes.
FPRINT='pam_systemd(sshd:session): Failed to create session: Activation of org.freedesktop.login1 timed out'

has_fault_history() {
    local host="$1"
    # Check the live log AND the most recent rotation — the last occurrence
    # may predate the last logrotate.
    ssh "$host" "sudo grep -qF '$FPRINT' /var/log/auth.log /var/log/auth.log.1 2>/dev/null" \
    || ssh "$host" "sudo journalctl -t sshd -t systemd-logind --since '-30 days' 2>/dev/null | grep -qF '$FPRINT'"
}
```

Rules that earn their keep:

- **As root, at apply time.** Auth logs and the full journal are typically
  root-readable only. An unprivileged grep doesn't error usefully — it sees
  nothing and reports "no history", silently emptying the candidate set.
- **Current log + most recent rotation**, minimum. Journald: bound with
  `--since` rather than trusting default retention.
- **Match the exact line (`grep -qF`)**, not a loose keyword. "timed out" as a
  gate will eventually select a host for the wrong disease.

## The `--preventive` waiver

A history gate has a legitimate blind spot: **provision-time / baseline use**.
A freshly provisioned host *cannot* have history yet, but you may still want
the fix applied as a platform baseline. Don't weaken the gate — add an
explicit waiver:

```bash
if ! has_fault_history "$host"; then
    if [ "${PREVENTIVE:-0}" = "1" ]; then
        echo "  $host: NO fault history — applying anyway (--preventive waiver)"
    else
        echo "  $host: NO fault history — skipping (use --preventive to override)"
        continue
    fi
fi
```

Default (curative) mode requires evidence; `--preventive` is loud in the plan
output so the transcript shows *which* rule admitted each host.

## Falsification discipline: the gate-equivalence dry-run

When a plan meets reality, the plan's *causal model* is a hypothesis. If two
independent gate definitions exist — e.g. "hosts whose auth log carries the
fingerprint" (evidence gate) vs "hosts on container platform X" (model gate:
the plan's theory of *why* the fault occurs) — run **both** in dry-run and
compare candidate sets before any `--apply`:

```bash
mapfile -t by_history < <(list_hosts_with_fingerprint | sort)
mapfile -t by_model   < <(list_hosts_matching_platform_theory | sort)

if [ "$(printf '%s\n' "${by_history[@]}")" != "$(printf '%s\n' "${by_model[@]}")" ]; then
    echo "GATE MISMATCH — evidence set and model set differ:" >&2
    diff <(printf '%s\n' "${by_history[@]}") <(printf '%s\n' "${by_model[@]}") >&2 || true
    echo "fail-closed: investigate before ANY --apply" >&2
    exit 1
fi
echo "gate equivalence holds: ${#by_history[@]} hosts selected by both definitions"
```

- **MATCH** → the causal model is corroborated; proceed.
- **MISMATCH** → **fail-closed stop-and-investigate, never "pick one".** A
  host in the model set but not the evidence set means the theory over-reaches
  (you'd mutate a healthy host); a host in the evidence set but not the model
  set means the theory misses a cause (the "fixed" fleet still carries the
  fault). Either way the plan's model is wrong, and a wrong model applied
  confidently is worse than no automation.

```text
✅ DO:   treat a gate mismatch as a finding — update the plan's model, re-run
         the equivalence check, only then apply.
❌ DON'T: shrug and apply to the union (mutates hosts the evidence never
         implicated) or the intersection (knowingly leaves evidenced hosts
         unfixed) just to keep the rollout moving.
```
