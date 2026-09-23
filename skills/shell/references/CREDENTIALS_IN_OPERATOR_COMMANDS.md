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

**Every value you let through goes through one scrub.** An allowed key's value can still carry a
secret in a URL (`user:password@`, the path, `?token=…`, the fragment) or in a trailing comment.
The operator asked *which endpoint*, so once a line contains a URL, everything after
`scheme://host[:port]` on that line is hidden — path, query, fragment, a second URL, a trailing
comment — and inline `#` / `;` comments are dropped elsewhere. The host is matched by an
allow-list (RFC 3986 unreserved characters, or a bracketed IPv6 address), so any other character
ends it and the rest of the line is hidden. It also fails closed: a line that still contains `://`
after the rewrite (a URL shape the pattern didn't parse) is hidden entirely:

```bash
scrub() {   # structured values hidden; a URL line keeps key + scheme://host[:port] only
  sed -E -e 's#^([[:space:]]*-?[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*[:=][[:space:]]*)[[{].*$#\1<structured value hidden>#' \
         -e 's#^(([[:space:]]*-?[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*[:=][[:space:]]*)?)(.*[^A-Za-z0-9+.-])?([A-Za-z][A-Za-z0-9+.-]*://)([^/@[:space:]]*@)?(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._~-]+)(:[0-9]+)?.*$#\1\4\6\7 <rest hidden>#' \
         -e '\#://#{\# <rest hidden>$#!s#.*#<line with an unparsed URL hidden>#;}' \
         -e 's/[[:space:]]+[#;].*$//'
}
```

What it must turn into what — the cases that have leaked through earlier versions of this helper:

| Input line | Output |
| --- | --- |
| `hosts: https://user:pw@es.example.org:9200/_bulk?token=S#f` | `hosts: https://es.example.org:9200 <rest hidden>` |
| `hosts: https://example.invalid;token=secret` | `hosts: https://example.invalid <rest hidden>` |
| `hosts: https://[2001:db8::1]:9200/?token=secret` | `hosts: https://[2001:db8::1]:9200 <rest hidden>` |
| `hosts: ["SECRET", "https://safe.example"]` | `hosts: <structured value hidden>` |
| `hosts: SECRET https://safe.example` | `hosts: https://safe.example <rest hidden>` |
| `host = https://safe.example ; token=abc` | `host = https://safe.example <rest hidden>` |
| `hosts: https://:secret@/weird` | `<line with an unparsed URL hidden>` |
| `port = 9200 ; token=abc` | `port = 9200` |

**First choice — print only the fields you need.** An allow-list cannot leak a secret it never
selects, whatever that secret's key is called:

```bash
# anchored on the exact keys the question is about — not a word that may appear anywhere
grep -E '^[[:space:]]*(hosts?|ssl|enabled|protocol):' /etc/service/config.yml | scrub
```

`grep` prints the whole matching line, so an allowed key is only as safe as its value: a URL with
embedded credentials, or an inline mapping (`hosts: {url: …, token: …}`), comes along with it.
`scrub` handles the URL; if the file uses inline mappings, extract the single field with a
format-aware tool, selecting the **leaf** you need and scrubbing it too —
`yq -r '.output.hosts.url' /etc/service/config.yml | scrub`
— never the parent key (`.output.hosts` prints the whole mapping, token included). `-r` prints the
bare value under both the Go `yq` (v4) and the Python jq-wrapper `yq` (Debian's package), which
otherwise JSON-quotes it.

**When the output must be broader, show every key but hide every value — except under keys you
have named as safe.** Don't try to recognise secrets: a scanner for secret-sounding key names or
token-shaped values always has a bypass (a JWT under `shipper:` has dots, so it looks like neither).
Invert it, so an unrecognised value is hidden by default:

```bash
# keys stay visible so the operator can see the file's shape; only allow-listed values print
awk -v safe='^(hosts?|port|ssl|enabled|protocol|scheme)$' '
  match($0, /^[[:space:]]*-?[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*[:=]/) {
    k = substr($0, RSTART, RLENGTH); key = k
    gsub(/^[[:space:]]*-?[[:space:]]*|[[:space:]]*[:=]$/, "", key)
    # a safe key prints only a plain scalar: a {…} or […] value can nest a token
    if (key ~ safe && $0 !~ /[:=][[:space:]]*[[{]/) print; else print k " <hidden>"
    next
  }
  /^[[:space:]]*#/ { print "# <comment hidden>"; next }   # a commented-out token is still a token
  /^[[:space:]]*$/ { print; next }
  { print "<hidden line>" }                 # list items, continuations: values, so hidden
' /etc/service/config.yml | scrub     # a safe key's value can still carry a token in a URL
```

None of this is a guarantee. A shell redactor narrows what can leak, it cannot prove nothing
does: a value format nobody anticipated will eventually get through. The real control is still
the first one, selecting the single field the question needs. Use the broad form only when the
operator has to see the file's shape, and never paste its output anywhere public.

The failure mode is now a hidden value you needed, which costs a follow-up question, instead of a
leaked secret, which costs a credential rotation. Grow the `safe` list only with keys whose values
can never be a credential. Even a safe key prints only a plain scalar: `hosts: {url: …, token: …}`
or `hosts: [ … ]` is hidden, because a structured value can nest anything — select the leaf with
`yq -r` as shown above instead. `hosts` stays safe for scalars only because `scrub` reduces its URL to
scheme, host and port. Comments are hidden too: a commented-out `# token: …` is a live credential.

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
