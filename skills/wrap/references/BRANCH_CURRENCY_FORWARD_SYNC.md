# Branch-currency pre-flight — forward-sync a parked branch before finalizing docs

`/wrap`'s Steps 3–4 (re-sort ideas index, append the CHANGELOG/devlog entry) rewrite
**shared, append-at-top files** — `docs/ideas/README.md`, `CHANGELOG.md` (self-mode) or
`docs/archive/YYYY-MM-DEVELOPMENT_LOG.md` (project mode). When the feature branch was cut
some commits ago and **other PRs merged to `main` in the meantime**, those same shared files
already moved on `main`. Finalizing docs on the stale branch writes the *wrong* neighbours,
and the drift surfaces as merge conflicts at `/land` (or at the human's merge click) —
the most expensive possible moment to discover it.

## The rule

Before `/wrap` runs Step 3 (ideas-index) or Step 4 (CHANGELOG/devlog), check whether the
feature branch is behind its base and **forward-sync if so**:

```bash
git fetch origin
behind=$(git rev-list --count HEAD..origin/main)
if [ "$behind" -gt 0 ]; then
    echo "Branch is $behind commit(s) behind main — forward-syncing before doc finalization."
    git merge origin/main      # resolve conflicts now, on the feature branch
fi
```

Forward-sync is **always allowed by `RULE_git-safety`** — the *feature* branch's tip moves,
the protected branch's tip does not. `git merge origin/main` (or `git pull --rebase origin
main` / `git rebase origin/main`) on a feature branch is the explicitly-sanctioned direction.
This is the inverse of the forbidden operation (merging the feature *into* main).

Run the sync **first**, then Step 3 and Step 4 — so the index re-sort and the version-section
cut happen against the *current* shared-file state, and the doc commits are conflict-free by
the time `/land` merges.

## Why a parked branch conflicts — three classes

A branch cut N commits ago, where sibling IDEAs landed while it sat:

1. **Version-section ordering (CHANGELOG, self-mode).** A sibling patch/minor release merged
   while you were parked, so `main`'s CHANGELOG already has a `## vX.Y.Z` section above where
   yours belongs. Cutting your version section on the stale branch places it in the wrong
   reverse-chronological slot — the resolution must interleave (e.g. `v4.9 > v4.8.1 > v4.8`),
   not just prepend.
2. **Ideas-index drift (`docs/ideas/README.md`).** Sibling IDEAs moved their own entries from
   In-Progress → References-Implemented, changed priority tiers, or left/cleared breadcrumb
   stubs. Your stale branch's index reflects a snapshot from N commits ago; both sides edited
   the same top-of-file regions. (A stale backlog stub a sibling already resolved typically
   *self-resolves* in the merge — the sibling's deletion wins — but only if you sync; on a
   stale branch you'd silently re-introduce it.)
3. **Shared source files your IDEA *and* a sibling both touched.** The dangerous, silent class.
   If your IDEA edits a file a *merged* sibling also edited (e.g. both your stack-decoupling
   work and a sibling's language-base extraction touch `skills/django/SKILL.md`), the stale
   branch carries a pre-sibling version of that file. Without a forward-sync the conflict lands
   at merge time mixed in with everything else; with it, you resolve the one file deliberately,
   in isolation, while you still remember why both sides touched it.

## When this fires

- **Any `/wrap` on a branch older than the most recent merge to its base.** The longer the
  parked interval, the higher the conflict surface — but even one intervening merge that
  touched a shared append-at-top file is enough.
- **Self-mode (mind-vault) especially**, because Steps 3 + 4 *both* rewrite top-of-file
  shared docs (`docs/ideas/README.md` + `CHANGELOG.md`), and mind-vault's own rapid PR cadence
  means a branch cut even a day ago is often several merges behind.
- **Not** under sprint-auto `--scope=idea-only` — that scope *defers* Steps 3/4 to the S11.7
  batch wrap on the integration branch precisely to avoid the parallel-branch version of this
  conflict. The forward-sync pre-flight is for the serial / manual path.

## Diagnostic — catch a stale branch before trusting the index

A tell-tale sign you're on a stale branch: the ideas-index (or CHANGELOG) shows an entry in a
state you *know* changed on `main`. If a sibling IDEA still appears under In-Progress in your
branch's index but you remember it merged, the branch predates that merge — forward-sync before
writing anything. Don't reconcile the index by hand on a stale branch; sync first, then let
Step 3's idempotency guard do the de-duplication against the current state.
