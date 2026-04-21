# sprint-auto — worktree lifecycle

The skill calls into a project-local `tools/sprint-auto-bootstrap.sh`, which is a **thin wrapper** around the canonical script that lives in mind-vault. The wrapper + canonical split gives the same benefit as symlinking (updates to mind-vault propagate to every project) without the symlink's biggest failure mode: when mind-vault isn't at the expected path (fresh VPS, CI runner, different user), a symlink gives a cryptic "file not found"; a wrapper prints an actionable error with remediation steps.

The 80% of bootstrap logic that's identical across Docker projects lives in the canonical script. The 20% that's genuinely project-specific (MinIO bucket setup, custom migrations, ES index creation, smoke test URL) lives in an optional project-local `tools/sprint-auto-hooks.sh` that the canonical script sources.

## Layout

```text
mind-vault/
  tools/
    sprint-auto-bootstrap.sh          ← canonical implementation (lives here)
  skills/sprint-auto/
    assets/
      sprint-auto-bootstrap.sh.wrapper  ← template; projects copy → tools/sprint-auto-bootstrap.sh
      sprint-auto-hooks.sh.example      ← template; projects copy → tools/sprint-auto-hooks.sh (optional)

<your-project>/
  tools/
    sprint-auto-bootstrap.sh          ← thin wrapper, committed to project, ~30 LOC
    sprint-auto-hooks.sh              ← optional project-specific hooks
```

## Setup — one-time per project

```bash
# From the project's primary checkout
cp ~/projects/mind-vault/skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper \
   tools/sprint-auto-bootstrap.sh
chmod +x tools/sprint-auto-bootstrap.sh
git add tools/sprint-auto-bootstrap.sh
git commit -m "chore: wrapper for mind-vault sprint-auto-bootstrap"

# Optional: if the project needs post-up init (MinIO, migrations, seed fixtures) or a
# custom smoke test, copy the hooks template and edit:
cp ~/projects/mind-vault/skills/sprint-auto/assets/sprint-auto-hooks.sh.example \
   tools/sprint-auto-hooks.sh
chmod +x tools/sprint-auto-hooks.sh
# Edit tools/sprint-auto-hooks.sh for project specifics, then:
git add tools/sprint-auto-hooks.sh
git commit -m "chore: sprint-auto hooks for <project> (migrations + MinIO + smoke)"
```

**Also add to `.gitignore`** (canonical bootstrap emits this file on every run; header says "do not commit" but each project needs its own gitignore line):

```
# Worktree-local docker compose override emitted by tools/sprint-auto-bootstrap.sh
docker-compose.override.yml
```

Without this line, every `/sprint-auto` cycle leaves an untracked `docker-compose.override.yml` in the worktree that blocks `git worktree remove` at teardown time unless force-flagged — which (per `/wrap` step 5) hides real findings. See teisutis PR #335 for the exact shape of this one-line gitignore followup. A future version of the bootstrap script may grow a preflight that checks for this rule and warns if missing; until then, it's an adoption-checklist item.

## The canonical script's responsibilities

Project-agnostic, runs in every Docker Compose project:

1. **Preflight**: docker present, jq present, `.env.template` exists, `.env` and `docker-compose.override.yml` absent (refuses to clobber).
2. **Sentinel `.env`**: copies `.env.template`, regex-replaces credential-shaped keys (`*_KEY`, `*_SECRET`, `*_TOKEN`, `*_PASSWORD`, `*_PASS`, `*_PWD`, `*_CREDENTIAL`) with `test-not-a-real-key`; generates fresh random `SECRET_KEY` and `*_SALT` / `*_HMAC`; neutralises `user:pass@host` patterns in `*_URL` values.
3. **Port-offset override**: runs `docker compose config --format json` to discover every service with host-port bindings, emits `docker-compose.override.yml` with `ports: !override` blocks shifted by `10000 + (idea_number % 100) * 100`.
4. **Stack up**: `docker compose up -d --wait`, tailing failure output into the auto-run log on exit 1.
5. **Hooks**: if `tools/sprint-auto-hooks.sh` exists, sources it and calls `post_up_init` + `smoke_test` (if declared).
6. **Default smoke**: services-configured count must equal services-running count via `docker compose ps`.

All of this is one script, reused across every project.

## The wrapper's responsibilities

~30 LOC, lives in each project, committed to the project's repo. Signature:

```bash
#!/usr/bin/env bash
# Locate the canonical script; exec into it with args.
set -euo pipefail
CANON_REL="tools/sprint-auto-bootstrap.sh"
candidates=(
  "${MIND_VAULT_ROOT:-}"
  "$(git rev-parse --show-toplevel 2>/dev/null)/../mind-vault"
  "$HOME/projects/mind-vault"
  "$HOME/.local/share/mind-vault"
  "/opt/mind-vault"
)
# find first $candidate/$CANON_REL that's executable, else print an actionable error
# full template: skills/sprint-auto/assets/sprint-auto-bootstrap.sh.wrapper
```

Lookup order: explicit env override → sibling dir of the project → `~/projects/mind-vault` (the user's convention) → `~/.local/share/mind-vault` → `/opt/mind-vault`. If none match, the wrapper prints the list of candidates it searched and the fix command (`git clone ... mind-vault` or `export MIND_VAULT_ROOT=...`).

**Why not just symlink?** Three concrete failure modes the wrapper catches cleanly:

- **Fresh clone on a new machine**: mind-vault not cloned yet → wrapper says "clone it here", symlink gives `ENOENT`.
- **CI runner**: mind-vault lives at a non-standard path → wrapper honours `MIND_VAULT_ROOT` env var, symlink breaks.
- **Mind-vault moved**: user reorganised `~/projects/` → wrapper checks multiple paths, symlink is now dangling.

Updates to the canonical script propagate to every project via `git pull` in mind-vault alone — same benefit as symlinks, without the fragility.

## The hooks file

Project-local. Not a symlink, not a wrapper — a real file, edited in-project. Bash functions:

```bash
# tools/sprint-auto-hooks.sh

post_up_init() {
    # Runs AFTER docker compose up, before smoke test.
    # Idempotent. Return 0 on success, non-zero on failure.
    docker compose exec -T web python manage.py migrate --noinput || return 1
    # ... MinIO bucket setup, seed fixtures, ES indices, etc.
}

smoke_test() {
    # Replaces the canonical's default "all services running" check.
    # Call `default_smoke_test` at the end if you want both.
    docker compose exec -T web curl --fail -s http://localhost:8000/health/ >/dev/null
}
```

See `skills/sprint-auto/assets/sprint-auto-hooks.sh.example` for a fuller template.

**Why the hooks file is copied, not wrapped**: the content IS the project-specific part. There's nothing to delegate to a canonical version — each project's migrations, fixtures, and smoke-test URL differ. A wrapper would be a wrapper around the project's own code, which is pointless.

## Worktree naming

- **Path**: `../<project>-auto-<slug>/` — sibling of the primary checkout. `-auto-` prefix distinguishes machine-created worktrees from human-created ones for filtering in `git worktree list` and teardown scripts.
- **Branch**: `auto/<slug>`. Distinctly prefixed; a human continuing the work can rebase or rename later.
- **Both** use `<slug>` (not the IDEA number) so they read well in `git worktree list` and `gh pr list`.

## The port-offset strategy

Canonical: `10000 + (idea_number % 100) * 100`.

| IDEA | offset | web (8000 →) | db (5432 →) |
|---|---|---|---|
| 050 | +15000 | 23000 | 20432 |
| 051 | +15100 | 23100 | 20532 |
| 099 | +19900 | 27900 | 25332 |
| 100 | +10000 | 18000 | 15432 |
| 150 | +15000 | 23000 | 20432 — **collides with 050** |

Collisions are real but rare in a single overnight batch. A future hardening: the canonical script can detect a port-in-use and bump by +10000 until clear, recording the actual offset in the auto-run log. For v1 the naive offset is fine — curate the overnight batch list to avoid modulo-100 collisions.

## Teardown policy — don't

The skill does not teardown after a run. Preserving state is the whole point of "failure is a diagnostic artefact".

**Success (PR open)**: worktree stays, stack stays up, human merges in the morning then runs the cleanup one-liner from the auto-run log.

**Failure (any)**: same. Human investigates inside the worktree, decides fix-and-retry / abandon / route back through `/plan`.

**Cleanup one-liner** (always written into each auto-run log):

```bash
cd <worktree> && docker compose down -v && cd - && git worktree remove <worktree> && git branch -D auto/<slug>
```

Omit `-v` to keep volumes if the human wants to inspect DB / MinIO state post-failure.

## Fallback when the wrapper is missing

If `tools/sprint-auto-bootstrap.sh` doesn't exist in the project at all, the `/sprint-auto` skill falls back to an inline minimal bootstrap: sentinel `.env`, naive +10000 port offset on common service names (`web`, `db`, `redis`, `elasticsearch`, `minio`), `docker compose up`. **No post-up init** — the fallback cannot know what the project needs.

Tests that depend on fixtures, buckets, or indices will fail in `/work`'s verification, and the IDEA will be skipped. This is why the preflight warns loudly when the wrapper is missing and the scripted path is strongly preferred for overnight batches.

---

**Last Updated**: 2026-04-20 (initial — wrapper pattern, not symlinks; wrappers fail gracefully)
