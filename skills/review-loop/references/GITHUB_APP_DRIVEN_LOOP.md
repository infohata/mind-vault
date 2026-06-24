# Driving the review loop as a GitHub App (bot actor, not a human)

When the agent session authenticates as a **GitHub App installation token** (a
`<your-app>[bot]` actor) instead of a human's `gh auth` — e.g. an unattended /
remote / overnight session whose pushes ride a scoped write App — several GitHub
automation surfaces gate on *human* identity and **silently drop bot actions**.
Each surface below ships unreviewed / un-retriggered / un-recreated with no error.
Recognise the class: "this automation only honours a human push-access actor."

## 1. claude-code-action workflows need an explicit bot allowance — TWO layers

There are two distinct workflows and BOTH must admit the App, by two different
mechanisms:

- **`claude-code-review.yml`** (auto-review on `pull_request` events). The action
  itself has a non-human-actor guard that aborts bot-*opened* PRs ("Workflow
  initiated by non-human actor") → the PR ships **unreviewed**. Fix: set
  `allowed_bots: '<your-app>[bot]'` in the action's `with:`. Scope to your ONE
  App — NOT `'*'` — so dependabot/renovate PRs don't auto-trigger metered reviews.
  (This half is the canonical [`engine-claude-onboarding.md`](engine-claude-onboarding.md)
  § allowed_bots — it covers the bot-*opened*-PR review case; the `claude.yml`
  trigger case below is the bot-*driven*-retrigger follow-on.)

- **`claude.yml`** (interactive `@claude` trigger — this is what the loop's
  **retrigger** uses: `tools/claude_retrigger.sh` posts `@claude review once`).
  The job `if:` typically gates on
  `author_association ∈ [OWNER, MEMBER, COLLABORATOR]`. **An App/bot comment is
  `author_association=NONE`**, so the agent-issued retrigger is silently dropped
  and the App cannot drive its own review loop. Fix needs BOTH:
  1. an exact-login OR-clause in the job `if:` for each comment/review event —
     `… || github.event.comment.user.login == '<your-app>[bot]'`
     (and `review.user.login` / `issue.user.login` for the other event kinds);
  2. `allowed_bots: '<your-app>[bot]'` on the action too (its own guard runs
     *after* the job `if:` admits the actor).

  **Scope to your single trusted App by exact login, never `'*'`.** The
  author_association gate exists partly because a *review* bot (Copilot, etc.)
  quotes the literal "@claude" in its review of these very files and false-triggers
  the workflow; an exact-login allowance keeps that protection (a random bot still
  fails the match) while admitting your one controlled App whose key only the agent
  host holds.

- **Both files must live on the DEFAULT branch to take effect.** `claude-code-action`
  validates `claude-code-review.yml` byte-for-byte against the default-branch copy
  (anti-tampering), so a feature-branch edit 401s; and the trigger config is read
  from default-branch regardless. ⇒ the bot-allowance is itself a chicken-and-egg:
  until the amendment is on `main`, the App still can't retrigger the very PR that
  carries the amendment — that PR's final verdict needs one human `@claude review once`.

## 2. Dependabot slash-commands are human-only

`@dependabot recreate` / `rebase` / `merge` posted by a bot/App actor are
**rejected**: *"Sorry, only users with push access can use that command."*
Dependabot requires a human push-access user; App write access is not accepted
(no `allowed_bots` equivalent exists). ⇒ after a base-branch move invalidates
open dependabot PRs (conflicts), the **recreate must be issued by a human**, not
the agent. See [`../../dependabot-triage/SKILL.md`](../../dependabot-triage/SKILL.md).

## 3. `gh` CLI on unattended/agent hosts — mint a token before any gh call

On an agent host `gh` is usually not `gh auth login`'d and `GH_TOKEN` is unset, so
`gh` calls fail (`gh release create`, `gh pr …`) — **even though `git push`
succeeds**, because git uses its own credential helper while gh does not read it.
Symptom: `To get started with GitHub CLI, please run:  gh auth login`.

Fix: before any `gh` invocation, run an auth-ensure shim that mints a short-lived
installation token from the same git-credential App helper and exports it as
`GH_TOKEN` (gh reads `GH_TOKEN` automatically). Gate it so it is a no-op when a
token is already present or gh is already authenticated, and overridable/absent-safe
so it ports to machines without the App:

```bash
ensure_gh_auth() {
    [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]] && return 0
    gh auth status >/dev/null 2>&1 && return 0
    local helper="${GH_APP_CREDENTIAL_HELPER:-$HOME/.local/lib/deploy/git-credential-github-app}"
    local envfile="${GH_APP_ENV_FILE:-$HOME/.config/<app>/app.env}"
    [[ -x "$helper" && -r "$envfile" ]] || return 0   # no App here → fall through to gh's own auth
    local token
    token=$(printf 'protocol=https\nhost=github.com\n\n' \
        | "$helper" "$envfile" get 2>/dev/null \
        | awk -F= '/^password=/{print $2}') || token=""   # load-bearing: split local+assign
    [[ -n "$token" ]] && export GH_TOKEN="$token"          # doesn't get `local`'s exit-0 mask,
    return 0                                               # so under set -euo pipefail a helper
}                                                         # failure would abort without `|| token=""`
```

The `|| token=""` is load-bearing: a split `local token` + `token=$(pipeline)`
does NOT inherit `local`'s exit-0 masking, so under `set -euo pipefail` a non-zero
from the helper aborts the whole script before the graceful empty-token fallback.

## 4. App installation tokens lack CI-read scopes — CI state is invisible

An installation token scoped `contents` + `pull_requests` (+ `workflows`) write
typically has **no `checks:read` / `actions:read`**. So `gh pr checks`, and the
`commits/{sha}/check-runs`, `check-suites`, `commits/{sha}/status`, and
`actions/.../runs` REST endpoints all return **403 "Resource not accessible by
integration"**. You CAN read PR review **comments** (the issue/PR comments API) but
NOT the CI run/check state. ⇒ when running the loop as the App, read engine verdicts
from **comments**, not check-runs (the SKILL's check-run-status state machine
degrades to comment-polling); or grant the App `checks:read`/`actions:read`. A
human-`gh` loop sees check-runs fine — this gap is App-token-specific.

## Quick triage

| Surface | Bot actor blocked because | Unblock |
| --- | --- | --- |
| `claude-code-review.yml` auto-review | action non-human guard | `allowed_bots: '<your-app>[bot]'` (default branch) |
| `claude.yml` `@claude` retrigger | `author_association=NONE` + action guard | exact-login OR in `if:` + `allowed_bots` (default branch) |
| `@dependabot recreate/rebase` | human-push-access-only, no override | human issues it |
| `gh release/pr …` on agent host | gh unauth, GH_TOKEN unset | `ensure_gh_auth` mints installation token |
| `gh pr checks` / check-run/status APIs | token lacks `checks:read`/`actions:read` | read comments instead, or grant scopes |
