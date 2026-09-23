# Credentials in operator commands

**Fires when** handing a human a command to run whose output they will paste back, when a
script sends a secret to an API, or when verifying a change that just narrowed an account's
privileges.

## A command you hand a human must redact on the way out

An operator was asked to grep a service config for `<servicename>|host|ssl` to find which
endpoint it pointed at. The file also held a service-account token, on a key named after the
service itself — so that line matched because it **contained the very word being searched for**.
A live credential landed in a chat transcript.

The operator promised to read output more carefully before pasting. That is the wrong fix:
**asking a human to scan output for secrets is a control that fails by design**, and the longer
the output, the more certainly it fails. Put the protection in the command.

**First choice — print only the fields you need.** An allow-list cannot leak a secret it never
selects, whatever that secret's key is called:

```bash
# anchored on the exact keys the question is about — not a word that may appear anywhere
grep -E '^[[:space:]]*(hosts?|ssl|enabled|protocol):' /etc/service/config.yml
```

**When the output must be broader, redact on the way out — by key name AND by value shape.** A
keyword list alone misses a token stored under a key named after the service (`shipper: …`), so
a second rule blanks any long token-like value whatever its key:

```bash
grep -iE 'servicename|host|ssl' /etc/service/config.yml \
  | sed -E -e 's/((password|passwd|token|secret|key|apikey|authorization|bearer|credential)[^:=]*[:=][[:space:]]*).*/\1<redacted>/I' \
           -e 's/([:=][[:space:]]*)["'"'"']?[A-Za-z0-9+/_=-]{20,}["'"'"']?[[:space:]]*$/\1<redacted:token-like>/'
```

Both rules over-redact on purpose (any key containing `key`; any 20+ character run without `.`
or `:`); an over-redacted line costs a follow-up question, a leaked one costs a credential
rotation. Neither is a guarantee — a short or punctuated secret under an innocent key still
passes — which is why the allow-list comes first. Adjust the separator class to the file
format: `:` for YAML, `=` for env/INI.

## Keeping secrets out of `-u` is not enough — request bodies go over stdin

Auth went through a mode-600 config file, carefully kept off the command line. Then a
user-creation request was sent with the new password in the request **body** as a
command-line argument — readable in the process table (`ps`, `/proc/<pid>/cmdline`) by every user
on the box for as long as the request ran.

```bash
# ❌ DON'T — the body, password included, is in argv
curl -sS --config "$AUTH" -X PUT "$URL/_security/user/shipper" \
  -H 'Content-Type: application/json' -d "{\"password\":\"$PW\",\"roles\":[\"writer\"]}"

# ✅ DO — the secret travels on stdin at every hop; no argv carries it
printf '%s' "$PW" | jq -Rs '{password: ., roles: ["writer"]}' \
  | curl -sS --config "$AUTH" -X PUT "$URL/_security/user/shipper" \
      -H 'Content-Type: application/json' --data-binary @-
```

Every hop counts, not just the last one: building the body with `jq -n --arg pw "$PW"` puts
the password in **jq's** argv instead of curl's, which is the same leak one process earlier.
`printf` is a shell builtin, so it never gets a process or an argv of its own; `jq -Rs` reads the
raw secret from stdin and emits the JSON body on stdout.

The test that caught it logged every argument vector the script produced and asserted the
secret never appeared in one. Once bodies moved to stdin, the test's stub could no longer tell
two requests apart by their arguments — **because nothing can, and that is the property.** The
stub had to start reading stdin to route requests, and the suite now asserts that explicitly: a
stub that still distinguishes requests by argv means a secret-bearing body has crept back onto
the command line.

## Least privilege will break your own verification — verify with metadata, not reads

A log shipper's superuser credential was replaced with a purpose-made **write-only** account.
The script then verified ingestion had resumed by counting documents. The count call needs a
**read** privilege, which a write-only account correctly lacks, so the script refused.

The refusal cost nothing, because it came **before** the configuration was touched: validate
the new credential first, edit second. But the design error is worth naming: least privilege was
granted, then verified with an operation least privilege forbids. Count through a
**stats/metadata** endpoint instead of a document-read endpoint — it answers "how many documents
exist" without granting access to any of them, so verification works and the account stays
write-only.

Pin it in the test: the stub returns `403` for the document-read endpoint, so a regression that
reaches for it again fails the same way production did.

Related: [`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) ·
[`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) ·
[`../../deployment/references/CONFIG_STATES_INTENT.md`](../../deployment/references/CONFIG_STATES_INTENT.md)
(the audit half of the same incident: five controls configured but inert).
