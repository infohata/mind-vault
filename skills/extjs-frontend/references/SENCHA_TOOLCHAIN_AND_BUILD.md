# Sencha Cmd toolchain, dev-server state, production build and deploy

The pre-merge gate (`test:unit` + `test:e2e`) is a **dev-mode** gate: the dev server serves
unminified source, the e2e mocks the API. Everything that differs in production — the compiler
(Closure), the artifact set (what the manifest fetches vs what the build emits), the install
(fresh vs relic `node_modules`), the data (mocked vs real dictionary) — is unverified until the
image is built and booted. **Build the image before calling a release candidate done.**

## 1. Java 8–11 (Nashorn) and the install order

Sencha Cmd's Fashion (SASS→CSS) engine runs JS on **Nashorn**, removed in Java 15+. Use a
**portable JRE 11** in the repo (`./.jdk11`, gitignored, downloaded by a `setup:jdk` script), and
prepend it in every build script (`cross-env PATH="$PWD/.jdk11/bin:$PATH" webpack …`).
**Java must exist before `npm ci`** — the Sencha packages' postinstall invokes Cmd; without Java
the install fails or leaves a half-provisioned `dist/`. `npm run bootstrap` = `setup:jdk` then
`npm ci`. Scripts are POSIX-shell-only (`$PWD` expansion; Windows → Git Bash/WSL).

Private registry: `.npmrc` maps `@sencha:registry=https://npm.sencha.com/`; the token comes from
CI secrets / a BuildKit secret, never the committed file. Rewrite lockfile tarball URLs to https —
npm resolves auth by host, so an `http://npm.sencha.com/…` `resolved` URL sends the bearer token
in cleartext. `npm ci` failing with `EINTEGRITY` after a token/tarball change is by design —
regenerate the lock in that PR.

## 2. Dev-server state footguns (shared mutable workspace)

`generatedFiles/`, `build/` and the Cmd watch lock are shared across profiles, environments and
processes; each symptom misdirects.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Phone e2e stuck at `LOADING…`, console `SyntaxError: Unexpected token '<'` | Any full build regenerated `generatedFiles/` and dropped `phone.json`; the microloader's manifest 404 falls back to `index.html` | brief headless phone dev run until `generatedFiles/phone.json` exists, then kill it |
| Every dev-server start hangs at `wait until bundle finished`; Playwright `Timed out waiting 180000ms from config.webServer` | orphan `java -jar …/sencha.jar app watch` holds the workspace lock; log shows `App watch is already running for this build profile` | `pkill -9 -f "sencha.jar app watch"; pkill -9 -f fashion.js; pkill -9 -f webpack`; verify with `lsof -nP -iTCP:<port> -sTCP:LISTEN` |
| `testing:*` script opens a "not available" tab and never exits | plain `webpack` one-shot with `environment=development` keeps `browser=yes` + `watch=yes` | use `build:desktop`/`build:phone` (production env, `browser=no`, `watch=no`) as the compile gate; "testing" builds are QA artifacts, not test runs |
| A class is `undefined` in dev, fine in production | dynamic loader indexes only declared deps; inline-only refs are absent from the `paths` map | add to `requires`; `Ext.syncRequire` in specs ([SERVICE_LAYER](SERVICE_LAYER.md) § 6) |

Read the server log for `App watch is already running` before bumping timeouts. Clean cold start
is ~25 s locally.

## 3. Production-build footguns (what only `build:*` + a deploy expose)

1. **Closure `C2001` on ES2018 syntax** (`\p{L}` regex, etc.) — `app.json` `output.js.version`
   defaults to an ES5-era level. Set `"output": { "js": { "version": "NEXT" } }` — build config,
   not the release version. The dev server never runs Closure, so a repo can sit broken for weeks
   with green tests.
2. **Closure `NEXT` mis-renames computed keys in object literals**: `for (const prop in x) { setConfig({ [prop]: v }) }`
   renames `prop` but leaves `[prop]` → production-only `ReferenceError` at boot (the boot-error
   sink may attribute it to the wrong stage). Bracket *assignment* renames cleanly:
   `var patch = {}; patch[prop] = v; setConfig(patch)`. Sweep:
   `grep -rnE '\{\s*\[[A-Za-z_$][A-Za-z0-9_$]*\]\s*:' app/ --include=*.js`; after a Closure change
   `grep -c '\[prop\]' build/production/<App>/*.js` → `0`. A production-only fix is not done when
   the app boots — run the full e2e on it (a `setConfig(name, value)` "equivalent" broke five dialog tests).
3. **Fresh `@sencha/cmd` install is crippled by modern npm** — nested `node_modules` stripped from
   a tarball without `bundleDependencies`: Fashion loses `package.json` + deps
   (`Cannot find module 'switchit'` → `Fashion build exited with code : 1`), the launcher loses
   its exec bit. **`@sencha/ext-webpack-plugin` swallows the spawn error and exits 0 with no
   bundle.** Fix in the Dockerfile: `npm pack @sencha/cmd-linux-64@<ver>` and overlay `dist/`
   with `cp -a`; assert `dist/js/node_modules/fashion/package.json` exists and `dist/sencha` is
   executable; after the build **`test -f build/production/<App>/index.html || exit 1`**. Never
   trust the plugin's exit code — gate on the artifact. (Also the likely cause of Fashion failing
   in a CI runner; `chmod -R +x node_modules/@sencha/cmd/{dist,bin}` is the other half.)
4. **The microloader manifest lists root `autobahn.js` and `app.js`** — ship the first (WAMP lib
   genuinely needed at runtime: `COPY autobahn.js` into the docroot), **never the second**: `app.js`
   is the 4-line `Ext.application` launcher already inside the built output; serving it again
   **launches the app twice** (second boot chain dies on the removed splash). Its manifest 404 is
   tolerated. Ask "is it already in the bundle?" before serving any manifest-listed asset.
5. **Cache policy** — only webpack's `main.<hash>.js` is content-addressed. `generatedFiles/…`,
   the microloader, theme CSS, resources are stable names with changing content.

```nginx
location ~* "^/main\.[0-9a-f]+\.js$" { expires 1y; add_header Cache-Control "public, immutable"; try_files $uri =404; }
location ~* \.(png|jpe?g|gif|svg|ico|webp|woff2?|ttf|eot)$ { expires 7d; try_files $uri =404; }
location ~* \.(js|css|json)$ { add_header Cache-Control "no-cache"; try_files $uri =404; }   # revalidate (etag/304)
location = /index.html { add_header Cache-Control "no-store"; }
location / { add_header Cache-Control "no-store"; try_files $uri /index.html; }               # SPA fallback; assets 404, never fallback
```

Backend paths (`/login`, `/api/`, the login page's own `/css/`, `/images/`) proxy **above** the SPA
fallback, with `^~` on the static prefixes so the `\.(js|css)$` regex locations don't win.

## 4. Docker image = the production build gate

```dockerfile
# docker build --secret id=sencha_npm,src=<file-with-token> .
COPY package.json package-lock.json .npmrc ./
RUN --mount=type=secret,id=sencha_npm \
    echo "//npm.sencha.com/:_authToken=$(cat /run/secrets/sencha_npm)" >> .npmrc \
 && npm ci && sed -i '/_authToken/d' .npmrc                     # token never persists in a layer
RUN <overlay @sencha/cmd dist from the platform tarball, assert fashion + exec bit>   # § 3.3
COPY . .
RUN npm run build:desktop && test -f build/production/<App>/index.html || { echo "no bundle"; exit 1; }
FROM nginx:alpine
COPY --from=build /app/build/production/<App>/ /usr/share/nginx/html/
COPY --from=build /app/autobahn.js /usr/share/nginx/html/           # manifest-listed, not in the bundle
```

Run the image locally and sweep the manifest for missing local paths before pushing.

## 5. Swap under a live tab

The shell is `no-store`, so a deploy is visible on the next load — but a tab left open across a
container swap holds the **old** manifest, and its next hard reload can 404 an old
`generatedFiles/…` or `main.<oldhash>.js` once. Expected exactly once per swap; a second reload is
clean. Don't "fix" it with immutable caching on non-hashed files (that freezes clients on the old
release instead).

## 6. Where hosts live

Dev hosts live only in a gitignored `config.dev.js` (`Ext.API_CONFIG = { url, ws, environment }`);
the committed `config.js` is the production stub with empty `url`/`ws` (same-origin). Fresh clone
= no backend until `cp config.js config.dev.js` and set the host. Never write a host into the
committed file or into code — every request is relative `/api/*` and the `beforerequest` hook
prefixes the host.

## 7. CI gate on the release image — one toolchain, production parity

Sencha Cmd cannot be installed on a CI runner with a plain `npm install`: npm strips the nested
`node_modules` inside the `@sencha/cmd` dist, Fashion loses its `switchit` dependency, and every
theme build dies with the opaque `Fashion build exited with code : 1` (which the webpack plugin
swallows). The production Dockerfile that repairs the dist (§4) is therefore the **only** place
the release build is known to work — so the CI gate builds *that* image and runs the suite
against it, instead of reinventing a runner-native Sencha install:

- `docker/build-push-action` with `context: .`, `load: true`, the registry token as
  `secret-files:` (written from an `env:` secret *after* asserting `.npmrc` carries no
  `_authToken` — a token in the `COPY . .` layer would ship), `cache-from/to: type=gha`.
  Cold image ≈ 5–6 min on a 2-vCPU runner, **≈7 s warm** — keep `tests/` in `.dockerignore` so a
  spec-only push hits the cached build layer.
- Run the container with a backend host that **resolves** (`127.0.0.1` — never contacted, routes
  are mocked in-browser); nginx resolves `proxy_pass` upstreams at `nginx -t`, so `backend.invalid`
  refuses to start. Set the trusted-proxy CIDR so the render path runs as in production.
- Verify the static contract (health, SPA fallback, cache policy — split the verify script into a
  static half and a proxy half; the proxy half expects a 502 by design against a dead upstream
  and belongs to the deploy side), then Playwright in a **static mode** pointed at the container
  (`E2E_STATIC_URL`; one mode helper derives dev | static | live and throws when two are set),
  **both** projects — the Pixel-7 UA makes the microloader load `phone.json` on its own, no
  `?phone` hack. `workers: 2` on the small runner; grid-icon paint polls at 30 s, not 10.
- Triggers: same-repo PRs (secrets are unavailable to forks — guard with
  `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`
  — placeholder shorthands like `head.repo == repo` are not valid workflow expressions, and the old
  PR-only guard got the dispatch and push cases wrong), a push to the trunk branch (every trunk SHA
  is a potential deploy-pointer source — gate it, and **never cancel a trunk run**;
  `cancel-in-progress` only for PR refs), and `workflow_dispatch`. Add `paths-ignore` for docs-only
  changes (`docs/**`, `**/*.md`, the version file) — a three-file docs PR built the whole image
  once; see `skills/deployment/references/CICD.md` § Path filters.

The local fast loop stays the dev server (`npm run test:e2e`); the image run is the pre-merge
gate and the reproduction path for a red CI (`npm run test:e2e:image` builds the same image
locally with the same token file). Probe design for what the gate asserts per bundle:
PLAYWRIGHT_COMPONENTQUERY_E2E.md §10.

## 8. Cross-origin dev login is dead in modern Chrome — proxy in the dev server, like prod's nginx

The documented dev flow ("app on `localhost:<port>`, log in at the backend host, come
back") fails SILENTLY today: backends that set the session cookie `SameSite=Lax` never
get it attached to cross-site XHR, and a CORS `Access-Control-Allow-Origin: *` is
invalid with credentials — so the backend login "succeeds", the app's session probe
401s, and the operator bounces back to the login page with no error anywhere. Measured
2026-09-01 on a Laravel-family backend + Chrome 152; it is why live smokes kept
happening only on the deployed staging instance.

The fix is parity, not CORS surgery: an opt-in webpack devServer proxy that mirrors the
production nginx — forward `/login`, `/logout`, `/api/*` and the asset prefixes to
`https://<backend-host>` with `changeOrigin: true` (the pinned `Host` selects the same
tenant as staging) and `cookieDomainRewrite: ''`. Cookies then land on the localhost
origin, the app runs the production same-origin code path (config `url: ''`, relative
requests), and the password manager needs the localhost URL added to the entry once.
Gate it on an env var so test harnesses that expect a dead backend stay untouched.

## 9. One `sencha app watch` profile at a time; the microloader picks the manifest by UA

Two dev servers (desktop + phone profiles) on one checkout silently fight: both watches
write the same `generatedFiles/` (bootstrap + build manifests), last writer wins, and
the second port serves the FIRST profile's bundle. Run one profile at a time.

And serving the phone profile is not enough: the microloader selects `phone.json` vs
`desktop.json` **by user agent**, not by what the dev server built — a desktop browser
gets the desktop manifest on the phone port. DevTools device emulation (Ctrl+Shift+M) +
reload is the dev-mode lever (the CI/static twin is a mobile-UA browser context). While
a DevTools emulation session is open, CDP-driven mouse input from automation tooling can
wedge even though page JS is fine — drive the walk through the framework's controller
API (`Ext.ComponentQuery` + controller methods) instead of synthetic clicks.

## 10. Post-deploy, the OLD app runs first — and the update prompt is a native confirm

Incident shape (post-deploy verification walk on a staging host): the freshly deployed
build was live on the server, yet every probe of the running app showed the old code —
and then the tab froze so hard that CDP `Runtime.evaluate` timed out at 45 s.

Two microloader behaviors compose into this:

- **The cached bundle boots first.** The microloader caches build manifests in
  `localStorage` (`_ext:*` keys) and boots from cache, then checks the server in the
  background. On the first load after a deploy, the tab runs the **previous** build
  end-to-end; the new code arrives only after the update-and-reload cycle.
- **The update prompt is a NATIVE `confirm()`.** When the background check finds a newer
  manifest, the stock microloader raises a browser-native dialog ("application updated —
  reload?"). Native dialogs block the renderer's event loop: automation sees frozen
  screenshots and CDP timeouts, and nothing recovers until a human dismisses it.

Consequences for anyone verifying a deploy:

- **Probe the server artifact, never the running app**: fetch the build manifest and
  compare its `cache` stamp, then fetch the served `app.js` and grep a symbol unique to
  the new release. A booted tab asserting old behavior proves nothing about the deploy.
- Expect the freeze on the first post-deploy load in **any** tab with a stale manifest
  cache — pre-arrange the human dismissal, or start from a tab whose `_ext:*` cache is
  already current. Clearing the `_ext:*` keys must happen **before** the app page loads
  (from a non-booting same-origin page, e.g. the login route) — on the app page the
  microloader has already consumed the cache by the time any injected script runs.

