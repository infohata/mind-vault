# Agent-host capacity — tmpfs scratch is RAM, and disk IOPS caps parallel jobs

**Fires when** an agent session (or the sub-agents it dispatches) clones repos, builds images or
writes dumps on its own host, and when deciding how many heavy jobs (image builds, test suites)
may run at once.

## A scratch directory on tmpfs is RAM

On a 16 GB build host, `/tmp` was a 7.6 GB tmpfs. A week of one agent session's repo clones and
build trees in its `/tmp` scratch directory held 5.7 GB, so available memory was 6 GB instead of
12. The host had no swap, and tmpfs pages without swap never leave RAM. Nothing failed outright;
every later job just had half the memory it was planned with.

- **Check before you write big trees:** `df -h -t tmpfs /tmp "${TMPDIR:-/tmp}"`. If the scratch
  directory is on tmpfs, keep clones, build contexts and dumps on a disk path instead, and keep only
  small files in scratch.
- **Clean scratch daily**, skipping anything a running process still holds open:

```bash
# list (dry run) or remove (APPLY=1) scratch entries untouched for a day and not held open
scratch=<your scratch dir>
find "$scratch" -mindepth 1 -maxdepth 1 -mtime +0 -print0 |
while IFS= read -r -d '' e; do
  if [ -d "$e" ]; then held=$(lsof +D "$e" 2>/dev/null); else held=$(lsof -- "$e" 2>/dev/null); fi
  if [ -n "$held" ]; then echo "KEEP (open)  $e"
  elif [ "${APPLY:-0}" = 1 ]; then rm -rf -- "$e" && echo "removed      $e"
  else echo "would remove $e ($(du -sh -- "$e" | cut -f1))"; fi
done
```

  Run it once as a dry run (it lists, with sizes), then with `APPLY=1`.
- **Say the same in every sub-agent brief.** Sub-agents inherit the scratch path, not the
  reason to keep it small.

## On VPS disks, IOPS is the parallelism cap

The question was whether a third parallel image-build slot was safe. CPU (load 2.5–3 on 4 cores)
and RAM (12 GB free once the scratch above was cleaned) said yes. `iostat -dx 5` during **one**
build showed about 292 writes/s at 95 % util with a 73 ms write await: the provider's roughly
300 IOPS ceiling. A second job would only have queued behind the first; a third would have slowed
all three. An app box at the same provider went from about 300 to about 1,850 writes/s after a
move to its SSD/NVMe storage tier, for a couple of euros a month.

- **Measure the disk during one job**, not just CPU and RAM: `iostat -dx 5` (sysstat) and read
  `w/s`, `%util` and `w_await` for the device that holds the build tree.
- **Add a parallel slot only if one job stays well under about 50 % util.** Near 100 %, more jobs
  add queueing, not throughput.
- **Price the storage-tier upgrade as the fix.** It is often cheaper than another box, and it
  raises the ceiling for every job on the host.

Related: [WATCHER_HYGIENE.md](WATCHER_HYGIENE.md) § Optional `/tmp` Cleanup (task-output files) ·
[`../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md`](../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md)
(parallel stacks on one host).
