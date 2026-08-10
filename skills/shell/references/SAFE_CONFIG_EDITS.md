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

## Flipping a key that may or may not already exist: SUBSTITUTE, never insert

The natural idiom for "make sure this setting is present" is a guarded append:

```bash
❌ DON'T: grep -q "$KEY" "$f" || printf "%s => '%s',\n" "$KEY" "$NEW" >> "$f"
```

It is silently wrong the second time and every time after. Once the key exists —
including when it exists **with the wrong value** — the guard is satisfied and the
append is skipped, so the operator gets a clean exit and no change. The failure is
invisible precisely in the case that matters: re-running to move a setting from one
value to another.

**Gate on the VALUE, not on the key's presence**, and make an ambiguous file an error
rather than a guess:

```bash
# ✅ DO — validate the interpolated values, then: exactly one occurrence, or refuse.
# $KEY/$NEW land inside a regex and a replacement — a metacharacter (or & / \ in $NEW)
# would silently change what matches or what gets written, so gate their shape first
# (case-not-grep validation — see QUOTING_AND_INPUT_HYGIENE.md).
case "$KEY" in (*[!a-z_]*|"") echo "!! REFUSING: KEY not [a-z_]+" >&2; exit 1;; esac
case "$NEW" in (*[!a-z_]*|"") echo "!! REFUSING: NEW not [a-z_]+" >&2; exit 1;; esac
hits=$(grep -cE "'$KEY'[[:space:]]*=>[[:space:]]*'[a-z_]+'" "$f" || true)
if [ "${hits:-0}" -ne 1 ]; then
  echo "!! REFUSING: '$KEY' matches $hits lines, expected exactly 1" >&2
  exit 1
fi
sed -i -E "s/('$KEY'[[:space:]]*=>[[:space:]]*')[a-z_]+(')/\1$NEW\2/" "$f"
```

The count check is not pedantry. A reader function that reports the current value with
`head -1` shows the operator **one** value, while `sed` without a line restriction
rewrites **every** matching line — so a duplicate entry, or a commented-out old value with
the same text shape, is changed without appearing anywhere in the output. Text matching
does not know PHP/YAML/INI semantics; refuse when the file is ambiguous.

## Stage → validate → `rename(2)`; never validate in place

Even with a validator available, `sed -i` followed by a check leaves a window:

```bash
❌ DON'T: sed -i …  "$f"          # live file is now the new content
          <validator> "$f" || cp -a "$BAK" "$f"   # ...but only if we get here
```

Between those two lines the live file holds **unvalidated** content. A dropped SSH
session, a `SIGKILL`, an OOM kill — anything that ends the process in that gap leaves the
new content serving traffic with no revert having run. The window is small and the
consequence is a broken service until someone notices.

Edit a copy in the **same directory** (so the rename cannot cross a filesystem), validate
the copy, and only then move it into place:

```bash
# ✅ DO
tmp="$f.tmp.$$"
trap 'rm -f -- "${tmp:-}"' EXIT HUP INT TERM   # see CLEANUP_TRAPS_AND_LOCKING.md
cp --preserve=all -- "$f" "$tmp" 2>/dev/null || cp -p -- "$f" "$tmp"
sed -i -E "…" "$tmp"

<validator> "$tmp" || { echo "rejected, live file untouched" >&2; exit 1; }
grep -q "<expected post-state>" "$tmp" || { echo "value did not land" >&2; exit 1; }

mv -f -- "$tmp" "$f"      # rename(2) within a directory: atomic
```

`rename(2)` relinks the directory entry to the inode the copy already built, so the live
name is only ever the old content or the fully-checked new content — and everything
`--preserve=all` set (mode, owner, ACLs, xattrs) comes across because it is *the same
inode*, not a second copy. Note `cp -p` alone preserves mode/owner/timestamps but **not**
ACLs, xattrs or SELinux context; prefer `--preserve=all` with `-p` as the fallback.

Three details that turn this from nearly-safe into safe:

- **A validator that CANNOT RUN is a failure, not a pass.** Three-state it: passed /
  failed / could-not-run, and treat the third like the second. A missing interpreter
  reporting "skipped" reads exactly like a clean lint, and the edit ships unchecked.
- **`trap` the staging file.** It is a full copy of the config — including any credentials
  it contains — and an orphan left by a kill is both litter and a disclosure. A `.bak`
  accumulation warning globbing `*.bak` will not mention it.
- **Serialise with `flock`** when two operators might run the tool at once. Without it,
  same-second backup filenames collide, and worse: one process's post-edit readback can
  observe the *other's* write, conclude its own edit failed, and "revert" from its own
  backup — silently undoing a legitimate concurrent change. See
  [`CLEANUP_TRAPS_AND_LOCKING.md`](CLEANUP_TRAPS_AND_LOCKING.md).

Backups hold whatever the config holds. When that includes credentials, an unbounded
`.bak` pile beside the live file is a growing disclosure surface — warn on accumulation
rather than deleting silently (they are the manual rollback path).

Related: [`CLEANUP_TRAPS_AND_LOCKING.md`](CLEANUP_TRAPS_AND_LOCKING.md) ·
[`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) for the
could-not-run-reads-as-pass family this shares.
