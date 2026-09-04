# Jest against `Ext.define`-wrapped code — the fail-loud Ext stub

Jest covers pure util logic **and ViewController method probes**; anything needing layout, DOM or
real component lifecycle is an e2e ([PLAYWRIGHT_COMPONENTQUERY_E2E](PLAYWRIGHT_COMPONENTQUERY_E2E.md)).

## 1. Why a stub — `Ext is not defined`

Every util is `Ext.define('App.util.X', {...})` at module top level; a bare `require()` under Node
throws before any assertion. `jest.config.js` installs a global `Ext` via
`setupFiles: ['<rootDir>/tests/unit/setup/extStub.js']` (runs per test file, before the module).
Bundling ExtJS for a regex test is the wrong trade; a ~120-line stub is the right one.

## 2. The stub (compact sketch)

```js
// tests/unit/setup/extStub.js
const NOT_STUBBED = (p) => new Error(`Ext.${p} is not stubbed — register it via Ext.__stub.register('${p}', …)`);

function setPath(obj, dotted, value) {
  const parts = dotted.split('.'); let n = obj;
  for (let i = 0; i < parts.length - 1; i++) { if (typeof n[parts[i]] !== 'object' || n[parts[i]] === null) n[parts[i]] = {}; n = n[parts[i]]; }
  n[parts[parts.length - 1]] = value; return value;
}

// Fail LOUD on unknown STRING props; permissive on symbols / `then` (Node + Jest probe those).
function nsProxy(target, path) {
  return new Proxy(target, {
    get(obj, prop) {
      if (typeof prop === 'symbol' || prop === 'then' || prop in obj) {
        const v = obj[prop];
        return v && typeof v === 'object' && !Array.isArray(v) ? nsProxy(v, path ? `${path}.${String(prop)}` : String(prop)) : v;
      }
      throw NOT_STUBBED(path ? `${path}.${String(prop)}` : String(prop));
    },
  });
}

const root = {};
const stubApi = {
  register: (dotted, value) => setPath(root, dotted, value),          // the ONE extension API
  makeModel(fields = {}) {                                             // genuine instanceof Ext.data.Model
    const M = root.data && root.data.Model;
    const m = Object.create(M.prototype); m.__data = { ...fields }; m.get = function (f) { return this.__data[f]; }; return m;
  },
  reset() { for (const k of Object.keys(root)) delete root[k]; seed(); },
};

// Ext.define(name, body): resolve function-form, FLATTEN statics + members onto one object,
// hang it off the nested global namespace (App.util.X). Note: this flattening is why the stub
// cannot distinguish `singleton+statics` (runtime-broken) from plain members.
function define(name, body) {
  const cfg = typeof body === 'function' ? body() : body, cls = {};
  if (cfg && cfg.statics) Object.assign(cls, cfg.statics);
  if (cfg) for (const k of Object.keys(cfg)) if (k !== 'statics') cls[k] = cfg[k];
  setPath(globalThis, name, cls); return cls;
}

function seed() { root.define = define; root.__stub = stubApi; root.data = { Model: class Model {} }; }
seed();
globalThis.Ext = nsProxy(root, '');
```

Decisions that carry the design: **any un-stubbed `Ext.*` access throws a NAMED error** (never an
opaque `undefined is not a function` three layers down); **one extension API** —
`Ext.__stub.register('data.validator.Email', factory)` — growing the suite never re-edits the
resolver; `makeModel` does `Object.create(Model.prototype)` so `instanceof Ext.data.Model`
branches in utils pass; symbols and `then` return `undefined` (Jest's thenable check,
`util.inspect`, `Symbol.toPrimitive` must not throw).

## 3. Register per test, reset after

```js
require('../../app/shared/src/util/Shared.js');            // whatever defines the namespace root
global.App.util = global.App.util || {};
global.App.util.TranslateText = { t: (k) => k };            // identity → assertions pin the KEY
require('../../app/shared/src/util/FormErrorHandler.js');
require('../../app/shared/src/service/Api.js');
require('../../app/desktop/src/view/entity/entitydialog/EntityDialogController.js');

function registerSurface({ ajaxImpl } = {}) {
  Ext.__stub.register('Promise', Promise);
  Ext.__stub.register('toast', jest.fn());
  Ext.__stub.register('Ajax', { request: jest.fn(ajaxImpl || (() => {})) });
  Ext.__stub.register('decode', (t, safe) => { try { return JSON.parse(t); } catch (e) { if (safe) return null; throw e; } });
  Ext.__stub.register('Date', { format: jest.fn((d) => (d instanceof Date ? d.toISOString().slice(0, 10) : '')) });
}
afterEach(() => Ext.__stub.reset());
```

The fail-loud error is a **scope signal**: when a helper's stub balloons (`Ext.util.Format`, DOM,
real validators), it belongs in e2e, not here.

## 4. Controller probes — `Ctl.method.call(fakeThis)`

The flattened `Ext.define` body is a plain object, so a controller method runs as
`Ctl.save.call(fakeThis)` where `fakeThis` supplies `getView()`, `getViewModel()`, `lookup()`.
**Sibling methods the probed method calls must be copied onto `fakeThis`** (`buildSaveParams: Ctl.buildSaveParams`)
— `this` is the fake, not the class.

```js
const Ctl = App.desktop.src.view.entity.entitydialog.EntityDialogController;
const flush = () => new Promise((r) => setImmediate(r));
const fakeView = () => ({ down: jest.fn(), mask: jest.fn(), unmask: jest.fn(), fireEvent: jest.fn(), close: jest.fn(),
                          isMasked: () => false });

it('save without a series: one error toast, NO request, dialog unmasked and open', async () => {
  registerSurface();
  const view = fakeView();
  const ctx = { getView: () => view, getViewModel: () => ({ get: (k) => ({ editId: null })[k] }),
                lookup: () => ({ validate: () => true, getValues: () => ({ name: 'x', series_id: null }) }),
                buildSaveParams: Ctl.buildSaveParams };
  Ctl.save.call(ctx);
  await flush();
  expect(Ext.Ajax.request).not.toHaveBeenCalled();
  expect(Ext.toast.mock.calls[0][0]).toEqual(expect.objectContaining({ message: 'app_entitydialog_series_required', ui: 'tooltip-error' }));
  expect(view.unmask).toHaveBeenCalled();
  expect(view.close).not.toHaveBeenCalled();
});

it('save with a series: PUT /api/entities/7 JSON, saved event, close', async () => {
  registerSurface({ ajaxImpl: (cfg) => cfg.success({ responseText: '{"success":true,"result":{"id":7}}' }) });
  // …
  const cfg = Ext.Ajax.request.mock.calls[0][0];
  expect([cfg.method, cfg.url]).toEqual(['PUT', '/api/entities/7']);
  expect(cfg.jsonData).toEqual({ name: 'x', series_id: 3, active: 1, main: 0 });   // all-absent booleans → 0
});
```

What this catches red-before-fix: `ReferenceError`s in rarely-run branches, false-success toasts on
`{success:false}` 2xx bodies, `undefined` toast messages, `getStore('x')` on a store the ViewModel
never declared, the loadmask left on after a thrown param-shaper.

## 5. RED-first, structural pins

- For every crash class, write the probe **RED** first: `git stash` the fix (an untracked test
  file survives), run, see red, `git stash pop`, commit test → fix (`git log` proves order).
- Pin **structure**, not literal names: `expect(Object.keys(vm.stores)).toContain('entities')`
  read from the ViewModel class rather than a hard-coded `'EntitiesStore'` — renames survive.
- All-absent fixtures for boolean shapers; string-vs-number fixtures for anything compared with
  `===` against backend data ([REFACTOR_CONTRACT_PINNING](REFACTOR_CONTRACT_PINNING.md)).

## 6. Babel isolation is config-load-bearing

The webpack build runs `babel-loader` with no root Babel config; a stray root `babel.config.js`
would change both webpack's and Jest's transform. Keep the Jest preset at a non-magic name
(`tests/unit/babel.jest.cjs`), reference it by **absolute** path in `jest.config.js`
(`configFile: path.resolve(__dirname, …)`), pass `babelrc: false`. Gate: `ls babel.config.js .babelrc`
at the repo root stays empty.

## 7. CI note

The unit job is browser-free and fast, but `npm ci` resolves the **whole** manifest including
private `@sencha/*` packages → the job still needs the registry token (and a same-repo fork
guard). Don't add a perpetual "no `app/**` edits" gate — util PRs legitimately touch `app/`.

## 8. The `node` test environment has no `window` — supply one for anything that reads it

Jest's default `testEnvironment: 'node'` is what makes this harness fast, and it is fine
for pure utils and flattened controller methods. It has no `window`, no `document`, no
`location`.

That is invisible until a probe reaches production code that reads one. A controller
deciding between an in-app back-navigation and a route redirect reads
`window.history.length`; under the node env that is a bare `ReferenceError: window is not
defined` inside the callback, which surfaces as a confusing test failure rather than an
obvious environment gap.

Supply a minimal stand-in in the suite that needs it, and let the probe shape it:

```js
beforeEach(() => {
  global.window = { history: { length: 5 } };   // in-app navigation
});
afterEach(() => {
  delete global.window;
});

test('a deep-linked open has no SPA history', () => {
  global.window.history = { length: 1 };        // the branch under test
  …
});
```

Prefer this over switching the whole suite to `jsdom`: the stand-in states exactly which
browser surface the code under test depends on, which is itself worth pinning, and it keeps
the suite's runtime in the milliseconds.

Two related gotchas from the same family:

- **Zeroing seconds widens your clock assertion.** A helper that returns "now with seconds
  zeroed" can land up to 59.999 s *behind* `Date.now()`, so a 5 s tolerance fails at :59
  past the minute. Assert a window wider than a minute, and say why in a comment.
- **Register `Ext.Date` only while a probe still needs it.** Once the code under test stops
  calling it, drop the registration — the fail-loud stub then turns a regression back to
  the framework helper into a named "not stubbed" error instead of a silent wrong answer.
