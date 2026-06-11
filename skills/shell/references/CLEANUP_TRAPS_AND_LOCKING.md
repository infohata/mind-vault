# Cleanup traps, temp files, and single-instance locking

**When this fires**: a script acquires anything that outlives a crash — temp
files/dirs, mux sockets, background children, or the right to be the only
running copy of itself (cron jobs, deploy/backup scripts). The common shape:
**resource lifetime must be bound to process lifetime via `trap`**, because
`set -e`, signals, and dropped SSH sessions all end the script at arbitrary
points.

## mktemp + EXIT trap — the canonical pair

```bash
tmpdir=$(mktemp -d -- "${TMPDIR:-/tmp}/myscript.XXXXXXXXXX") || exit 1
trap 'rm -rf -- "$tmpdir"' EXIT HUP INT TERM
```

- **Register the trap on the line immediately after acquisition** — a gap is a
  window where death leaks the resource.
- Never name temp files with `$$`: predictable names in world-writable `/tmp`
  are the classic symlink-attack surface (BashFAQ/062); `mktemp` is atomic and
  unpredictable.
- `EXIT` covers normal end, `set -e` death, and `exit` calls; the signal list
  covers terminal hangup and Ctrl-C (bash runs the EXIT trap on signal death
  too, but the explicit list is cheap and POSIX-sh-safe).

## One trap per signal — compose, don't stack

A second `trap '…' EXIT` **replaces** the first silently. Scripts with multiple
resources route everything through one cleanup function:

```bash
cleanup() {
    rc=$?                          # capture first — anything below clobbers it
    [ -n "${tmpdir:-}" ] && rm -rf -- "$tmpdir"
    [ -n "${MUXDIR:-}" ] && cleanup_mux
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM
```

Keep cleanup idempotent (it can fire after a partial setup) and guard each
step on the resource actually existing — `set -u` + an unset var inside a trap
is a cleanup that dies half-way. The per-socket ControlMaster teardown in
[SSH_FLEET_PATTERNS.md](SSH_FLEET_PATTERNS.md) is the worked multi-resource
instance.

## Single-instance locking (cron / overlapping runs)

When cron can re-fire while the previous run is still going (a slow backup,
a long deploy), serialize with `flock` on a held file descriptor:

```bash
exec 9>"/var/lock/$(basename "$0").lock"
flock -n 9 || { echo "already running — exiting" >&2; exit 1; }
# fd 9 stays open for the script's lifetime; the lock dies WITH the process —
# no stale-lock cleanup, no PID files, kill -9 included.
```

- `flock -n` = fail fast; drop `-n` to queue instead.
- ❌ DON'T: check-then-create a lock file (`[ -f lock ] || touch lock` — TOCTOU
  race) or `ps | grep` for a sibling process.
- `flock` is util-linux, not POSIX — fine on Linux hosts. The portable
  fallback is atomic `mkdir` + EXIT-trap `rmdir` (BashFAQ/045), which *does*
  leave a stale dir on `kill -9`; prefer flock wherever available.
- Both are unreliable on NFS; lock on local filesystems.

## Background children

A script that spawns background jobs (`cmd &`) owns them: on exit, stragglers
keep running detached. When that's not intended:

```bash
trap 'jobs -p | xargs -r kill; wait' EXIT
```

…and `wait` after the parallel section anyway — under `set -e`, `wait "$pid"`
also surfaces the child's rc instead of silently losing it.

## Related

- BashFAQ/045 (locking), BashFAQ/062 (secure temp files) — verified upstream
  canon.
- [MAINTENANCE_SCRIPT_CONTRACT.md](MAINTENANCE_SCRIPT_CONTRACT.md) — evidence
  logs interact with traps: the `exec > >(tee …)` wrapper owns stdio, which is
  why operator gates read `/dev/tty`.
