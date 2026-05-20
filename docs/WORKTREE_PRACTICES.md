# Parallel worktrees

`git worktree` lets multiple branches of the same repo coexist on disk simultaneously, each in its own directory. mind-vault uses worktrees aggressively for parallel IDEA work — each worktree is an isolated dev environment with its own docker stack, its own `.env`, its own port range.

## Why worktrees beat branch-switching

The naive flow — `git checkout other-branch`, work, `git checkout original-branch` — has three failure modes:

1. **Container state drift** — docker compose stays running. A migration ran on branch A's schema; you switch to branch B which expects the pre-migration schema. The DB and the code disagree.
2. **Editor / language-server reload churn** — switching branches invalidates every open file's syntax tree, every running test watcher, every dev-server hot reload state.
3. **Mental context loss** — half-finished WIP on branch A is invisible (or worse, on a stash you forget about) while you work branch B.

Worktrees solve all three: branch A and branch B each live in their own directory, with their own docker project, their own editor session if you want one.

## When to use a worktree

✅ **Yes** when:

- You need to work two IDEAs in parallel today.
- `/sprint-auto` is running unattended — it creates per-IDEA worktrees + an integration worktree.
- You need to spot-check a fix on a stale branch without disturbing your current dev environment.
- You want to run the test suite against `origin/main` while your feature branch sits dirty.

❌ **No** when:

- Quick one-line edit on a different branch (just stash, checkout, edit, checkout back).
- The branches don't actually need parallel isolation (same code, same DB).
- Disk space is tight — each worktree is a full repo checkout plus a docker volume set.

## The basic pattern

```bash
# Create a worktree at ../mind-vault-idea-007 for branch feat/idea-007
git worktree add ../<repo>-<slug> feat/idea-007

# Switch shell into it
cd ../<repo>-<slug>

# Run docker compose with a project-namespaced prefix so volumes don't collide
COMPOSE_PROJECT_NAME=<repo>-idea-007 docker compose up -d

# Work normally — commits, tests, etc. — all isolated from the primary tree

# When done (PR merged):
cd ../<repo>           # back to primary
git worktree remove ../<repo>-<slug>
# or, if it had unmerged changes:
git worktree remove --force ../<repo>-<slug>
```

## Port-offset discipline

Two docker stacks can't bind the same host port. If your `docker-compose.yml` exposes `8000:8000`, the second worktree's stack will fail to start.

The mind-vault convention: every worktree gets a **port offset** that shifts all exposed ports. The primary tree binds the documented defaults (8000, 5432, 6379, ...); each worktree adds 10000, 20000, 30000, ... to every host port.

```yaml
# docker-compose.override.yml (per-worktree)
services:
  web:
    ports:
      - "${WEB_HOST_PORT:-8000}:8000"
  db:
    ports:
      - "${DB_HOST_PORT:-5432}:5432"
  redis:
    ports:
      - "${REDIS_HOST_PORT:-6379}:6379"
```

```bash
# Worktree-local .env
WEB_HOST_PORT=18000
DB_HOST_PORT=15432
REDIS_HOST_PORT=16379
COMPOSE_PROJECT_NAME=myproj-idea-007
```

sprint-auto's integration worktree uses the **+30000** offset by convention (`38000`, `35432`, `36379`) so it doesn't collide with primary, idea-A, or idea-B worktrees.

## `.env` isolation — the off-limits-with-an-exception rule

mind-vault's global rule: **the agent never reads, writes, or copies `.env` files**. Worktrees get a narrow, codified exception:

If `.env` is missing inside a worktree and `.env.template` exists:
- Copy template → `.env`.
- Replace `*_API_KEY=` / `*_TOKEN=` / `*_SECRET=` values with `test-not-a-real-key`.
- Replace `SECRET_KEY=` with `test-$(openssl rand -hex 16)`.
- Scope DB/Redis URLs to the worktree's docker compose project namespace.

This is bootstrap-only — for disposable test-data stacks. **Never read or copy from the primary checkout's `.env`.** Never populate real credentials. Never apply this exception in the primary working tree.

The rule is auto-enforced by `/bugbot-loop` and `/copilot-loop`'s Phase 0 worktree bootstrap. See [global `CLAUDE.md` § Guardrails](../CLAUDE.md.example) for the canonical wording.

## sprint-auto's integration-worktree pattern (v3.1+)

When `/sprint-auto` runs a cohort of N IDEAs overnight, it creates N+1 worktrees:

- **N per-IDEA worktrees** — pure *code surfaces*, no docker stack, no `.env`. They exist for `git` operations only (branch, commit, push). The bugbot / copilot loops detect the `SPRINT_AUTO_INTEGRATION_WORKTREE` env var and skip Phase 0 entirely on per-IDEA worktrees.
- **1 integration worktree** at the +30000 port offset — the ONE worktree with a running docker stack. All test verification routes here. DB state is reset between IDEAs (S1.5) so each IDEA's PR is independently deliverable when reviewed in isolation.

This is *the* lever that makes overnight runs cheap: only one container stack to spin up + tear down across N IDEAs.

## Editor + worktrees

Each worktree opens in its own editor window with its own language-server instance. Recommendations:

- **VS Code / Cursor**: open each worktree as a separate window. Workspace settings (`.vscode/settings.json`) commit naturally.
- **Vim / Neovim**: spawn one tmux pane per worktree.
- **Claude Code**: launch one `claude` instance per worktree from inside that worktree's directory. The host detects you're in a worktree (`git rev-parse --git-common-dir` differs from `.git`) and `/bugbot-loop` etc. apply the worktree-specific bootstrap.

## Teardown — non-trivial

When the PR merges and you want to clean up:

```bash
cd ../<repo>                           # always tear down from primary, not from inside the worktree
docker compose -p <repo>-idea-007 down -v   # -v drops the volume too
git worktree remove ../<repo>-<slug>
git branch -d feat/idea-007 2>/dev/null || git branch -D feat/idea-007
                                       # squash-merged branches need -D
```

The `-v` is important: docker volumes survive `down` by default, and a stale volume on next worktree-create-with-same-name will mount yesterday's DB into today's branch.

sprint-auto handles all of this automatically in its `--cleanup` phase. Manual worktree-management workflows need the teardown discipline by hand — easy to forget, common cause of "why is my new IDEA's DB full of old IDEA's test data".

## Disk-space watch

A worktree of a typical Django project: ~500MB code + ~2GB docker volume = ~2.5GB per worktree. Five active worktrees = ~12GB. Plan accordingly on laptops with small SSDs. `du -sh ../<repo>-*` to audit.

## What can go wrong

| Symptom | Cause | Recovery |
| --- | --- | --- |
| `git worktree add` errors "branch already checked out" | The branch IS checked out — in the primary tree or another worktree | `git worktree list` to find where; either work there or `git worktree remove` first |
| Port collision on docker compose up | Two worktrees forgot the port-offset convention | Set the worktree-local `*_HOST_PORT` env vars |
| Test data mysteriously shared between worktrees | Both stacks pointing at the same DB (forgot `COMPOSE_PROJECT_NAME`) | Set `COMPOSE_PROJECT_NAME=<unique-per-worktree>` in worktree's `.env` |
| Worktree directory exists but `git worktree list` doesn't show it | Manual `rm -rf` instead of `git worktree remove` | `git worktree prune` to clean up the metadata |
| `.env` missing in worktree, agent stalls | Phase 0 worktree-bootstrap rule not honoured by current host | See [global `CLAUDE.md`](../CLAUDE.md.example); manual `cp .env.template .env` + sanitise |

## See also

- [`rules/RULE_git-safety.md`](../rules/RULE_git-safety.md) — branch-write rules apply per-worktree.
- [`skills/sprint-auto/SKILL.md`](../skills/sprint-auto/SKILL.md) — the canonical multi-worktree consumer.
- [GIT_WORKFLOW.md](GIT_WORKFLOW.md) — branch + PR pattern that worktrees enable.
- Git official: <https://git-scm.com/docs/git-worktree>
