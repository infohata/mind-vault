# Vendored-static Dependabot variant — the re-vendor-CI flow

A distinct flavour of dep sweep that the main [`../SKILL.md`](../SKILL.md) (pip
requirements files) doesn't cover. Recognise it by the setup:

- A **synthetic `package.json`** (npm ecosystem in `.github/dependabot.yml`) that
  pins third-party **browser** builds vendored into the repo's `static/` tree. It
  is never built or bundled — it exists only so Dependabot opens version-bump PRs
  for the minified files committed in git (CDN-free / `script-src 'self'` setups).
- A **map file** (`revendor-map.json` or similar) mapping each npm package →
  the dist path inside `node_modules` → the committed `static/` destination, plus
  a license-banner substring and a byte floor per file.
- A **re-vendor CI workflow** (`pull_request_target`, guarded to the Dependabot
  PR opener) that, on a manifest bump: `npm install`s the new pin, runs a copy
  script (`node_modules` dist → `static/`), runs an integrity test, and **commits
  the refreshed `static/` bytes back onto the Dependabot PR branch**. Never
  auto-merged; a human reviews the binary diff.
- An **integrity test** asserting banner + size + manifest/map/catalog
  consistency, run both in CI and in the suite.

## Why these PRs silently get stuck

The CI workflow commits the re-vendored bytes **only if `npm install` + copy +
integrity test all pass**. So when a bump fails any of those, the job dies before
the commit and **no re-vendor commit is pushed** — the PR sits at one commit (the
manifest bump alone), `mergeable_state: "unstable"`, with no obvious reason in the
PR conversation (especially if you're driving as a bot/App and can't read the CI
run logs — see [`../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md`](../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md) §4).

The usual cause for a **major** bump: the map's `src` path is stale for the new
major's **dist layout**. The copy script can't find the file → integrity fails →
no commit. The prep PR that adapted the *consuming code* for the new major often
does **not** also fix the map src (different file, easy to miss). So minor/patch
bumps sail through CI (dist layout stable) while every major sticks.

## Major bumps need a map `src` change, not a byte refresh

Treat a vendored-static major as a migration of the **map entry**, not just the
bytes. Install the new major and inspect what it actually ships before trusting
the old `src`. Recurring dist-layout traps:

- **A library drops its root minified build.** The dist moves under `lib/` and
  ships only an unminified UMD + an ESM build (e.g. `marked` after v11 →
  `lib/marked.umd.js`, no root `*.min.js`). Vendor the **UMD** build (it exposes
  the browser global the app uses); keep the destination filename stable
  (`marked.min.js`) to avoid template churn even though the bytes are now
  unminified; **raise the byte floor** to match the larger unminified size.
- **An icon/font library consolidates compat shims into the all-in-one and goes
  woff2-only.** The faithful source becomes the all-in-one CSS (`css/all.min.css`),
  NOT the core file (`css/fontawesome.min.css` carries no `@font-face`, so
  vendoring it renders glyphless icons). Drop now-orphaned `.ttf` from the map and
  delete the orphaned font files. Verify every `url(../webfonts/*.woff2)` ref in
  the new CSS resolves to a present file — a manifest static storage
  (`ManifestStaticFilesStorage`) hard-fails `collectstatic` on a missing CSS
  `url()` target.
- **A library keeps its dist path stable across the major** (e.g. a UMD
  `dist/*.min.js` that just grew). Faithful re-vendor, no map change — but still
  review the *consuming code* for API/behaviour breaks (the bump is a migration
  even when the file path isn't).

## The committed file may not be reproducible by a 1:1 copy

The re-vendor model is **one src → one dest copy**. If the committed vendored file
is actually a **hand-concatenation** of several npm files (e.g. an icon CSS built
from `all` + `v4-shims` + `v5-font-face`), the map's single `src` never matched
reality — a latent drift the integrity test misses (it checks banner + size on the
committed bytes, not byte-equality with a fresh `npm install`). You discover it
when a revendor of *any* package rewrites that file too.

A major bump is the moment to reconcile it: either the new major folds the
concatenation into one shippable file (common — pick that as the new `src`), or
extend the map/script to support multi-src → concatenated-dest. Don't paper over
it by reverting the "unexpected" diff forever.

## Reproducing the re-vendor locally (CI can't, or you're consolidating)

You don't need Node on the host. Use a disposable container; mind the two gotchas:

```bash
# Docker bridge networking is often off on agent/staging hosts (no IPv4
# forwarding) → use --network host so npm reaches the registry.
# --ignore-scripts neutralises install/postinstall (supply-chain hygiene; the
# CI uses it too).
docker run --rm --network host -v "$PWD":/work -w /work/tools/vendored-assets \
  node:20-alpine npm install --ignore-scripts --no-audit --no-fund

bash tools/revendor-vendored-static.sh           # copy; runs on host (bash+python3)
python3 .../test_vendored_assets_manifest.py     # integrity gate
rm -rf tools/vendored-assets/node_modules         # never commit it (often NOT gitignored)
```

Per-commit hygiene: the copy script refreshes **every** mapped file, so a single
package bump surfaces any pre-existing drift in *other* packages. Stage only the
bumped package's destination files for that commit and `git checkout --` the
unrelated drift, so each per-dep commit's diff is clean and bisectable. Handle the
pre-existing drift as its own separate change.

## Consolidation-as-unblock — fold the vendored-static PRs into one branch

When the per-PR CI is wedged on stale map srcs **and** you can't drive the bot
commands to fix it (Dependabot `recreate` and the review-bot retrigger are
human-only actors — [`../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md`](../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md)),
the cleanest unblock is to **abandon the individual Dependabot PRs and consolidate**:

1. One agent-authored branch off current `main` (in an isolated worktree if the
   working tree is a live-staging checkout — never check PR branches out there).
2. One **per-dep commit**: bump that package in the manifest → local re-vendor →
   stage only its files (+ the map `src` fix for that dep) → commit, citing the
   Dependabot PR it supersedes.
3. The catalog/version drift-guard test typically forces a docs update (version
   cells + mapping notes) in the **same** PR — do it; it's part of the gate.
4. Open one PR; **close** each superseded Dependabot PR with a comment pointing at
   it (`Closes #N` does NOT auto-close another *PR*, only issues — close them
   explicitly).

This move kills three birds: it produces the re-vendor commits CI couldn't, it
fixes the map srcs, and — because the branch is opened by a normal (or
App-but-allowlisted) actor rather than `dependabot[bot]` — it **escapes both
bot-actor gates at once** (no Dependabot recreate needed; the review bot
auto-reviews a non-Dependabot PR). One review, one staging smoke for the whole
batch instead of N stuck PRs.

Trade-off vs. the main skill's per-PR worktree flow: you lose Dependabot's
per-PR changelog/compatibility-score surface, so read the upstream release notes
yourself for each major. Worth it only when the per-PR path is genuinely wedged —
for a healthy vendored-static minor bump, just let the re-vendor CI do its job and
merge the PR.

## Composes with

- [`../SKILL.md`](../SKILL.md) — the general sweep (duplicate detection, risk
  tiers, per-dep commits, non-squash merge, forward-sync) still applies; this is
  the vendored-static-specific overlay.
- [`../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md`](../../review-loop/references/GITHUB_APP_DRIVEN_LOOP.md)
  — why the bot can't recreate/retrigger/read CI, which motivates consolidation.
