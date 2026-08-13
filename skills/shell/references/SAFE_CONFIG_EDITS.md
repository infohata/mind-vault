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
rather than deleting silently (they are the manual rollback path). Where that pile may
live is not free either — see the next section.

## The deciding property lives outside the line you wrote

Everything above assumes the hazard is *your* edit being wrong. The other half of the
class is an edit that is well-formed and says exactly what its author meant, whose
behaviour is decided by a party that never appears in the diff — so nothing errors, no
reviewer objects, and a correct-looking artefact produces a different effect. The absent
decider is one of three: the **consumer's grammar** (how the program that reads this file
parses lines and selects filenames), the **runtime's attachment semantics** (what the
kernel or a container runtime does with a path at attach time), or **ambient state and
ranges** (umask, whether the path already existed, which commit is actually running).
Identify the deciding party first, read the property FROM it, and assert the span or
object you actually consumed — not the one you wrote.

### The consumer's grammar decides what your line means

**Inline comments in ignore-file formats.** Where `#` opens a comment only at column 0
(`.gitignore`, `.dockerignore` and kin), `path/   # why` is stored as ONE literal pattern
that matches nothing. The rule silently never applies, and "not ignored" is
indistinguishable from "no rule needed" until something is committed or baked into an
image — a per-host override one `git add -A` from the repo, a secret directory copied in
by `COPY . .`. Put the explanation on its own line ABOVE the pattern.

Prove the rule **fires**, not that the line exists:

```bash
❌ DON'T: touch "$d/x" && git status --short     # short-circuits if $d doesn't exist → PASS, nothing tested
❌ DON'T: git check-ignore -q "$p"               # exit 0 can come from a BROAD neighbour rule (*.log),
                                                 # while the rule under test is still dead
# ✅ DO
git check-ignore -v "$real_matching_path"        # READ the rule the -v output names
```

If a broad neighbour answers, retest with a filename only the rule under test can match,
and compare against a known-working bare pattern in the same file so a green result cannot
be a broken instrument (same family as
[`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md)). When one
ignore file is fixed, sweep every sibling ignore file in the repo in the same commit — the
habit is author-level, not file-level. The generalisation is **not** "never annotate
inline": the mirror-image bug is a hand-rolled parser of a data file whose producer emits
trailing comments unconditionally, which must be taught to STRIP them. Ask how the
consumer parses, then decide.

**A backup written beside a config file is a config file.** Writing `.bak` next to the
file it backs up is safe only where the consumer selects configuration by exact name; any
consumer that **globs its directory** loads the backup as live configuration. Directory-glob
config is everywhere — `conf.d`, `sites-enabled`, `sudoers.d`, systemd drop-in dirs,
`profile.d`, IaC module directories — and the same act lands in front of a different filter
each time: a `.bak` beside an enabled web-server vhost gives a second server block on the
same listener and the whole reload fails, while the identical act in a sudoers drop-in dir
is inert *only* because that consumer ignores dot-bearing filenames. The practice works by
luck until the luck runs out, and every inert instance confirms the habit.

It bites hardest in a batch edit: the backup is the *safety* step, so it is never reviewed
as a change to the running system, and the first validator run after N edits fails — which
points suspicion at the edits rather than at the backups sitting beside them.

This **qualifies** the ✅ DO above. Keep the timestamped `.bak` — it is the `--revert`
input — but write it into a directory the consumer cannot see (outside every include path),
and name that destination in the runbook. Run the consumer's own validator after a batch
edit, before reload. When you find an instance that happens to be inert, remove it anyway;
it is the same act in front of a different filter.

### Assert the SPAN you consumed, not the count

An edit or extraction delimited "from this marker to the next one" takes everything between
the two whenever the end delimiter is not the true **sibling boundary** of the start: a
subsection cut to the next *top-level* heading absorbs every subsection between them; a
non-greedy match whose terminator does not occur inside the intervening siblings runs to a
distant one; a marker range whose END marker is absent runs to EOF. The end delimiter
chosen is the one that is easy to name, not the one that bounds the intended unit — and the
resulting diff still looks proportionate to the stated intent, so it reads fine in review.

The usual guards are blind in distinct ways: a match **count** is right while the single
match is hundreds of lines too wide, and a non-empty check passes while an unterminated
range carried off a file's tail. (This is why the diff-shape assertion above tests exact
line content and equal `wc -l`, not merely that sed matched something.)

- Diff the **inventory** before and after: the heading list (`grep '^#'`, or `grep '^-#'`
  over the diff), the set of function/query starts, the marker pairs — the changed set must
  equal the intended set.
- Deleting a nested section: terminate at the next heading of the **same or shallower
  level**, and check what that heading actually is on disk rather than assuming the section
  is last.
- Programmatic patchers: assert the byte/line **size** of every replaced span, not how many
  spans matched.
- Marker ranges: assert the range **closed** — end marker found, known tail content absent
  — and mutation-test the guard by renaming the END marker; it must fail loudly.

**The same arithmetic, deploy-side.** Where a box pulls a long-lived, hand-advanced deploy
ref (a fast-forward pull of a mutable branch), what a deploy ships is the range between the
commit currently **running** and the commit the ref is moved to — not the change that
motivated the deploy. That ref is routinely not where anyone assumes, and it fails in two
directions needing **opposite** remedies, so diagnose which one you are in first:

| Direction        | Shape                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| **Over-shipping**  | Fast-forwarding to a merge commit ships every intervening change at once; a safety claim scoped to one change's delta ("no new mounts, no behaviour change") describes only that delta, and a deliberately phased plan is defeated in one step. |
| **Under-shipping** | The ref lags (dozens of commits is normal and invisible unless computed), so the pull is a no-op and reads as a clean run — or the checkout simply lacks a file that only ever landed on the mainline. |

Compute the range before deciding anything, as a numbered runbook step, for the back-out
target too: `git rev-list --count <deployed>..<target>` and `git log <deployed>..<target>`.
Read the **blob at the target SHA** rather than trusting the branch — a target picked
mid-change may predate a review fix. Recompute every quoted commit count after changing a
target; the count that motivated the fix is usually not the count the fix leaves behind.
Name absolute SHAs for target and back-out **where they can exist** — they cannot for a
commit the runbook itself instructs you to create, and there you substitute a check on the
deployed **effect** (a marker only the new code emits, read inside the deployed checkout).
A correct config file, a set env var, or a migration reporting "nothing to do" is never
evidence that the code is deployed. State in the runbook that reversing a fast-forward is a
force push. Scope: none of this applies to tag-pinned deploys or CI-on-merge delivery.

### A missing bind-mount source is created for you — as a root-owned directory

A bind mount whose host source does not exist is auto-created by the container runtime as a
**directory, owned by root** (short syntax — `-v` and the compose `volumes:` list — where
host-path creation defaults to on; the explicit `--mount type=bind` form errors instead).
What you see depends on what the image has at the destination: a **file** there → the mount
fails and the container dies at init with an opaque runtime "not a directory" error far
from the missing file; **nothing** there → the mount succeeds and the application fatals
later on "Is a directory" when it reads or writes the path. Either way the bogus directory
poisons the checkout — every later `up` hits the same error until it is removed, and the
deploying user often *cannot* remove it, because the runtime created it as root. The milder
sibling: a missing **directory** source is auto-created correctly but still root-owned, so
it mounts fine and fails on the rootless app's first write.

It only ever appears on fresh clones — never on the machine where the file has always
existed, which is where the author works.

So every ignored bind source (generated, per-host, admin-rewritten, operator-provisioned)
needs a **type-correct seed before `up`**, and the list of those sources belongs in ONE
shared library, not per-caller copies: labelling a copy "keep in sync" is demonstrably
insufficient — the labelled copy drifts while only the shared one gets hardened. Each new
untracking of an app-regenerated file mints a new source that must be seeded everywhere, so
this recurs on a schedule set by your untracking, not by your bug fixes.

```bash
❌ DON'T: [ -d "$f" ] && rm -rf "$f"    # root-owned leftover ⇒ rm fails: without errexit nothing
                                        # checks the status; with errexit you die with no hint about
                                        # who owns the leftover or what the remedy is
# ✅ DO
if [ -d "$f" ]; then
    rm -rf -- "$f" 2>/dev/null \
        || die "leftover DIRECTORY at $f owned by $(stat -c '%U:%G' "$f") — run: sudo rm -rf $f"
fi
```

Then assert the **type** of every bind source immediately before `up` as a separate step —
a run wedged between seed and `up` leaves a directory behind. Make the consuming code
tolerate absence so it degrades instead of fataling, **but only where an empty fallback is
safe**: for a file like an IP allow-list, degrading to an empty list silently empties a
security control, so fail loudly there instead.

Related: [`CLEANUP_TRAPS_AND_LOCKING.md`](CLEANUP_TRAPS_AND_LOCKING.md) ·
[`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) for the
could-not-run-reads-as-pass family this shares ·
[`STRICT_MODE_HAZARDS.md`](STRICT_MODE_HAZARDS.md) for why condition contexts and
non-final list position swallow a failed cleanup's status ·
[`../../deployment/references/CONTAINER_SINGLE_FILE_MOUNT.md`](../../deployment/references/CONTAINER_SINGLE_FILE_MOUNT.md)
for the sibling traps when the bind source *does* exist (inode pinning, directory
shadowing).
