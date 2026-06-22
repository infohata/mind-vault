# GitHub App git credentials — deploy (read-only) + automation (write + PR)

How a server authenticates to GitHub **without a personal SSH key or PAT standing on the
box**. A personal credential on a server is a supply-chain risk (own the box → push to the
repo), a key-custody gap, and the opposite of dev-agnostic (tied to one human). The
replacement is a **short-lived GitHub App installation token minted on-box** from a local
App private key, wired as a git credential helper.

Two cases, one mechanism:

- **Deploy case (read-only)** — a deployed checkout that must **pull but never push**. Token
  scope tops out at `contents:read`.
- **Agent/automation case (write + PR)** — an unattended host (CI runner, an agent box) that
  **pushes branches and opens/merges PRs** through the App identity, with no human GitHub
  login and no `gh` auth on the box. Scope `contents:write` + `pull_requests:write`.

> **Deploy keys are commonly org-disabled** — don't reach for them first. This is the
> App-installation-token pattern. Related: [`ROOTLESS_DOCKER.md`](ROOTLESS_DOCKER.md) (the
> same non-root deploy user usually runs rootless Docker too), [`CICD.md`](CICD.md),
> [`HARDENING.md`](HARDENING.md).

## The security invariant — one App per trust level (two Apps, not one)

**A GitHub App's permission set is the ceiling for anyone holding its private key.** Per-mint
token down-scoping (requesting fewer permissions in the `access_tokens` call) is **hygiene,
not a boundary** — whoever holds the `.pem` can mint a token at the App's full declared
ceiling any time.

Each box self-mints from a **local** key. So a box only stays read-only-against-compromise
if **its App tops out at `contents:read`**. You therefore cannot serve a read-only deploy box
and a write-capable automation host from one write App "that agrees to mint read tokens for
deploys" — a deploy-box compromise would mint write. **Two trust levels → two Apps:**

| | Deploy App | Automation App |
|---|---|---|
| Declared ceiling | `contents:read` (+`metadata:read`) | `contents:write`, `pull_requests:write` (+`workflows:write` only if it edits workflows) |
| Lives on | the deploy host (non-root deploy user) | the automation host |
| Can it push? | **No** — the API caps at the read ceiling | Yes |
| Blast radius if the `.pem` leaks | read-only clone | write to the installed repo(s) |

Install each App on **only** the repo(s) that box touches, never "all repositories". The App
ceiling is the real boundary; the helper's per-mint scope env is defense-in-depth on top.

## The on-box mint — a stateless credential helper

git invokes a configured credential helper with the operation appended, so a helper sees its
configured arg(s) plus `get|store|erase` as the final arg. On `get` it mints a short-lived
installation token and prints `username=x-access-token` / `password=<token>`; `store`/`erase`
are no-ops. **Nothing is cached to disk** — no token at rest.

The mint is dependency-light (`openssl` + `curl` + `python3`; no `jq`, no `gh`, no stored
token): build an RS256 JWT (`{"alg":"RS256","typ":"JWT"}` header; payload `iat`=now−60,
`exp`≤now+600, `iss`=App ID; sign with `openssl dgst -sha256 -sign <key.pem>`, base64url each
part), then `POST /app/installations/<install-id>/access_tokens` with `Authorization: Bearer
<jwt>` and a body of `{"permissions":<scope-json>}` to down-scope. Extract `.token` from the
JSON.

Make the per-mint scope an env var (default `{"contents":"read"}`), passed straight to the
`access_tokens` call. **It can only down-scope** — the API caps the request at the App's
declared ceiling — which is what lets **one helper binary serve both cases**: deploy uses the
read default; automation sets `{"contents":"write","pull_requests":"write"}`.

Hardening worth baking in (learned via review): **validate the App ID / installation ID are
numeric** before interpolating them into the JWT/URL (a mistyped id should fail clearly, not
produce a malformed JWT or a confusing 404); and **bound the mint `curl`** with
`--connect-timeout`/`--max-time` so a hung GitHub API call can't stall an unattended `git
fetch` indefinitely (`-f` fail-fasts on HTTP errors but not on a connection stall).

**Discovering the installation id** (you don't need it up front): mint the JWT from the
`.pem` and `GET /repos/<owner>/<repo>/installation` → `.id`.

## Case A — deploy credential (read-only)

1. Create the App with **Contents: Read-only** (Metadata: Read-only comes automatically),
   nothing else. Install on only the target repo. The `.pem` is the only secret.
2. Place key + env + helper (unprivileged layout below). Wire the helper repo-local.
3. Switch the remote SSH → HTTPS; retire the personal key (rename, don't delete, until
   proven).
4. **Verify** the App fetch works **both with and without** the old personal key present (so
   it's genuinely the App, not a lingering SSH fallback); a push is denied; no token persists.

## Case B — automation credential (write + gh-less PR)

1. Create the App with **Contents: Read & write** + **Pull requests: Read & write** (+
   **Workflows: Read & write** only if it edits `.github/workflows/**` — see Gotchas). Install
   on the target repo(s).
2. Same placement + wiring as Case A, but set the write scope in the env:
   `DEPLOY_TOKEN_PERMISSIONS='{"contents":"write","pull_requests":"write"}'`.
3. **Open + merge PRs gh-less.** With the installation token the host drives the GitHub REST
   API directly — create branch refs, open PRs, merge — with no `gh` login. The token is the
   same `password` the helper emits; reuse the mint for API calls. (Proven: a PR opened from an
   automation host with `gh` logged out, authenticated purely by the App token.)
4. **Enforce branch protection** so the automation's writes land only via reviewable PRs,
   never direct pushes to the protected branch.
5. **Verify**: the host can push a branch + open a PR; a direct push to the protected branch is
   rejected (`GH013`).

## Unprivileged deploy-user wiring (the proven default)

Default to the **non-root deploy user** layout — a non-root user can't write `/usr/local/lib`
or `/etc`, so keep the binary, env, and key under the deploy user's `$HOME` (mode 700 dir, 600
files). This is the realistic case and pairs naturally with rootless Docker on the same box.

Two wiring gotchas that silently no-op if missed:

- **git matches credentials by HOST, not path**, unless `credential.useHttpPath=true` (default
  false). A path-qualified key (`credential.https://github.com/<owner>/<repo>.helper`) is
  **silently ignored** on a single-repo box — use the **host-level**
  `credential.https://github.com.helper`. (Multi-repo host: set `useHttpPath=true` + one
  path-qualified key per repo.)
- **A `$HOME`-relative helper value only expands when run via a shell** — i.e. prefix the
  value with `!`. A bare absolute path is `exec`'d **without** a shell, so `$HOME`/`~` would
  not expand. So the home-relative form needs the `!`-shell prefix:

  ```bash
  git -C <checkout> config credential.https://github.com.helper \
    '!$HOME/.local/lib/deploy/git-credential-github-app $HOME/.config/<repo-slug>/<repo>.env'
  ```

  A root-owned shared install (`/usr/local/lib/...` binary, `/etc/...` env) uses a **bare
  absolute path** (no `!`, no `$HOME`). Prefer the unprivileged layout unless a root-owned
  shared install across deploy users is genuinely warranted.

Wire the helper **repo-local** (`git -C <checkout> config`), never global/system — a global
credential.helper would mint App tokens for every github.com pull on the box.

> **If your audit/inventory tooling classifies the deploy mechanism by matching the configured
> `credential.*.helper` value, don't rename the helper binary** once that marker is in place —
> the basename in the helper value is the load-bearing signal.

## Gotchas (each cost a debugging cycle)

1. **Write Apps need `workflows:write` to touch `.github/workflows/**`.** GitHub **refuses**
   any push *or merge* that creates/updates a workflow file unless the App was granted
   Workflows permission (`refusing to allow a GitHub App to ... workflow ... without workflows
   permission`) — this bites both a direct push and a PR-merge that carries a workflow change.
   Either grant the write App `workflows:write`, or route workflow-file changes through a
   human/web path. Read-only deploy Apps are unaffected (pull-only).

2. **Branch protection isn't free on private repos.** A **Free-plan private** repo does **not**
   enforce branch-protection rules / rulesets — a direct push to a "protected" branch is
   silently accepted, making any "automation can only land via PR" invariant inert. Use a paid
   (Pro/Team) or org repo and add a **ruleset** on every protected branch (e.g. `main` *and*
   the deploy branch). Verify by attempting a direct push and confirming `GH013` rejection.

3. **An unattended agent host may be policy-blocked from production writes.** When an
   automation agent's own host sandbox forbids writing to prod (remote-shell writes, running a
   deploy script, merging protected branches all denied), design the flow so a **human runs the
   prod-side install/cutover/deploy/merge** while the agent prepares the exact commands, PRs,
   and discovery. Don't assume an agent can self-serve a prod change.

4. **A bot-opened PR may be skipped by a bot-authored review engine** unless that engine is
   explicitly told to review bot actors — see the review-loop claude engine's `allowed_bots`
   note. A fully-automated "App opens PR → engine reviews it" flow ships **un-reviewed** until
   that's set.

## Verify (the load-bearing proof)

```bash
# Deploy (read-only): fetch works under the App token, BOTH with the old personal key present
# AND after it's renamed away — so the fetch is genuinely the App, not a lingering SSH key.
git -C <checkout> fetch origin <branch>     # run before AND after retiring the personal key
git -C <checkout> push 2>&1 | grep -qiE 'denied|read-only|403|not permitted' \
  && echo "OK: push denied (read-only)"
! grep -rqa 'ghs_' <checkout>/.git && echo "OK: no token at rest"

# Automation (write): push a branch + open a PR succeeds; a direct push to the protected
# branch is rejected with GH013.
```

Retire the old personal credential by **rename, not delete** (reversible) until the App path
is proven; only then remove it. Confirm no SSH agent-forwarding onto prod (a sudoer with their
own creds + agent-forwarding could still `git remote add` a writable URL — the documented
residual; pair the read-only remote with server-origin-push detection in your audit).
