---
name: extjs-frontend
description: Apply Sencha ExtJS 7 Modern-toolkit SPA conventions — MVVM ViewModel/ViewController binds and formulas, a promise service layer over Ext.Ajax with a single JSON-envelope owner, Ext.define + named-`ui` component system, loadmask + native-submit form lock, Jest Ext-stub and Playwright ComponentQuery harnesses, Sencha Cmd/webpack production-build gate, i18n key sweep. Load ONLY in a repo that actually builds a Sencha ExtJS app — `app.json` carrying `"framework": "ext"`, `@sencha/ext*` in `package.json`, or `Ext.define(` under `app/**`. NOT for React/Vue/Angular/Svelte/HTMX frontends, NOT for the ExtJS Classic toolkit, NOT for backend work; a plain Jest + Playwright + webpack toolchain is not an ExtJS signal.
license: Apache-2.0
metadata:
  author: mind-vault
  version: '0.1'
---

# extjs-frontend

Production patterns for a **Sencha ExtJS 7.x Modern-toolkit SPA** (Material theme) built by
**webpack + `@sencha/ext-webpack-plugin` + Sencha Cmd**, usually with two build profiles
(`desktop` + `phone`) sharing an `app/shared/` layer, and talking to a **remote backend over
REST (`/api/*` JSON envelopes) + optional WAMP/WebSocket** for live updates. Philosophy: the
ViewModel is the state, the ViewController is the only imperative layer, writes go through a
promise service layer, and every claim about framework behavior is proven against the
*installed* toolkit — the Modern widgets repeatedly do less than their names imply.

**Not covered:** the Classic toolkit (different component/layout API), Sencha Architect
projects, and the backend itself. **Pairs with whichever backend skill the API belongs to** —
the frontend contract is REST + optional WAMP; nothing here assumes a backend framework.

## When to use

**Precondition — the gate for every trigger below:** the repo actually builds a Sencha ExtJS
app (`app.json` `"framework": "ext"`, `@sencha/ext*`, or `Ext.define(` under `app/**`; see
*Stack resolution* below). Without that signal none of the triggers fire, however familiar the
symptom sounds.

**TRIGGER when:** editing `Ext.define(...)` classes under `app/**` (views, ViewControllers,
ViewModels, stores, `util`/`service` singletons, overrides); adding a dialog, grid, form field
or `ui`; touching `app.json`, `workspace.json`, `webpack.config.js`, `build.xml`, `.jdk*`; writing or
debugging Jest tests against an `Ext` stub or Playwright specs that drive `Ext.ComponentQuery`;
seeing a raw `<prefix>_*` translation key on screen; a "works in dev, dies in the production
build / deployed image" report; a Sencha dev-server that hangs at *wait until bundle finished*.

**SKIP for:** ExtJS Classic-only code (`Ext.grid.Panel`, `Ext.window.Window`, `renderTo`
layouts); React/Vue/HTMX frontends (their own stack skills); backend-only work; native
mobile clients; **any repo with no ExtJS signal at all** — a shared
Jest/Playwright/webpack toolchain on its own is not a trigger, and neither is the word
"SPA".

## Stack resolution + fail-open

Resolve the frontend stack in this order: `.claude/dispatch.md` `stack: extjs-frontend` pin →
`AGENTS.md` pin → auto-detect → ask once. **Auto-detect signals:** `app.json` with
`"framework": "ext"` and `"toolkit": "modern"`; `@sencha/ext*` in `package.json`; `Ext.define(`
in `app/**`; a `workspace.json` that is Sencha Cmd's (a `frameworks`/`packages` map — *not* Nx;
tools that sniff `workspace.json` misread these repos). **Fail-open clause:** if resolution
yields nothing or is ambiguous (e.g. `app.json` says `"toolkit": "classic"`, or Ext is one of
several frameworks in a monorepo), enforce the craft core only and **announce the unresolved
stack** — never silently assume the Modern-toolkit rules below.

## Pattern

The four `###` headings below are the required frontend contract headings (verbatim strings,
grep-resolved across stack skills — never rephrase them).

### Reactivity model

Client state lives in the **ViewModel** (`Ext.app.ViewModel`: `data`, `formulas`, `stores`);
views bind with `bind: { … '{path}' … }`; the **ViewController** is the only imperative layer
(event handlers, service calls, `Ext.widget` for dialogs). Derived state is a `formula`, not a
`down()`/`setValue` cascade; `Ext.getCmp` and DOM poking are absent. Reads are store-backed
(`type: 'api'`-style proxy owning the envelope, `remoteSort/remoteFilter`); a dialog re-fetches
its stores rather than patching records by hand.

```js
Ext.define('App.view.entity.EntityDialogModel', {
    extend: 'Ext.app.ViewModel', alias: 'viewmodel.entitydialog',
    data: { record: null, editId: null },              // editId: null on Add, real id on Edit
    formulas: {
        isEdit: function (get) { return !!get('editId'); },
        statusBadge: function (get) {                  // formulas may return HTML
            var s = String(get('record.status') || '').toLowerCase();
            return '<span class="badge badge-' + s + '">' +
                Ext.String.htmlEncode(App.util.TranslateText.t('app_status_' + s)) + '</span>';
        }
    },
    stores: { categories: { type: 'categories', autoLoad: true } }
});
```

Traps that hide behind green tests: a **seeded `Ext.create('Ext.data.Model', {...})` is a
phantom** with a plausible auto-id — bind the create/update discriminator to a dedicated VM prop
(`editId`), never `{record.id}`; a config whose initial value equals its default (`null`) **never
fires its updater** — set VM data explicitly; a **formula-bound value used as a two-way target
warns** — bind wrapper-field `*Value` configs to plain data paths; the store `load` event
delivers an **Array**, not a Collection (`records.each` is a TypeError) — helpers accept
`Array | Store | Collection`; `Store.findRecord` is *startsWith* by default (`1` matches `10`) —
prefer the row ViewModel's `record` over a store lookup, or pass `exactMatch: true`. Detail: [MODERN_COMPONENT_FOOTGUNS](references/MODERN_COMPONENT_FOOTGUNS.md).

### Partial/fragment response

**An ExtJS Modern SPA has none.** The server never returns HTML fragments; every call is JSON in an
envelope, and the UI re-fetches stores after a write. Read the API's actual envelope, then
pin it; the recurring shape is:

```jsonc
{ "success": true,  "result": [ … ], "total": 150 }          // reads (paged: total)
{ "success": true,  "result": { … } }                          // single entity / write echo
{ "success": false, "msg": "Series has issued documents" }     // 2xx OR 404/409/422 — SAME shape
{ "success": false, "errors": { "field": ["msg", …], "reason": "…" } }  // 400 validation
```

Two rules follow. (1) The envelope has **one owner** — a shared proxy class (`type: 'api'`,
`rootProperty: 'result'`, `totalProperty: 'total'`); outlier endpoints override per instance
(`rootProperty: 'data'` / `''` = whole payload); pin it with a test. (2) **A 2xx body may say
`success:false`** — the service layer resolves it (callers branch on `success`), and rejects only
on non-2xx with ONE normalized error `{status, errors, body, message, response}` whose `message`
follows the three-branch resolution (`errors.reason` → joined field messages → `body.msg` →
translated default). Raw `Ext.Ajax` failure handlers that read one shape silently swallow the
other — hence the [service layer](references/SERVICE_LAYER.md) is a *precondition* for any error
UX that depends on backend error bodies. Live updates (WAMP) push topics, never fragments; the
handler reloads the affected store.

### Component system

Reusable UI is an **`Ext.define` class with an `xtype`/`alias`**, composed by config. Three
layers of a typical repo: **`app/shared/`** (models, stores, `util`, `service`, cross-build
dialogs), **`app/desktop/`** and **`app/phone/`** (per-build views; each has its own
`Application.js` + `Application.scss`); builds never import each other — cross-build code goes to
`shared`. Styling is the **named `ui` catalogue** (`@include button-ui($ui: 'primary-action-button')`
in `Application.scss`, applied as `ui: 'primary-action-button'`); the stock Material components are
deliberately *unstyled* until a `ui` is applied, so **no raw `Ext.*` UI without a `ui`/`cls`**.
Form inputs are commonly an app-prefixed **wrapper field family** (`apptextfield`, `appselectfield`, `apptogglefield`, …):
a container exposing `<xtype>Label/Name/Value/Info/Required/Hidden` configs (labels/info are
translation keys) that publishes `*Value` back through the wrapper. Wrapper fields typically
**exist only in the desktop build**; phone styles raw fields via `ui` from *its own* catalogue —
names overlap but diverge, verify per build.

Dialogs are mounted imperatively and are the unit of feature work:

```js
// controller of the parent grid/panel
var dlg = Ext.widget('entitydialog', {
    record: rec,                                   // null on Add
    listeners: {
        saved:     function () { this.getViewModel().getStore('entities').load(); },
        cancelled: Ext.emptyFn,
        scope: this
    }
});
dlg.show();                                        // dialog fires 'saved' / 'cancelled', then closes
```

Grid extras that must be `requires`'d where used: custom `Ext.data.summary` types (extend
`Ext.data.summary.Sum`, `alias: 'data.summary.<name>'`, skip rows by flag), `plugin.gridfilters`
(Modern *does* ship per-column filters + column show/hide — verify a bot's "Classic-only" claim
against `node_modules/@sencha/ext-modern`). Guard every deferred callback that captured a
component (`if (cmp.destroyed) return; var vm = cmp.getViewModel(); if (!vm) return;`).

### Form-submission lock

Four parts, all required — the framework provides none of them reliably in Modern 7.x:

```js
save: function () {
    var view = this.getView(), form = this.lookup('form');
    if (view.isMasked && view.isMasked()) { return; }                 // 1. in-flight guard
    if (!form.validate()) { return; }
    view.mask({ xtype: 'loadmask', message: App.util.TranslateText.t('app_common_saving') });
    try {                                                              // 2. unmask on throw
        var params = this.buildSaveParams(form.getValues());           //    (a throw here would mask forever)
        App.service.Entities.save(params, this.getViewModel().get('editId'))
            .then(function (body) {
                view.unmask();                                         // 3. unmask FIRST in then/catch
                if (!body.success) { return App.service.Api.toastError({ message: body.msg }); }
                view.fireEvent('saved', view); view.close();
            }, function (err) { App.util.FormErrorHandler.handleError(view, err); }); // unmasks first
    } catch (e) { view.unmask(); App.service.Api.toastError({ message: e.message }); }
},
// 4. native-submit guard: Enter in a Modern formpanel field fires the browser's <form> submit and
//    RELOADS THE SPA (field values in the URL) — Ext's own onSubmit does not stop it in 7.7.
onFormPainted: function (form) {
    if (this._submitGuardAttached || !form.element || !form.element.dom) { return; }
    this._submitGuardAttached = true;
    var ctr = this;
    form.element.dom.addEventListener('submit', function (e) { e.preventDefault(); ctr.save(); });
}
// view: { xtype: 'formpanel', reference: 'form', listeners: { painted: 'onFormPainted' } }
```

Payload shaping is part of the lock: an unchecked Modern `checkbox` serializes `null` and is
**omitted** from `getValues()` — enumerate the full boolean set and coerce `values[f] ? 1 : 0`
(never iterate present keys on a partial-update PUT); `emailfield` sets only `inputType`
(add `validators: ['email']`); `togglefield` always reports.

## Optional extras (stubs — detail loads on demand)

- **Service layer** — `App.service.Api` (promise wrapper over `Ext.Ajax`, rides the global
  `beforerequest` host/CSRF + `requestexception` 401 hooks, never toasts) + per-domain
  singletons owning URL strings + `FormErrorHandler.handleError/handleFailure/handleBody`
  (unmask → mark `[name=field]` invalid → toast). Migration precondition + `requires` indexing:
  [SERVICE_LAYER](references/SERVICE_LAYER.md).
- **Unit tests** — Jest with a fail-loud `Proxy` `Ext` stub (`Ext.define` flatten,
  `Ext.__stub.register`, `makeModel`), controller probes via `Ctl.method.call(fakeThis)`:
  [JEST_EXT_STUB_HARNESS](references/JEST_EXT_STUB_HARNESS.md).
- **E2E** — Playwright driving `Ext.ComponentQuery` → DOM id, ONE `**/api/**` mock handler with
  captured fixtures, dialogs mounted via `Ext.syncRequire` + `Ext.widget`, sentinel +
  `framenavigated` probes: [PLAYWRIGHT_COMPONENTQUERY_E2E](references/PLAYWRIGHT_COMPONENTQUERY_E2E.md).
- **i18n as backend data** — strings are `<prefix>_*` keys through a translate util over a
  dictionary fetched at boot; missing keys are invisible to unit + mock e2e; the static sweep
  is the gate: [I18N_KEY_SWEEP](references/I18N_KEY_SWEEP.md).
- **Toolchain / build / deploy** — JDK 8–11 (Nashorn), portable JRE before `npm ci`, dev-server
  lock hygiene, production build = the image build gate, cache policy for non-hashed output:
  [SENCHA_TOOLCHAIN_AND_BUILD](references/SENCHA_TOOLCHAIN_AND_BUILD.md).
- **Refactor pinning** — facade/rename/batch migrations pin producer types + bridge value
  contracts + exact classifiers: [REFACTOR_CONTRACT_PINNING](references/REFACTOR_CONTRACT_PINNING.md).

## ✅ DO / ❌ DON'T

| ✅ DO | ❌ DON'T |
| --- | --- |
| Bind the create/update discriminator to a VM prop that is `null` on Add (`editId`) | Bind the hidden `id` to `{record.id}` of a seeded `Ext.data.Model` — its phantom id makes create issue a PUT |
| Singleton util → plain members (`singleton: true, isX: fn`) | `singleton: true` **plus** `statics: {}` — statics live on the class, the namespace resolves to the instance; the Jest stub can't catch it |
| Enumerate every boolean field and coerce `? 1 : 0` before a partial-update PUT | Iterate the present keys of `getValues()` — unchecked `checkbox` is omitted, flags silently clear |
| Attach the native `submit` listener on `painted` and route Enter to `save()` | Trust `formpanel`'s own `onSubmit` — Enter reloads the SPA with the form in the query string |
| `view.unmask()` FIRST in every `.then`/`.catch`; wrap the mask→request body in `try/catch` that unmasks | Mask, then compute params that can throw — the loadmask never clears |
| Accept `Array \| Store \| Collection` in helpers fed by store events | `records.each(...)` on the `load` event payload — it is an Array |
| Prefer the row ViewModel's `record`; `findRecord(..., exactMatch=true)` when you must look up | `store.findRecord('id', 1)` — default is *startsWith*, `1` matches `10` |
| Declare every shared `util`/`service` class in `requires` | Reference `App.service.X` inline only — the dev loader never indexes it (works only in production) |
| Route writes through `Api.verb().then(ok, sink)` and branch on `body.success` on 2xx | Raw `Ext.Ajax.request` with a `failure` that reads one error shape — the 400 vs 409/422 twin is swallowed |
| Verify a `ui` name against the build's own `Application.scss`; use wrapper fields on desktop, raw+`ui` on phone | Import desktop wrapper fields into phone, or ship `{ xtype: 'button', text }` with no `ui` |
| Ship a mock e2e that seeds rows and asserts no `pageerror` | Trust an empty-grid mount — Modern cell renderers run only when there are rows |
| Verify a review bot's "wrong class name" claim in `node_modules/@sencha/ext-modern` (symbol found + replacement absent = bot wrong) | Apply a "Classic vs Modern" rename because it sounds right |
| Prove the production compile with the image build (`build:*` + assert the bundle exists) | Treat green `test:unit` + `test:e2e` as proof the Closure/Fashion build passes |
| Write the regression probe RED (`git stash` the fix), commit, then GREEN; pin structure (`Object.keys(vm.stores)`) | Pin literal names that a rename breaks; add probes after the fix so `git log` can't prove order |

## When NOT to use these patterns

- **Classic toolkit** apps — grid/form/window APIs and the theming mixins differ; the
  Modern-specific traps (checkbox `null`, native submit, `emailfield`) do not transfer 1:1.
- **Backend work** — the API's own stack skill owns validation, envelopes' server side, auth.
- **Non-Sencha bundlers without Sencha Cmd** (e.g. ExtJS loaded from a CDN in a plain page):
  the toolchain/build reference is irrelevant; the component/service/testing references still apply.
- **Server-rendered fragment UIs** — the *Partial/fragment response* section documents an
  absence; a fragment-driven stack has its own skill.

## References

- [MODERN_COMPONENT_FOOTGUNS](references/MODERN_COMPONENT_FOOTGUNS.md) — phantom ids, singleton+statics, empty-grid renderers, `emailfield`, native submit, checkbox `null`, deferred-callback teardown, wrapper-field binds, formulas as HTML, custom summaries, desktop/phone split, stay-open dialogs that must disarm Save (an unguarded one writes a duplicate per click), console ops against a live app (the first queried view is not the active one; destructive calls list-first and one at a time), invented `ui:` names that render invisible-but-functional chrome, a base `record` config that nulls any non-Model value, formulas an optional ancestor dependency blocks forever, desktop date pickers whose ui comes from `floatedPicker` over an invisible selected cell.
- [SERVICE_LAYER](references/SERVICE_LAYER.md) — Api singleton sketch, FormErrorHandler contract, envelope truth table, migration precondition, `requires` indexing, controller before/after.
- [JEST_EXT_STUB_HARNESS](references/JEST_EXT_STUB_HARNESS.md) — fail-loud Proxy stub, define flatten, makeModel, per-test registration, controller probes with `fakeThis`, RED-first, structural pins.
- [PLAYWRIGHT_COMPONENTQUERY_E2E](references/PLAYWRIGHT_COMPONENTQUERY_E2E.md) — ComponentQuery bridge, single-handler mock bootstrap, `syncRequire`+`widget` mounting, toast reading, sentinel/`framenavigated` probe, dev-server collision + port reuse, phone-project skip, mock mode still fetching real external hosts (a dead one fails suites that never mention it) + the known-green-commit re-run that splits code from environment.
- [SENCHA_TOOLCHAIN_AND_BUILD](references/SENCHA_TOOLCHAIN_AND_BUILD.md) — JDK 8–11 Nashorn, portable JRE + `npm ci` order, workspace-lock hygiene, production-build gate, Docker image, cache policy, microloader double-launch, autobahn copy, registry token as BuildKit secret, swap-under-live-tab.
- [I18N_KEY_SWEEP](references/I18N_KEY_SWEEP.md) — keys as backend data, dynamic key families, per-feature `translations.json` → idempotent seed SQL, sweep gate, cache drop.
- [REFACTOR_CONTRACT_PINNING](references/REFACTOR_CONTRACT_PINNING.md) — `==`→`===` is a contract change, bridge value contracts, exact classifiers in batch scripts.
- [Sencha ExtJS Modern docs](https://docs.sencha.com/extjs/7.7.0/modern/) · [`@sencha/ext-webpack-plugin`](https://www.npmjs.com/package/@sencha/ext-webpack-plugin) · [Playwright](https://playwright.dev) · [Jest](https://jestjs.io)
