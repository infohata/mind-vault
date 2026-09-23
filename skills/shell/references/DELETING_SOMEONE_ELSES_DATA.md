# Deleting data on someone else's say-so

**Fires when** a script removes data you don't own and the authority for it is a message
("yes, delete those") rather than a spec: another team member's backups, a colleague's
scratch volumes, a customer's expired exports.

About 20 GB of a teammate's backup artifacts were removed on the strength of a two-word chat
reply to a surveyed list. The reply approved **that list, as it looked when surveyed** —
nothing wider and nothing newer. Every guardrail below exists to keep the script inside that
approval. **A deletion script's job is to refuse. Removing files is the easy part.**

## The rules

- **Pin every target by path + exact byte size + exact mtime**, taken from the survey the
  person actually replied to. A file rewritten since the survey is no longer the file they
  approved; the script must not guess whether that's fine.
- **A literal list, never a glob.** A pattern over a date prefix widens silently when someone
  drops a new file into the directory, and widening is exactly what must not happen when the
  authority is one sentence.
- **Verify all targets and all keepers BEFORE unlinking any.** Two phases, never interleaved.
  One mismatch aborts the run with nothing removed.
- **Assert the survivors, before and after.** If the point is "keep one restore point per
  instance", the script proves each instance still has one when it finishes.
- **Stay narrower than what is technically possible.** The approved message proposed keeping
  the newest backup of each instance. Removing those too would have freed more space and
  exceeded the authorization. If you want more, ask again.
- **Test the refusals, not the successes.** The tests worth having: a tampered target aborts,
  a missing keeper aborts, an already-absent target aborts — each with nothing removed.

## Shape

```bash
#!/bin/bash
set -euo pipefail

# path|bytes|mtime (stat %.9Y, nanoseconds) — copied verbatim from the survey the owner approved
TARGETS=(
  "/srv/backups/app1/2026-08-01.tar.zst|7340032000|1785542400.118207431"
  "/srv/backups/app2/2026-08-01.tar.zst|6291456000|1785542700.502961744"
)
# must still exist, unchanged, when we finish
KEEPERS=(
  "/srv/backups/app1/2026-09-01.tar.zst|7516192768|1788220800.330584019"
  "/srv/backups/app2/2026-09-01.tar.zst|6442450944|1788221100.874120563"
)

check() {   # check <path|bytes|mtime> -> 0 only on an exact match
  local path bytes mtime actual
  IFS='|' read -r path bytes mtime <<<"$1"
  [ -f "$path" ] || { echo "MISSING: $path" >&2; return 1; }
  actual=$(stat -c '%s|%.9Y' -- "$path")   # whole seconds would miss a same-second rewrite
  [ "$actual" = "$bytes|$mtime" ] || { echo "CHANGED since survey: $path ($actual)" >&2; return 1; }
}

case "$#:${1:-}" in                   # exactly zero args, or exactly --apply
  0:)       MODE=dry-run ;;
  1:--apply) MODE=apply ;;
  *)        echo "usage: $0 [--apply]" >&2; exit 2 ;;
esac

# Phase 0 — the lists themselves: no duplicates, no path both a target and a keeper
dups=$(printf '%s\n' "${TARGETS[@]%%|*}" "${KEEPERS[@]%%|*}" | sort | uniq -d)
[ -z "$dups" ] || { echo "ABORT: path listed twice (target/keeper overlap?):" >&2; echo "$dups" >&2; exit 1; }

# Phase 1 — verify everything; any failure aborts with nothing removed
bad=0
for e in "${TARGETS[@]}" "${KEEPERS[@]}"; do check "$e" || bad=1; done
[ "$bad" -eq 0 ] || { echo "ABORT: survey no longer matches; nothing removed" >&2; exit 1; }
[ "$MODE" = apply ] || { echo "DRY-RUN: ${#TARGETS[@]} target(s) verified"; exit 0; }

# Phase 2 — remove exactly the pinned paths; stop at the first failure and say where
removed=0
for e in "${TARGETS[@]}"; do
  if ! rm -- "${e%%|*}"; then
    echo "PARTIAL: removed $removed of ${#TARGETS[@]}; stopped at ${e%%|*}" >&2
    break
  fi
  removed=$((removed + 1))
done

# Survivors still hold — checked on the partial path too
kept=0
for e in "${KEEPERS[@]}"; do check "$e" && kept=$((kept + 1)); done
echo "removed $removed/${#TARGETS[@]}, keepers intact: $kept/${#KEEPERS[@]}"
[ "$removed" -eq "${#TARGETS[@]}" ] && [ "$kept" -eq "${#KEEPERS[@]}" ]
```

The check and the `rm` are separate steps, so a writer that replaces a verified path in between
gets its new file deleted. Run this while the owner's backup job is idle — or take the lock that
job holds, across both phases — rather than trusting the gap to be short.

The dry-run default and `--apply` flag follow
[`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) § Mode surface. The
refusal tests are cheap to write against a temp directory: copy the lists, `touch` one target
to change its mtime, delete one keeper, pre-delete one target, list one path as both target and
keeper, pass a stray extra argument — every case must exit non-zero with the directory unchanged.
A run that fails partway exits non-zero and says how many targets it removed and where it stopped.

## Why pinning beats "the owner said the old ones"

"The old ones" is a description; the survey is a snapshot of what it meant at one moment. A
glob or an age filter re-evaluates the description at run time, against a directory that may
have changed, and nobody re-approves the result. Pinning path, size and mtime turns the
approval into data the script can compare against — so the question "is this still what they
agreed to?" has a mechanical answer instead of a guess.

Related: [`EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) (a check
that reports success without having looked) ·
[`SAFE_CONFIG_EDITS.md`](SAFE_CONFIG_EDITS.md) (refuse when a match count isn't exactly what
you expected).
