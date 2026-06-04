# sprint-auto — safety gates

Belt-and-suspenders: every IDEA in the batch must pass **all** gates. No single-signal opt-in. Curation is the whole point of this skill — the human decides the list, the frontmatter confirms the decision, and the preflight verifies the IDEA is mechanically suitable for unattended work.

## Per-IDEA opt-in

There are two opt-in modes — **`auto_safe`** (autonomous through to merge gate) and **`auto_safe_with_eval_gate`** (autonomous through to merge gate + emit a manual-evaluation checklist for the human reviewer to walk before merging). Sprint-auto includes IDEAs from BOTH modes in the same batch's cohort selection (S0); the only difference downstream is that eval-gate IDEAs additionally emit a checklist artefact at S5 (`/wrap --scope=idea-only`) and the integration PR's body at S11.10 lists each eval-checklist URL.

### Mode A — `auto_safe: true`

```yaml
---
# ... standard IDEA fields ...
auto_safe: true
auto_safe_reason: "Pure UI tweak, covered by existing Alpine component tests. No DB or API contract changes."
---
```

- **`auto_safe: true`** — the flag the skill greps for. Missing or `false` → IDEA is rejected from the batch at preflight (unless Mode B applies — see below).
- **`auto_safe_reason`** — one-sentence justification the human wrote when they cleared the IDEA. Required when `auto_safe: true`. Missing → rejected. The field exists so morning-you can reconstruct why overnight-you thought this was safe, without re-reading the whole IDEA body.

### Mode B — `auto_safe_with_eval_gate: true`

```yaml
---
# ... standard IDEA fields ...
auto_safe: false
auto_safe_with_eval_gate: true
auto_safe_reason: "Implementation is mechanical (cotton template + JS API + tests). Visual / a11y / interaction review needed at integration-PR-merge time."
eval_gate_reason: "Modal primitives ship focus-trap + screen-reader semantics + mobile gesture nuance — render-and-assert tests cannot verify the UX of these. The integration-PR review is the right HITL gate."
---
```

For IDEAs whose **implementation** is mechanical enough to sprint-auto end-to-end, but which ship behaviours that need human eyes on visual / a11y / interaction review before merge. The merge gate (the integration PR per `RULE_git-safety`) is already HITL — eval-gate mode just structures that review by emitting a per-IDEA manual-evaluation checklist for the human to walk. Sprint-auto runs the IDEA all the way through `/wrap` and into integration without pausing.

- **`auto_safe_with_eval_gate: true`** — the second flag. Sprint-auto's S0 cohort selection accepts an IDEA when **either** `auto_safe: true` OR `auto_safe_with_eval_gate: true`.
- **`auto_safe: false`** — explicit, paired with `auto_safe_with_eval_gate: true`. The two flags carry distinct semantics; the eval-gate flag does NOT override `auto_safe`. Both states are independently true.
- **`auto_safe_reason`** — same field, same purpose; required for either mode.
- **`eval_gate_reason`** — additional one-sentence justification specifically explaining what the human needs to walk that automated tests cannot verify. Required when `auto_safe_with_eval_gate: true`. Missing → rejected. The field exists because "needs human eyes" without a reason is too easy to slap on every IDEA — the explicit reason forces the author to think about which residue is genuinely human-only.

The two modes are not a hierarchy — they're orthogonal opt-in signals. An IDEA that's `auto_safe: true` does NOT need the eval-gate (its tests cover everything). An IDEA that's `auto_safe_with_eval_gate: true` does NOT auto-imply `auto_safe: true` (the manual walk is the gate, not the test suite).

### Explicit arg presence (both modes)

The IDEA slug or number must appear in the `/sprint-auto` invocation's args. There is **no scan mode in v1** — if the human didn't type the slug, the skill will not touch the IDEA, even if either opt-in flag is set. Two independent signals = two independent authorial acts.

## Playwright-availability gate (`requires_playwright`)

Direction-1 (Playwright-driven browser tests) introduces a third frontmatter flag — orthogonal to `auto_safe` and `auto_safe_with_eval_gate`, **not** a fourth opt-in mode and **never** a disqualifier:

```yaml
---
# ... standard IDEA fields ...
auto_safe: false
auto_safe_with_eval_gate: true
auto_safe_reason: "..."
eval_gate_reason: "..."
requires_playwright: true   # IDEA wants Playwright tests for its surface
---
```

**Semantics — three branches** (decided by combining the frontmatter flag with sprint-auto's S(-1) probe outcome — see [`../SKILL.md`](../SKILL.md) § 1 step 9):

| Probe outcome | `requires_playwright` | Behaviour |
|---|---|---|
| Present | `true` | Plan author writes Playwright tests in the Verification section + a `playwright_test_coverage` YAML block. `/wrap` Step 7 pre-fills covered eval-checklist rows. |
| Absent | `true` | Plan author writes ONLY manual-eval-checklist rows for Playwright-relevant scenarios. The flag stays as a backref so a later "set up Playwright" IDEA can backfill tests for these scenarios. **The IDEA still ships through sprint-auto with eval-gate as today.** |
| (any) | unset / `false` | IDEA proceeds independent of Playwright state. Most IDEAs. |

**Why `requires_playwright` is NOT a disqualifier**: the bootstrap circularity argument from the ROADMAP. If the flag *did* disqualify when probe = absent, the very first project setting up Playwright would be unable to ship the IDEA that provisions Playwright (probe is absent until that IDEA merges). The manual-eval-only fallback closes the loop — every IDEA that mentions Playwright still ships, just with rows that say "manual walk needed" until the infra catches up. After the first project-side `setup_playwright.sh` IDEA merges, downstream IDEAs' probes flip to "present" and the gate begins pre-filling test-covered rows.

**Defence in depth at S2** (per [`../SKILL.md`](../SKILL.md) step 4): `/work` re-probes Playwright availability before running tests; a probe failure between S(-1) and S2 (rare; image rebuild or container reset) logs `playwright_unavailable: true` to the auto-run log, skips Playwright tests for that IDEA, continues with non-Playwright tests. The integration PR's S11.10 evaluation summary surfaces the warning.

**Out of scope for this gate**: deciding *whether* a specific IDEA wants Playwright tests. That's a `/plan`-time architect decision (see [`../../../agents/AGENT_architect.md`](../../../agents/AGENT_architect.md) — the architect probes the project, asks whether the IDEA's deliverable surfaces want browser-test coverage, and proposes adding `requires_playwright: true` to the frontmatter). Once the flag is in the IDEA, this gate just routes; it doesn't author.

## Automatic disqualifiers

Run these checks at preflight. Any fail → IDEA dropped from the batch with a logged reason; the batch continues if ≥1 IDEA survives, aborts if all drop.

| Check | Reason |
|---|---|
| Neither `auto_safe: true` NOR `auto_safe_with_eval_gate: true` declared | Opt-in not declared (one of the two modes is required) |
| `auto_safe_reason` missing | Required for either mode |
| `auto_safe_with_eval_gate: true` AND `eval_gate_reason` missing | Eval-gate mode requires an explicit "what's the manual walk for" reason |
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
