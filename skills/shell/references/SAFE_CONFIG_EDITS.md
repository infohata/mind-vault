# Safe edits to config files with no validator

**When this fires**: a script edits a system config file that has **no syntax
checker**. `sshd_config` has `sshd -t`, sudoers has `visudo -c`, nginx has
`nginx -t` — when one of those exists, run it as the post-edit gate. But the
PAM stack, `nsswitch.conf`, `fstab` and most of `/etc` have nothing: the first
feedback for a malformed edit is a broken host. Worst case is PAM — a corrupt
`/etc/pam.d/common-session` breaks **every** login path at once (SSH, console,
`su`), and you find out at the next login attempt.

The discipline, in order:

1. **Anchored sed on the exact line shape** — never a bare substring.
2. **`cp -a` backup first** (`-a` preserves mode/owner — PAM files are
   permission-sensitive; a root-owned 644 file restored as 600 is a new bug).
3. **Hard post-edit diff-shape assertion**: the diff vs the `.bak` must have
   *exactly* the intended shape. Any other shape → restore the `.bak`, abort.

## Worked example: commenting a PAM module line out

Goal: disable one `pam_examplemod.so` line in `/etc/pam.d/common-session` by
prefixing it with `#` — changing nothing else, on a file no tool can validate.

```bash
#!/usr/bin/env bash
set -euo pipefail

TARGET=/etc/pam.d/common-session
BAK="${TARGET}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
# Exact ACTIVE-line shape, anchored start-of-line. No bare 'pam_examplemod' —
# that would also hit comments, other module types, and partial tokens.
LINE_RE='^session[[:space:]]+optional[[:space:]]+pam_examplemod\.so([[:space:]].*)?$'

# Preflight: no-op fast path + exactly-one-line precondition.
if ! grep -qE "$LINE_RE" "$TARGET"; then
    echo "no-op: active line not present in $TARGET — nothing to do"
    exit 0
fi
matches=$(grep -cE "$LINE_RE" "$TARGET")
[ "$matches" -eq 1 ] || { echo "ABORT: expected exactly 1 active line, found $matches" >&2; exit 1; }

cp -a "$TARGET" "$BAK"
sed -i -E "s|$LINE_RE|#&|" "$TARGET"      # '&' = the whole matched line
```

## The diff-shape assertion

sed exits 0 whether or not anything matched, and a subtly wrong regex can
match more (or differently) than intended. So **assert the result**, don't
trust the edit:

```bash
restore_and_abort() {
    cp -a "$BAK" "$TARGET"
    echo "ABORT: post-edit diff shape unexpected — backup restored, file untouched" >&2
    exit 1
}

diff_out="$(diff "$BAK" "$TARGET" || true)"     # diff rc=1 on difference; that's the expected case
removed=$(printf '%s\n' "$diff_out" | awk '/^< /' | wc -l)
added=$(printf  '%s\n' "$diff_out" | awk '/^> /' | wc -l)
old_line="$(printf '%s\n' "$diff_out" | sed -n 's/^< //p')"
new_line="$(printf '%s\n' "$diff_out" | sed -n 's/^> //p')"

[ "$removed" -eq 1 ]                                   || restore_and_abort  # exactly one line left
[ "$added"   -eq 1 ]                                   || restore_and_abort  # exactly one line arrived
[ "$new_line" = "#$old_line" ]                         || restore_and_abort  # changed ONLY by gaining '#'
[ "$(wc -l < "$BAK")" -eq "$(wc -l < "$TARGET")" ]     || restore_and_abort  # no lines gained/lost

echo "OK: $TARGET edited; backup at $BAK"
```

What each check catches:

| Check                          | Failure it catches                                                          |
| ------------------------------ | ---------------------------------------------------------------------------- |
| `removed == 1 && added == 1`   | Regex matched multiple lines; sed mangled/deleted a line outright            |
| `new_line == "#" + old_line`   | Replacement produced anything other than the literal comment-out             |
| equal `wc -l`                  | Truncation, duplicate insertion, lost trailing newline turning into a merge  |

```text
✅ DO:   keep the timestamped .bak after success — it IS the --revert input
         (cp -a "$BAK" "$TARGET") and the forensic record.
❌ DON'T: sed -i 's/pam_examplemod/#&/' "$TARGET" with no backup and no
         assertion. On a PAM file, a bad match is a host you can no longer
         log in to — over SSH, on the console, or via su.
❌ DON'T: edit-then-eyeball over a fleet. The assertion exists precisely so
         per-host verification doesn't depend on operator attention.
```

Remote variant: when the edit runs on a target over SSH, ship this whole
sequence as the payload script and run it *on* the target — never stream
`sed -i` through an ssh one-liner where quoting layers can silently alter the
regex.
