# engine-claude — onboarding a project to the Claude review engine

How to wire the Claude engine into a new project so `/review-loop <PR> claude`
works AND can actually post findings. The short version: **don't trust
`/install-github-app`'s default output — commit our own write-perm, guarded
workflows to the default branch.** The long version is the bootstrap catch-22
below, which is the single most surprising part.

## The four-step setup

1. **Workflows** — copy the canonical templates from this skill's assets into the
   project's `.github/workflows/`:
   - [`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) — auto-review on push (action + `code-review` plugin), `pull-requests: write`, fork-PR guard.
   - [`../assets/claude.yml`](../assets/claude.yml) — `@claude` assistant, `pull-requests: write`, author-association gate.
   `/install-github-app` is fine for *dropping* the two files and wiring the
   secret, but its templates ship `pull-requests: read` and an ungated `@claude`
   trigger — **immediately replace both with the asset templates** (or run the
   install then overwrite). Do NOT ship the read-only default (next section).
   Both templates pin the review models (§ Choosing the review model).
2. **Tools** — port `tools/find_claude_comments.sh` + `tools/claude_retrigger.sh`
   from mind-vault `tools/` into the project's `tools/`, **verbatim** (byte-identical,
   same as the bugbot/copilot scripts — keeps future mind-vault fixes a trivial re-copy).
   `chmod +x` both. The existing `Bash(./tools/*.sh:*)` allowlist (if present) covers them.
3. **Secret** — wire `CLAUDE_CODE_OAUTH_TOKEN` (the install step does this).
4. **Land on the DEFAULT BRANCH.** The workflow perms only take effect from the
   default branch (next section). Onboarding is a setup commit/PR to `main` (human-merged
   per RULE_git-safety), not a feature-branch change.

After merge: `find_claude_comments.sh <open-PR>` should stop emitting
`CLAUDE_NOT_INSTALLED=true`, and a push to any **ready-for-review** PR auto-runs the review
**with posting rights**. ⚠️ **Draft PRs get no posted review** — the run fires and concludes
`success` but posts nothing (reads SILENT); mark the PR ready-for-review before trusting a
verdict. See [`engine-claude.md`](engine-claude.md) § Push-triggered model.

## Why read-only is a trap, not a safe default

`/install-github-app` ships `pull-requests: read` / `issues: read`.
`anthropics/claude-code-action` posts inline review comments via the workflow
`GITHUB_TOKEN` — with read-only it **cannot post**. The failure is silent and
worst-case directional: a findings-bearing run finds issues, fails to post them,
and `find_claude_comments.sh` sees zero inline comments → reports a **FALSE CLEAN**
via the zero-inline arm. "Read-only + clean" does NOT mean "reviewed fine"; it
means "may have found problems and dropped them on the floor." Always run with
`pull-requests: write` + `issues: write`. (A genuinely-clean *write*-perm run and
a posting-blocked *read*-perm run are indistinguishable from the outside — which is
exactly why read-only is unsafe.)

## The anti-tampering bootstrap catch-22

`claude-code-action` validates that the `claude-code-review.yml` running on a PR is
**byte-identical to the copy on the repository's default branch** — a security guard
so a PR can't escalate its own workflow's permissions. Consequences, all observed:

- **You cannot change the perms from a feature branch.** Editing the workflow on a
  feature branch makes it differ from the default-branch copy → the action fails
  with *"Workflow validation failed. The workflow file must exist and have identical
  content to the version on the repository's default branch."* (`completed/failure`,
  not a review). The error message itself says this is normal on first-add and to ignore it.
- **The perms change must land on the DEFAULT BRANCH via its own PR.** And that PR's
  *own* Claude run fails the same validation (its workflow differs from the
  not-yet-updated default branch) — a **benign, expected red ✗**. Merge through it
  (it's the bootstrap; no required check blocks it on a private-repo/no-branch-protection
  setup — verify with `gh api repos/:owner/:repo/branches/<default>/protection`).
- **After the default branch has write perms, every in-flight feature branch must
  forward-sync it** (`git merge origin/<default>`) so its workflow copy matches —
  otherwise Claude fails validation there too. A 3-way merge keeps the default
  branch's write version as long as the feature branch never authored a competing
  perms edit.

**Shipping the write-perm asset templates at onboarding (step 1, on the default
branch) avoids this entire dance for new projects** — write is the baseline from day
one. The catch-22 only bites when *retrofitting* a project already running the
read-only default (raise the perms via one default-branch PR, then forward-sync open branches).

**Not perms-specific — ANY edit to these two files triggers it.** The validation is
byte-identity, so a `actions/checkout` version bump, a comment tweak, or whitespace
fails identically. The **most common post-onboarding trigger is a dependabot
workflow-action bump** (`actions/checkout v4 → v6` etc.): the same three rules apply —
(1) it can only land on the **default branch** (a feature-branch PR carrying it 401s,
including any consolidated deps PR — so split the workflow bump out and send it to the
default branch on its own); (2) that default-branch PR's own Claude check **red-✗es by
design** — merge through; (3) once merged, **every active feature branch red-✗es until
it forward-syncs** (anti-tampering needs PR-head workflow == default branch), so a
single default-branch workflow bump has a fan-out cost across all open branches. Because
v4 is functionally fine, weigh whether a cosmetic action-version bump is worth the
dance — or batch it with the next forward-sync wave.

## Repo-level setting (usually already correct)

`gh api repos/:owner/:repo/actions/permissions/workflow` →
`default_workflow_permissions` is typically already `write`. That is NOT the cap —
the **workflow-level** `permissions:` block overrides it downward, which is why the
read-only template is the real bottleneck. `can_approve_pull_request_reviews: false`
is irrelevant (that gates PR *approval*, not posting review comments).

## Choosing the review model

Both templates pin models. Without a pin, the run uses whatever default ships in the
Claude Code bundled with the pinned action version, which lags: mind-vault's own runs
on `v1.0.133` logged `claude-sonnet-4-6` in October 2026. There are two settings, and a
real upgrade needs both:

- **`--model <id>` in `claude_args`** sets the top-level session. In `claude-code-review.yml`
  that session orchestrates the `code-review` plugin. In `claude.yml` it writes the
  `@claude review once` reply itself.
- **`ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` in the step's `env:`** decide what
  the plugin's helper agents run on. The plugin launches them by alias (upstream
  `plugins/code-review/commands/code-review.md`, restructured 2026-01, unchanged since
  2026-03). Haiku agents check eligibility and list CLAUDE.md files. One Sonnet agent
  summarizes the PR and two Sonnet agents check CLAUDE.md compliance. **Two Opus agents
  hunt bugs**, and a validator subagent re-checks each bug candidate. The aliases resolve
  through these variables, which the action forwards (`action.yml`, the
  `ANTHROPIC_DEFAULT_*` passthrough). **`--model` alone upgrades the orchestrator, but
  the agents that find the bugs stay on the old model.** The templates install the plugin
  from the marketplace tip with no ref, so re-read that file when the review's behavior
  shifts. A cached local copy can be months stale.

Current pins: session and sonnet alias `claude-sonnet-5-5`, opus alias `claude-opus-5-5`,
haiku alias `claude-haiku-4-5-20251001`. Use full model IDs, not aliases like
`opus`. An old bundled CLI maps an alias to whatever model was current when that CLI
shipped.

- **Which pin sets what.** The token is subscription-billed, so every review spends
  plan quota. **`ANTHROPIC_DEFAULT_OPUS_MODEL` is the pin that decides bug-finding
  quality and most of the cost**, because the bug finders run on the opus alias. Point
  it at a Sonnet ID to cut quota, at the price of shallower bug hunting. In
  `claude-code-review.yml`, `--model` only sets the orchestrator and the posted
  summary, so Sonnet is enough there and Opus buys little depth.
- **`claude.yml` is different: its `--model` IS the reviewer.** No plugin runs there.
  The session answers the loop's `@claude review once` retrigger itself, so that
  review's depth is whatever `--model` names, Sonnet 5.5 in the templates. If the
  retrigger replies feel shallower than the auto-run's, raise `--model` in
  `claude.yml` only.
- **Bump the action pin with the models.** A newer action ships a newer CLI that
  knows the newer models. After a pin bump, the first review must still **post**:
  the silent-success failure (anthropics/claude-code-action#1087) is version-sensitive, so check the run left a
  comment, not just a green check.
- **It takes effect after merge.** Both files are validated against the default
  branch (§ The anti-tampering bootstrap catch-22). The PR that changes them gets
  `Workflow validation failed` on its own Claude review. Merge it, then confirm the
  new IDs on the next PR's run: `gh run view <id> --log | grep '"model"'`.

## Dependabot and the review workflows

Dependabot PRs come from a branch in the same repo, so the fork guard doesn't skip
them. A run Dependabot triggers gets only Dependabot secrets, never
`CLAUDE_CODE_OAUTH_TOKEN`, so the auto-review would fail with a red check on every
dependency bump. `claude-code-review.yml` therefore also skips PRs authored by
`dependabot[bot]`. The guard is keyed on `github.event.pull_request.user.login`, not
`github.actor`, so a maintainer re-running the job doesn't change the outcome. Apply the
same guard to any other auto-review workflow, such as grok. `claude.yml` needs nothing:
its author-association gate already excludes bots.

To have Dependabot keep the action pin current, add a `github-actions` entry with a
cooldown. claude-code-action ships several releases a day, and a week's delay gives a
bad release time to be pulled:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 7 }
    groups: { github-actions: { patterns: ["*"] } }
```

A Dependabot bump to these workflows hits the same catch-22 as any other edit: the
review on that PR fails validation, and the new version takes effect only after merge.

## Hardening the @claude assistant (claude.yml)

The default `@claude` trigger fires on ANY comment containing the literal string
`@claude`. Two failure modes the [`assets/claude.yml`](../assets/claude.yml)
author-association gate fixes:

- **Security** — any commenter could invoke a workflow holding the OAuth secret + write perms.
- **Bot false-trigger** — when another review engine (e.g. Copilot) reviews the
  workflow files and *quotes* `@claude` in its comment ("this runs when anyone
  comments `@claude`"), it trips the trigger. GitHub gates the bot-triggered run as
  `action_required` and spams "approve to run" prompts. The triggering actor is the
  bot, not a human. Gating on `author_association ∈ {OWNER, MEMBER, COLLABORATOR}`
  blocks both (bots/outside users don't carry a trusted association). These
  `action_required` runs are harmless if they slip through — leave them unapproved;
  they stop once the workflow files leave the active PR diff.

## Reviewing bot-opened PRs — the `allowed_bots` gotcha

`anthropics/claude-code-action` **aborts the review on any PR opened by a bot actor**
("Workflow initiated by non-human actor") unless that bot is explicitly allow-listed. So a
**fully-automated flow** — an App / automation host opens a PR, and you expect claude-review
to review it — ships the PR **un-reviewed**, silently, until you set:

```yaml
# claude-code-review.yml — on the DEFAULT branch (the action validates against the
# default-branch copy of the workflow, not the PR's copy)
allowed_bots: '<app-slug>[bot]'
```

Two load-bearing details:

- **Set it on the default branch.** Like the perms change, the action reads the workflow from
  the default branch, so an `allowed_bots` added only on the feature branch has no effect.
- **Scope to the specific bot, not `'*'`.** `'*'` would also greenlight `dependabot`/`renovate`
  PRs and burn metered Actions minutes reviewing every dep bump. Name the exact App bot slug
  (`<app-slug>[bot]`) you want reviewed.

This pairs with the all-App-driven automation pattern (an automation App opening PRs gh-less);
it's the review-side half of making that loop actually get reviewed. Distinct from the
`@claude` author-association gate above — that *blocks* untrusted bot **triggers** for security;
`allowed_bots` *permits* a chosen bot's PR to be **reviewed**.
