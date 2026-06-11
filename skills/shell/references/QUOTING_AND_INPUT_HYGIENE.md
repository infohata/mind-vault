# Quoting, word-splitting, and input hygiene

**When this fires**: any script that expands a variable into a command line,
reads lines from a file or pipe, validates a flag value, or writes a heredoc —
i.e. essentially every script. These are the mechanical rules (shellcheck-
enforceable, zero canon disagreement) plus the arg-parsing judgment call.

## Quote every expansion; lists are arrays

Word splitting + pathname expansion silently corrupt the argument vector the
moment a value contains a space, a glob character, a leading `-`, or is empty
(BashPitfalls #1/#2/#4/#5 are all this one bug; SC2086).

```bash
opts=(-o ConnectTimeout=5 -o BatchMode=yes)
ssh "${opts[@]}" "$host" true            # ✅ list = array, expansion quoted
for f in ./*.log; do cmd -- "$f"; done   # ✅ glob directly; `--` guards leading-dash names

opts="-o ConnectTimeout=5"; ssh $opts …  # ❌ space-joined string + unquoted expansion
for f in $(ls *.log); do …               # ❌ splits on whitespace, re-globs
```

- `"$@"` always — never `$*` or unquoted `$@` — to forward args intact.
- Intentional splitting has sanctioned shapes: an array (preferred),
  `${flag:+--flag}` alternate expansion. Never a bare unquoted variable.
- `printf '%s\n' "$var"` over `echo "$var"` for variable data: `echo` eats or
  transforms values like `-n`/`-e` and backslashes, implementation-defined
  (Pitfall #14). `printf '%q'` when showing a suspect value in an error.

## Reading lines: `IFS= read -r`, and the subshell trap

```bash
count=0
while IFS= read -r line; do (( ++count )); done < <(grep foo bar)   # ✅ survives
grep foo bar | while read line; do (( ++count )); done              # ❌ both bugs
```

- Piping into `while read` runs the loop in a subshell — mutations vanish when
  the pipe ends (Pitfall #8). Feed the loop (`< <(…)`, or a file redirect) or
  `shopt -s lastpipe`.
- `-r` stops backslash mangling; `IFS=` preserves leading/trailing whitespace.
- For a fixed small parse, the `while read -r name addr _` + `case` skip shape
  in [SSH_FLEET_PATTERNS.md](SSH_FLEET_PATTERNS.md) (hosts-file parser) is the
  worked example.

## Validating untrusted values: `case`, not `grep -E`

```bash
case "$SESSION_NAME" in
    '') echo "❌ --session-name cannot be empty." >&2; exit 1 ;;
    *[!a-zA-Z0-9_.-]*)
        echo "❌ Invalid --session-name: $(printf '%q' "$SESSION_NAME")" >&2; exit 1 ;;
esac
```

`grep` matches per-line: `$'main\nmalicious'` passes an anchored regex on its
first line while the newline still injects a second line into whatever file the
value lands in. `case` matches the full string atomically, no regex engine, no
line splitting, POSIX-portable. *Provenance: PR #59 cycle 6 (heredoc code
injection via a "validated" value).*

## Arg parsing

Hard rules:

- **Validate before consuming `$2`**: a flag run as `--flag` with no value
  makes `shift 2` eat the next flag. Check `[ -z "${2:-}" ]` → friendly error.
  *Provenance: PR #59 cycle 2.*
- **Never external `getopt(1)`** (BashFAQ/035 is categorical).
- Unknown args → error + exit, never silently ignored.

Judgment call, by option shape: short options only → `getopts` (handles `-xvf`
bundling, `OPTIND`/`shift "$((OPTIND-1))"`); `--long-options` → the manual
`while [ $# -gt 0 ]; case "$1" in` loop (getopts can't do long) — the house
template in deployment's
[`SHELL_INSTALLERS.md`](../../deployment/references/SHELL_INSTALLERS.md) shows
the full shape with `--help` extraction.

## Heredoc quoting — choose, and document the choice

- `<<'EOF'` (quoted): zero expansion — for bodies with runtime `$`-vars.
- `<<EOF` (unquoted): script-time vars expand — escape runtime ones as `\$VAR`.
- Mixed bodies: unquoted + backslash-escape the runtime vars.
- The comment above the heredoc must match the code; a comment claiming
  single-quoted above an unquoted heredoc misleads the next editor into adding
  an unescaped `$VAR`. `<<-EOF` strips leading **tabs** only, not spaces.
  *Provenance: PR #59 cycle 2.*

## Status checks: anchor both ends

```bash
ufw status | grep -qi "active"                                   # ❌ matches "inactive"
ufw status | grep -qE '^Status:[[:space:]]+active[[:space:]]*$'  # ✅
```

Any token that is a substring of its own negation (`active`/`inactive`,
`on`/`gone`) needs full-line anchoring. *Provenance: PR #59 cycle 3 (HIGH).*
The active-vs-commented line-shape discriminator lives in
[MAINTENANCE_SCRIPT_CONTRACT.md](MAINTENANCE_SCRIPT_CONTRACT.md) (grep
portability hazard).

## In-place edit traps

`sed … file > file` truncates the file before sed reads it (Pitfall #13):
write to a temp sibling then `mv` over, or `sed -i` where GNU sed is
guaranteed. For system config files, the full backup + diff-shape-assertion
discipline in [SAFE_CONFIG_EDITS.md](SAFE_CONFIG_EDITS.md) supersedes this.

## Related

- ShellCheck SC2086 (quoting), BashPitfalls #1–5/#8/#13/#14, BashFAQ/035 —
  the verified upstream canon for this file.
- [STRICT_MODE_HAZARDS.md](STRICT_MODE_HAZARDS.md) — rc-handling sibling.
