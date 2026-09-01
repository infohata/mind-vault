# Playwright against an ExtJS Modern SPA — ComponentQuery bridge + single-handler mocks

## 1. Selectors: drive Ext, not CSS

The DOM has no `data-testid`s, auto-generated ids and virtualised grids; CSS/`getByText` is
brittle. The code is richly labelled (`reference`, `itemId`, `xtype`, field `name`) — resolve a
component through the global `Ext` and hand its DOM id to Playwright:

```js
// tests/e2e/helpers/ext.js
async function waitForExtReady(page, timeout = 30_000) {
  // Ext.isReady can flip true a tick before getBody/ComponentQuery attach — require all three.
  await page.waitForFunction(() => !!(window.Ext && window.Ext.isReady && typeof window.Ext.getBody === 'function' && window.Ext.ComponentQuery), null, { timeout });
}
async function getByExt(page, query) {
  const id = await page.evaluate((q) => {
    const c = window.Ext.ComponentQuery.query(q)[0];
    const el = c && ((c.element && c.element.dom) || (c.el && c.el.dom));   // modern: element / classic: el
    return el ? el.id : null;
  }, query);
  if (!id) throw new Error(`getByExt: no rendered component for "${query}"`);
  return page.locator(`#${id.replace(/([^\w-])/g, '\\$1')}`);
}
const extExists = (page, q) => page.evaluate((q) => window.Ext.ComponentQuery.query(q).length > 0, q);
```

Modern gotcha: a `floated` component is `x-hidden` until shown and `renderTo: getBody()` can land
outside the viewport → don't inject synthetic controls; click a REAL mounted one.

## 2. Mock bootstrap — ONE `**/api/**` handler, longest key wins

Playwright runs matching `page.route` handlers in **reverse registration order**; a catch-all
plus specific routes is a race (the catch-all shadows the session check → `{success:false}` →
the app redirects to `/login` → *"execution context was destroyed"*). An empty handler does
**not** hang a request — it falls through to the real backend (401 → redirect).

```js
// tests/e2e/fixtures/mockBootstrap.js
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const SESSION_OK = { success: true, userData: { id: 1, name: 'E2E User', email: 'e2e@example.com' } };

function defaultResponses(lng = 'lt') {
  return { '/api/app/params': { success: true, result: { language: lng } }, '/api/app/translations/': {},
           '/api/app/menu': { success: true, result: [] } /* … the boot chain's endpoints */ };
}
async function mockBootstrap(page, overrides = {}) {
  const { lng, ...routeOverrides } = overrides;
  // precedence: defaults < captured real shapes (fixtures/responses/*.json) < per-spec overrides
  const responses = { ...defaultResponses(lng), ...loadCapturedResponses(), ...routeOverrides };
  const keys = Object.keys(responses).sort((a, b) => b.length - a.length);      // longest key wins
  const serve = (route, entry) => typeof entry === 'function' ? entry(route) : route.fulfill(json(entry));
  await page.route('**/api/**', (route) => {
    const url = route.request().url();
    if (url.includes('/api/auth/activesession')) {                             // 1. session FIRST, success by default
      const e = responses['/api/auth/activesession'];
      return e === undefined ? route.fulfill(json(SESSION_OK)) : serve(route, e);
    }
    const key = keys.find((k) => url.includes(k));                              // 2. data map
    if (key) return serve(route, responses[key]);
    return route.fulfill(json({ success: false }));                             // 3. unknown → 200 {success:false}, never 401
  });
}
```

Rules: specs **extend by merging into the map**, never by another `page.route`; an override is a
**plain body** (`serve` wraps with `json()` — `json(json(body))` double-wraps and the store reads
0 rows) or a `(route) => …` function for status/method branching
(`route.request().method() === 'DELETE' ? route.fulfill(json({success:false, msg}, 409)) : …`);
`'/api/entities/1'` outranks a captured `'/api/entities'` list by length. Unknown endpoints answer
`{success:false}` — you mock only what an assertion reads. **Captured fixtures**
(`fixtures/responses/*.json` = `{ _meta: { endpoint }, body }`) hold real backend shapes with PII
scrubbed (emails, phones, tokens — keep the shape, fake the values); a file with `body: null` is
a skeleton and is skipped so the smoke self-skips until it is filled. The app may build absolute
URLs with a double slash (`https://host//api/x`): match with `/\/+api\/entities(\/\d+)?(\?|$)/`,
not `new URL(u).pathname`.

## 3. Mount dialogs the way production does

The dev build loads classes lazily; `Ext.syncRequire` then `Ext.widget`:

```js
await page.evaluate((cls) => {
  window.Ext.syncRequire(cls);                                          // 'App.desktop.src.view.entity.entitydialog.EntityDialog'
  const record = window.Ext.create('Ext.data.Model', { id: 2, name: 'Entity 1', status: 'DRAFT' });
  window.Ext.widget('entitydialog', { record }).show();
}, DIALOG_CLASS);
await expect.poll(() => extExists(page, 'entitydialog'), { timeout: 15_000 }).toBe(true);
// drive fields through the form, not CSS
await page.evaluate(() => {
  const form = window.Ext.ComponentQuery.query('entitydialog')[0].down('[itemId="entity-form"]');
  form.down('textfield[name=name]').setValue('Probe'); form.down('selectfield[name=role_id]').setValue(3);
});
```

Toast text (Modern's `Ext.toast` reuses one instance):

```js
const lastToastText = (page) => page.evaluate(() => {
  const t = window.Ext.Toast && window.Ext.Toast._instance, m = t && t.getMessage && t.getMessage();
  const html = m && m.getHtml ? m.getHtml() : null; return html == null ? '' : String(html);
});
await expect.poll(() => lastToastText(page), { timeout: 5_000 }).toContain('cannot be deleted');
```

Assert requests by capturing them (`page.on('request', r => r.method() === 'DELETE' && deletes.push(r.url()))`)
or via a handler that records `{method, postData}` — proves create → POST not PUT.

## 4. Seed rows to exercise cell renderers

Modern cell renderers run only when rows exist; an empty mock grid proves nothing.

```js
const pageErrors = []; page.on('pageerror', (e) => pageErrors.push(e.message));
await mockBootstrap(page, { '/api/entities': { success: true, total: 3, result: [ /* rows hitting each renderer branch */ ] } });
// navigate; poll grid store getCount() === 3
expect(pageErrors.filter((m) => /is not a function|Cannot read/.test(m))).toEqual([]);
```

## 5. The sentinel + `framenavigated` probe (native submit / any "did the page reload?" question)

```js
let navigations = 0;
page.on('framenavigated', (f) => { if (f === page.mainFrame()) navigations++; });
// … mount dialog …
await page.evaluate(() => { window.__alive = 'yes'; });
const before = navigations;
await page.evaluate(() => { /* focus a text field inside the form */ });
await page.keyboard.press('Enter');
await expect.poll(() => captured.filter((c) => c.method === 'POST').length, { timeout: 10_000 }).toBe(1); // Enter == Save
expect(await page.evaluate(() => window.__alive)).toBe('yes');                                             // no reload
expect(navigations - before).toBe(0);
```

Distinguishes "handler didn't fire" from "fired but didn't prevent"; persist a handler-fired flag
in `sessionStorage` if a reload would wipe the evidence. Prove the probe **RED** by `git stash`ing
the guard first.

## 6. Two projects (desktop / phone), one dev server

`projects: [{ name: 'desktop', use: devices['Desktop Chrome'] }, { name: 'phone', use: devices['Pixel 7'] }]`.
Desktop-only surfaces skip explicitly:
`test.skip(testInfo.project.name === 'phone', 'desktop-only settings dialog');`.
The microloader picks `generatedFiles/<profile>.json` by UA — a phone project stuck at `LOADING…`
with `SyntaxError: Unexpected token '<'` means `phone.json` is missing (a full build dropped it);
regenerate with a brief headless phone dev run.

## 7. Dev-server collision, port reuse, watcher hygiene

`webServer: process.env.E2E_BASE_URL ? undefined : { command: 'npm run start:test -- --env port=' + PORT, url, reuseExistingServer: !process.env.CI, timeout: 180_000 }`
with `PORT = process.env.E2E_PORT || 1962`.

- **Never run a second webpack/Sencha dev server while `playwright test` boots its own** — two
  `sencha app watch` + Fashion processes write the same `build/`/`generatedFiles/`, the Cmd
  workspace lock is held, the server log says `App watch is already running for this build
  profile` and Playwright times out at `wait until bundle finished`. Either point at the running
  one (`E2E_PORT=<port>` / `E2E_BASE_URL=http://localhost:<port>` — `reuseExistingServer`) or
  stop it first.
- Killing means the **process tree**: `pkill -9 -f "sencha.jar app watch"` (the java child holds
  the lock and its cmdline has no literal `sencha app watch`), `pkill -9 -f fashion.js`,
  `pkill -9 -f webpack`; then `lsof -nP -iTCP:<port> -sTCP:LISTEN` must be empty. Never `pkill -f`
  a pattern that appears in your own shell's command line.
- CI: the Sencha compile inside `webServer` is the wall; build once in a cached step and serve
  `build/production/<App>/` with a static server (instant boot). The Fashion step may still fail
  on a fresh `npm ci` — see [SENCHA_TOOLCHAIN_AND_BUILD](SENCHA_TOOLCHAIN_AND_BUILD.md) § 3.

## 8. Dev-vs-production class loading in tests

A bare `App.service.Api` at `Ext.isReady` is `undefined` in the dev build unless some loaded class
`requires` it; `Ext.syncRequire` it in the spec. A spec that fails only in dev → suspect the build
mode: check out the base branch detached (the dev server serves the working tree live) and
re-run; grep the served manifest's `paths` for the namespace.

## 9. Mock mode still fetches real external hosts — and the known-green bisect

"Mock mode" routes the *API*; anything the app loads by absolute URL — an editor bundle from an
estate media host, CDN fonts — still hits the real network **on every page boot of every test**.
Two consequences, both observed the hard way:

- **You are load on someone's box.** Repeated suite runs fired hundreds of asset fetches in
  bursts from one IP — enough to trip the serving host's fail2ban and get the *developer's IP*
  banned estate-wide. Route every external host in the mock bootstrap (serve a vendored copy or
  a stub); a mock-mode suite that needs the internet is a latent incident.
- **A dead external host fails suites that never mention it.** The boot-time loader threw
  (`EDITOR global not found`) into whichever test happened to be running — cross-suite failures
  with *varying counts per run*, in specs untouched by the branch. Any spec asserting
  `pageErrors == []` owns every async throw on the page; filter known boot noise explicitly or
  eliminate its source.

**The bisect that names the class in one run**: when failures are cross-suite and the count
varies between runs, re-run the suite on a **known-green commit** *first*. Same failures there =
environment (external host, box state, network) — stop reading your diff. Only a clean
known-green run justifies bisecting your own commits. This one command distinguishes "I broke
the app's boot" from "the world changed under me", and it would have saved an hour of
diff-staring the night this was learned.

## 10. Boot probes on the production bundle — the boot chain handles its own rejection

A CI gate that boots the **release image** (see SENCHA_TOOLCHAIN_AND_BUILD.md §7) needs a probe
per manifest that fails on *any* boot-time error. The first cut asserted `pageerror.length === 0`
and stayed green through a deliberate `ReferenceError` planted in a boot module — vacuous, because
a well-built app's launch chain **catches its own rejection** (paints a boot-error overlay, logs
`console.error('Boot init failed at <stage>')`) and nothing ever reaches `pageerror`. The gate is
the union of four collectors installed **before** `goto`:

```js
page.on('pageerror', e => errors.push(e.message));                 // uncaught only — necessary, not sufficient
page.on('console', m => { if (m.type() === 'error') errors.push(`${m.text()} @ ${m.location().url}`); });
page.on('response', r => { if (r.status() >= 400 && !TOLERATED.some(rx => rx.test(new URL(r.url()).pathname))) failed.push(r.url()); });
page.on('request', r => { if (/\/(desktop|phone)\.json/.test(r.url())) manifests.push(r.url()); }); // the manifest fetched == the project under test
```

then: `mainview` mounted (poll ~30 s on a 2-vCPU runner), **no** boot-error overlay element,
all three lists empty, manifest === project. Two rules that came out of the red runs:

- **Tolerate 404s by an explicit whitelist, one entry with a reason each** — the microloader may
  request a file the manifest lists but the image omits (a root `app.js` alongside the per-profile
  bundle); that is the *only* boot 404 a healthy image produces. A blanket "ignore 404s" would have
  hidden the missing-manifest bug that stalled the phone bundle for a week.
- **Tolerate a framework's bare-`undefined` rejection by *shape*, never by silencing `pageerror`.**
  Ext's `Scroller#ensureVisible` returns `Deferred.getCachedRejected()` — a rejection with no
  reason and no handler — when a dataview's `NavigationModel.setLocation` runs on focus-enter after
  the focused element was re-rendered away (any editor that replaces `innerHTML` inside its own
  blur handler triggers it). Playwright reports it as `pageerror` with `message === undefined`.
  Filter exactly that signature (`msg === undefined || msg === 'undefined'`) with the source named
  in a comment; anything carrying a message still fails. Tracing recipe: wrap `window.Promise`
  via `addInitScript` so a `reject(undefined)` records `new Error().stack` — 30 s from "some
  promise" to the framework frame.
- **The stage a boot-error screen names is a hint.** A single terminal rejection sink attributes
  every unattributed failure to its last-registered stage; a `ReferenceError` in a *later* module
  reported as "failed at translations". Read the message, not the stage.

Prove the probe once with a deliberate red (a planted `ReferenceError` on a throwaway branch — the
phone bundle went red with `pageerror: 0` and the console collector carrying the error, desktop
stayed green) before trusting it; a probe that has never failed has never been tested.

## 11. Turning on tracing flips one-shot races — the de-race taxonomy

Enabling `trace: 'retain-on-failure'` (or anything that slows the renderer — a loaded
2-vCPU CI runner does it too) is an **observer effect**: tests that always passed start
failing deterministically, because they secretly bet on winning a race. One overnight
hardening pass on a consuming ExtJS project hit five distinct shapes in a single suite;
every fix generalizes. The dividing line: **poll budgets absorb slow observations;
they cannot recover a lost one-shot action.** Diagnose which side you're on first —
a 90 s budget that expires with *zero* progress means the action was lost at t=0, and
more budget is the wrong tool.

| Shape | Symptom under tracing | Fix |
| --- | --- | --- |
| **Store-load race** | A "no selection / empty state" probe fails because a bound store's auto-select landed before the probe's save fired | Mock the *state* the test claims (an empty store response registered after the boot mock — last-registered route wins), never "act before the load lands" |
| **Covered / stale button** | `locator.click` retries for the whole test timeout: "element is not visible" or "subtree intercepts pointer events" — a resolve-once DOM id went stale after a re-render, or a parent dialog's scroller sits over the child (a real z-order defect: capture it as its own bug) | Drive the button's declared controller handler via `page.evaluate`; keep real clicks only where nothing re-renders underneath |
| **Swallowed `focus()`** | `document.activeElement` never becomes the field — Ext defers `focus()` and it can no-op outright while a dialog animates | `waitForFunction` that **retries a DOM-level `input.focus()` on every poll tick**, not one that merely observes |
| **Swallowed synthetic keypress** | Focus verified, `keyboard.press('Enter')` sent, the expected request never appears | Re-press inside the poll until the effect shows (`expect.poll(async () => { if (n===0) await press(); return n; })`); relax an exactly-once count to `>=1` — the routing claim survives, and a real user re-presses too |
| **Grid rows never paint** | A row/icon count poll exhausts a *generous* budget at 0 on the slowest runner tier | Not budget-fixable blind — this is the class the tracing exists FOR: pull the retained trace + JSON report from the red run's artifact and find which one-shot (store load, route event) was dropped |

Two ops corollaries from the same night, cheap to remember: a killed test-runner shell
orphans the webpack dev server, and `reuseExistingServer: true` then latches every
later run onto the wedged instance — kill the process tree before retrying; and
`pkill -f <pattern>` matches its own wrapping shell when the pattern appears in your
command line — bracket the first character (`pkill -f '[w]ebpack serve'`).
