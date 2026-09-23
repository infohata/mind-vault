# Config states intent — only the running system states fact

**Fires when** auditing a host's security posture, remediating after an incident, or writing
the verification step for any control (TLS, auditing, backups, firewall, credentials).

One host carried **five** controls that read as present in configuration and did nothing. None
was found by reading a file; every one was found by asking the running system.

| The config said | The truth | What revealed it |
| --- | --- | --- |
| `ssl: enabled: true` on a log shipper | **inert** — the endpoint was declared with an explicit `http://` scheme, which wins, so the link was plaintext | reading the whole output block, not the flag |
| an audit-logging flag set to `true` | **refused** — the service logs at startup that its license tier does not permit auditing | the service's own startup log |
| a registered filesystem snapshot repository | **could never be written** — its location sat outside the declared repository-path allow-list | comparing the two paths, then the repository's *verify* call |
| "there is a firewall" | **there was none** — the firewall service was inactive and the filter table empty | asking the service manager |
| "the connection is authenticated" | authenticated **as the superuser** — the log shipper held full cluster admin | checking *which user*, not whether auth existed |

## A setting that does nothing is worse than the gap it pretends to close

It stops anyone looking again. The self-inflicted instance is the one to remember: while fixing
the other four, the audit flag was set again and "verified" by watching the audit file grow from 0
to 935 bytes. **File growth is not audit events** — the service had already logged that it was
refusing the setting.

Deleting an inert setting quietly has the same defect: the next person is free to re-add it and
believe it. Replace it with a comment saying why the control is absent and what would enable it.

## Verify the effect, never the setting

| ❌ Not a verification | ✅ A verification |
| --- | --- |
| "the service started with the new flag" | "documents rose 145,518,161 → 145,518,176 in ten seconds" |
| "the audit file is growing" | an audit **event** for an action you just performed, found by its own fields |
| "the TLS flag is true" | the connection's negotiated protocol, observed on the wire or in the client's connect log |
| "the firewall rule is listed" | a request from outside that times out (below) |
| "the snapshot repository is registered" | the repository's own verify call succeeding, then a snapshot completing |

Same principle as `--verify` proving an effect in
[`../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md`](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md),
applied to controls instead of scripts.

## Verify from outside the thing under test — and both sides of it

A firewall rule listing looked perfect. What proved containment was a request **from another
host** to the public address timing out, where the day before it had returned `401` — while the
internal path still answered in about a millisecond. Check both sides: the blocked path is
blocked, and the path that must keep working still works. A rule that blocks everything also
passes a one-sided check.

## When a firewall listing looks empty, check the other backend

A host's default firewall listing was empty. The legacy filter table held a hand-written drop
rule for one rented VPS address: someone had hit the same exposure before, blocked one address,
documented nothing, and used a backend the default listing does not show. The exposure itself
stayed open for years. Before concluding anything from an empty listing, list **every** backend
the host could be using (`nft list ruleset`, `iptables-legacy -S`, `iptables-nft -S`, plus ufw /
firewalld status) — the same any-variant probe as
[`MAINTENANCE_SCRIPT_CONTRACT.md`](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md)
§ Detect the mechanism. And treat a one-address block as a symptom report: find the exposure it
was papering over.

## Triage aside: an established TCP connection cannot have a spoofed source

Completing the handshake requires receiving the SYN-ACK at the claimed address and answering with
the right sequence number; an off-path spoofer never sees it. So an address seen in an
**established** session really completed the connection — it is not forged. That proves the
**peer**, not the originator: NAT, a proxy, a VPN exit or a load balancer can be that peer on
behalf of many clients. Before blocking, check whether the address is a known intermediary
(your own edge, a CDN, a shared egress); if it is, block at the layer that sees the real client
instead. Spoofing stays trivial for UDP and for bare SYN floods — the distinction is the
established session, not TCP as such.

Related: [`HARDENING.md`](HARDENING.md) (baseline firewall and SSH) ·
[`MONITORING.md`](MONITORING.md) ·
[`../../shell/references/CREDENTIALS_IN_OPERATOR_COMMANDS.md`](../../shell/references/CREDENTIALS_IN_OPERATOR_COMMANDS.md)
(the remediation half of the same incident: redaction, secrets off the command line, least
privilege vs your own verification).
