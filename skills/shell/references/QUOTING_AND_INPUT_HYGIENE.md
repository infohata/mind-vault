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

## Generating shell from a Python triple-quoted string

A Python patch step that writes shell text broke the generated script twice in one session:

```python
new = """echo "done\""""   # intended; what was written:
new = """echo "done""""   # SyntaxError — loud, fine
new = """echo "done""""" # → 'echo "done'  — the closing quote is gone, silently
new = """echo "done"""   # → 'echo "done'  — same
```

Python closes the literal at the **first** `"""`, and a content-final `"` is the first quote of that
run. The shell string loses its closing quote and swallows whatever follows. `bash -n` on the
*previous* version of the file passes, so it doesn't flag the breakage as new — run `bash -n` on
the **generated** output. The rule: never end a triple-quoted literal on the delimiter's quote
character — switch to `'''…'''`, or end the literal on a newline.

## A block pasted into an interactive bash contains no `!`

**When this fires**: any command block handed to a human to paste into a terminal —
a runlist block, a one-liner in a chat reply, a fix recipe. An interactive bash
has history expansion on (`histexpand`, the default). It rewrites `!…` **before
the line is parsed**, so the line runs altered or not at all:

```text
bash: !/: event not found
bash: !~: event not found
```

It fails safe, but each slip costs a round trip, and during an incident that is
the expensive part. The recurring shape is a `!` that belongs to **another
language nested inside a double-quoted remote command**:

```bash
ssh host "sudo awk '!/^#/ && NF' /etc/foo.conf"     # ❌ event not found
ssh host "sudo awk '{ if (p !~ /re/) next }' f"      # ❌ event not found
```

The single quotes protect awk on the remote side, but locally they are literal
characters **inside** the outer double quotes, and that is where the interactive
bash looks for `!`. Agents reason about quoting one layer at a time and miss that
the outermost layer is an interactive shell. The `!` is in awk syntax, where it
doesn't look like shell. A narrower rule ("no `!` inside double quotes") was in
place and still slipped twice in one evening (2026-11-04).

**The rule: no `!` anywhere in a paste block.** It is cheaper to check than the
exact expansion grammar, and it covers every nesting. (Measured on bash 5.2:
`!` inside plain single quotes, inside `$(…)`, or in a heredoc body ran fine,
and so did `!=` and `! -f`, because a `!` followed by a space, `=` or `(` is not
expanded. Single quotes nested inside double quotes did **not** protect. Don't
hand-audit which case a line is: rewrite.)

| Instead of | Write |
| --- | --- |
| awk `!/re/ {…}` | `/re/ == 0 {…}` |
| awk `if (p !~ /re/) …` | `if ((p ~ /re/) == 0) …` |
| awk `!seen[$0]++` | `seen[$0]++ == 0` |
| awk `$1 != "x" {…}` | `($1 == "x") == 0 {…}` |
| `[ ! -f x ] && a && b` | `test -f x \|\| { a && b; }` |
| `if ! cmd; then …; fi` | `cmd \|\| { …; }` |
| `[ "$a" != "$b" ] && a` | `[ "$a" = "$b" ] \|\| { a; }` (strings); `-ne` (integers) |

**Group the whole guarded body** in the shell rows: `a || b && c` parses as
`(a || b) && c`, so `test -f x || create && reload` runs `reload` even when the
file exists. The rewrite also returns 0 where the original returned 1 when the
guard is false. Where that status is used (last command of a function, a
continuing `&&` chain), restructure into an `if … then … else … fi` and state
the status explicitly.

Negate by **comparing the positive test with zero**, not with `next`: `next`
skips every later rule and statement for that record, so `/re/ {next} {…}`
silently changes a script like `!/re/ {print} {count++}`, which counts every
record. (Each awk rewrite above was run against its original, with a later
counting rule, on the same input: identical output, mawk.)

**Last step before handing a block over:** check it mechanically. A hit means
rewrite, not "this one is probably fine". The check also flags the forms bash
leaves alone (`! -f`, `!=`, `!` in plain single quotes). That is deliberate,
not a false positive: the rule is no `!`, so the check has no exceptions to
judge, and the table above has a rewrite for each.

```bash
grep -n '!' block.sh        # or scan the block text by eye for the one character
```

**Fallback, not a replacement:** a block may start with `set +H` **on its own
line**. Bash expands history on the whole input line before any of it runs, so
`set +H; ssh host "awk '!/^#/'"` on one line still fails. Only a separate
earlier line turns it off. It then stays off for the rest of that shell, but a
new terminal, a fresh ssh session or another operator starts with it on again,
which is why the rule is no `!`, not "remember `set +H`".

## Related

- ShellCheck SC2086 (quoting), BashPitfalls #1–5/#8/#13/#14, BashFAQ/035 —
  the verified upstream canon for this file.
- [STRICT_MODE_HAZARDS.md](STRICT_MODE_HAZARDS.md) — rc-handling sibling.
