# sprint-auto — safety gates

Belt-and-suspenders: every IDEA in the batch must pass **all** gates. No single-signal opt-in. Curation is the whole point of this skill — the human decides the list, the frontmatter confirms the decision, and the preflight verifies the IDEA is mechanically suitable for unattended work.

## Per-IDEA opt-in

### Required frontmatter

```yaml
---
# ... standard IDEA fields ...
auto_safe: true
auto_safe_reason: "Pure UI tweak, covered by existing Alpine component tests. No DB or API contract changes."
---
```

- **`auto_safe: true`** — the flag the skill greps for. Missing or `false` → IDEA is rejected from the batch at preflight.
- **`auto_safe_reason`** — one-sentence justification the human wrote when they cleared the IDEA. Required when `auto_safe: true`. Missing → rejected. The field exists so morning-you can reconstruct why overnight-you thought this was safe, without re-reading the whole IDEA body.

### Explicit arg presence

The IDEA slug or number must appear in the `/sprint-auto` invocation's args. There is **no scan mode in v1** — if the human didn't type the slug, the skill will not touch the IDEA, even if `auto_safe: true`. Two independent signals = two independent authorial acts.

## Automatic disqualifiers

Run these checks at preflight. Any fail → IDEA dropped from the batch with a logged reason; the batch continues if ≥1 IDEA survives, aborts if all drop.

| Check | Reason |
|---|---|
| `auto_safe` not true OR `auto_safe_reason` missing | Opt-in not declared |
| Body has fewer than ~3 substantive prose paragraphs | `/plan`'s thin-input bootstrap would fire and block on interactive questions — autopilot cannot answer |
| `status` is not `idea` | Already in-progress / complete / superseded — nothing to run |
| `depends_on` references an IDEA that is not `status: complete` | Pipeline not ready; don't run work that will need to rebase onto unmerged prerequisites |
| IDEA body lists a file path under a sensitive-paths default-deny list | See below — override with explicit frontmatter acknowledgement |

### Default-deny sensitive-path list

Anything the IDEA's body mentions editing under these paths drops it from the batch unless the frontmatter has `sensitive_paths_cleared: true` + `sensitive_paths_cleared_reason: "..."`:

- `.env*` (any env file — the skill is not allowed to read or mutate these per global CLAUDE.md)
- `docker-compose.yml` (base file — override files are fine)
- `docker/` production Dockerfiles (dev Dockerfiles are fine)
- `.github/workflows/` or `.gitlab-ci.yml` (CI/CD pipelines — a bad change here can block every subsequent PR)
- any path containing `migrations/` where the IDEA body suggests a destructive migration (data loss, drop table, drop column) — non-destructive migrations are fine
- auth middleware / permission-check modules (regex: `*auth*`, `*permission*`, `*middleware*` — broad on purpose; the human acknowledges for this class)

The detection is heuristic, not bulletproof. It's a "did you mean to do this?" gate, not a security boundary. False positives are cheap (human adds the acknowledgement frontmatter); false negatives are expensive (bad change lands overnight), so the gate errs on the strict side.

## In-flight halt conditions

These fire during the loop, not at preflight. The skill must recognise them and respond correctly — skip-IDEA vs. abort-batch matters.

### Skip this IDEA, continue batch

- `tools/sprint-auto-bootstrap.sh` exits non-zero (project-local bootstrap broken for *this* slug — maybe this IDEA's branch has a docker-compose change that collides; next IDEA's branch might be fine)
- `/plan`'s architect review returns `REJECTED`
- `/work`'s verification step fails (tests red, build broken)
- Per-IDEA budget exceeded (default 60 minutes wall clock)

Action: record outcome in the per-IDEA auto-run log, leave the worktree intact (diagnostic artefact), move to the next IDEA.

### Abort the entire batch

- Docker daemon became unreachable between IDEAs
- Disk has < 5GB free (subsequent worktrees would fail bootstrap anyway)
- Per-batch budget exceeded
- Two consecutive IDEAs failed at the bootstrap step with the same error class (something environmental changed; not worth burning the remaining budget)
- Exception propagates out of the `plan` or `work` skill in a way that suggests harness/agent state is degraded

Action: write the partial batch summary, stop the loop, print a clear "batch aborted at IDEA-N, reason: X" message, preserve all worktrees.

### Never fires (by design)

These are **not** halt conditions — the skill must carry through them:

- A git commit inside a worktree is rejected by a pre-commit hook → `/work` handles this by fixing the issue and re-committing. Not a batch-level event.
- A persona subagent comes back with a "I'm stuck" response → `/work` already routes this to its Open Questions mechanism, which for autopilot means documenting in the log and moving on.

## The override paths

All overrides live in the IDEA's frontmatter, not the `/sprint-auto` invocation. This keeps the authorial record with the idea itself — the next run (or the human reviewing later) sees exactly what was cleared and why.

```yaml
---
# ... standard IDEA fields ...
auto_safe: true
auto_safe_reason: "Covered by existing tests; bounded to one file."
priority: medium
sensitive_paths_cleared: true
sensitive_paths_cleared_reason: "Touches auth middleware only to rename a logging field — behaviour unchanged, covered by test_auth_logging.py"
---
```

The invocation-level flags (`--budget-minutes=N`) exist for batch-wide concerns (budget), not as a bypass for frontmatter gates.

### Priority is queue order, not a safety gate

`priority: high` / `medium` / `low` affects the order in which the human schedules IDEAs — it does not imply "how dangerous to automate". The authoritative automation-safety signal is `auto_safe: true`, full stop. Stacking priority on top of `auto_safe` as a second gate was confusing (what would a `priority: high` + `auto_safe: true` IDEA even mean — "safe but the human refuses to let the machine touch it"?) and got in the way of the common case where the human deliberately sprint-auto-dogfoods their most-wanted items. Dropped 2026-04-22.

## When the human reviews in the morning

The per-IDEA auto-run log makes review mechanical. Expected fields:

- **Outcome**: ✅ PR open / ⚠️ architect rejected / ❌ verification failed / 🚫 bootstrap failed / ⏱️ budget exceeded
- **PR URL** (if opened)
- **Worktree path** (always present; human `cd`s there to investigate)
- **Diagnostic excerpt** (last 50 lines of `/work`'s test output on failure; the architect's rejection verdict on rejection; the bootstrap script's stderr on bootstrap failure)
- **Cleanup command**: one-liner to tear down the worktree + its docker stack once the human is done (`cd <worktree> && docker compose down -v && cd - && git worktree remove <worktree>`)

---

**Last Updated**: 2026-04-20 (initial)
