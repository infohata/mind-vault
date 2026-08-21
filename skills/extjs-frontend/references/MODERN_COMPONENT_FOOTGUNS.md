# ExtJS Modern component / runtime footguns

Traps that pass `node --check`, a Jest Ext-stub and a mock-empty-grid e2e, and are wrong only
against the *installed* framework with *real* rows. Meta-rule: **trust the installed toolkit's
empirically-observed behavior over the widget's name or the API docs** — write a probe, or run
the real build, before believing a `formpanel` prevents Enter or an `emailfield` validates.

## 1. Seeded `Ext.create('Ext.data.Model', {...})` is a phantom → create issues PUT

**Incident.** Adding a new entity sent `PUT /api/entities/106` (404). `106` looked like a real id.
The Add-mode dialog seeded defaults with `vm.set('record', Ext.create('Ext.data.Model', {active: 1}))`;
a model with no `id` is a phantom and gets a session-sequential auto-id; the hidden field bound
`{record.id}` picked it up; the service's `if (id && id > 0) PUT else POST` chose PUT.

**Fix.** Decouple the discriminator from the seed:

```js
config: { record: null },
updateRecord: function (record) {              // fires only for a non-null (edit) record
    var vm = this.getViewModel();
    vm.set('record', record);
    vm.set('editId', record ? record.get('id') : null);
},
// hidden field
{ xtype: 'hiddenfield', name: 'id', bind: { value: '{editId}' } }     // never {record.id}
```

**Rule.** Never bind a create/update discriminator to a generic model you instantiated for
default-seeding. Seed defaults via a prop that is `null` on create, or a model class with `id`
explicitly absent.

## 2. `singleton: true` + `statics: {}` → methods unreachable at runtime

**Incident.** `TypeError: App.util.Helper.isUnlimited is not a function` from a grid renderer —
with the Jest suite green. `singleton: true` resolves the namespace to the **instance**; `statics`
live on the **class**. The Jest stub flattens both onto one object and cannot see the difference.

```js
// ❌
Ext.define('App.util.Helper', { singleton: true, statics: { isUnlimited: fn } });
// ✅ pick ONE access model
Ext.define('App.util.Helper', { singleton: true, isUnlimited: fn });        // Namespace.method()
Ext.define('App.util.Helper', { statics: { isUnlimited: fn } });            // class statics, no singleton
```

## 3. An empty mock grid hides throwing cell renderers

Modern grid **cell renderers run only when rows exist**. An e2e that mounts a panel over an empty
mock store proves the container mounts, nothing more (#2 shipped through exactly this hole).
Seed rows covering every renderer branch and assert no `pageerror`
(see [PLAYWRIGHT_COMPONENTQUERY_E2E](PLAYWRIGHT_COMPONENTQUERY_E2E.md) § Seed rows).

## 4. Modern 7.7 DOES ship `gridfilters` + column show/hide — verify bot claims against the install

A review bot flagged `requires: ['Ext.grid.filters.Plugin']` as "Classic; Modern wants
`Ext.grid.plugin.GridFilters`". Both halves were wrong: the first *is* defined in
`node_modules/@sencha/ext-modern/src/grid/filters/Plugin.js`; the second exists nowhere.
Applying the "fix" would have broken the loader. Enable with `plugins: { gridfilters: true }` +
per-column `filter: 'string' | 'number' | 'date' | 'boolean' | { type: 'list', options }`;
`remoteFilter: true` serializes into the `filter` request param. Column visibility is native to
the header menu (`hideable` default; `hidden: true` ships collapsed); `plugin.gridviewoptions` is
the long-press alternative.

**Two tells that a framework-API claim is wrong:** the current symbol IS found in the installed
package, and the suggested replacement is NOT found anywhere. The e2e booting the real dev build
with the plugin present is the clincher.

## 5. `emailfield` validates nothing

`Ext.field.Email` only sets `inputType: 'email'` (a keyboard hint; HTML5 validation fires only on
a *native* submit, which `form.validate()` never triggers). `not-an-email` saves. Add the
validator: `{ xtype: 'emailfield', name: 'email', required: true, validators: ['email'] }`
(`Ext.data.validator.Email`, alias `data.validator.email`). Prove it with an "enter a bad value →
no save + inline error" e2e; a `required`-only test passes on the broken config. Same suspicion
for every semantically-named field (`urlfield`, `numberfield`).

## 6. Enter in a `formpanel` reloads the whole SPA

**Incident.** Enter in a series-name field reloaded the app with the form values in the query
string and saved nothing (reproduced on a real pilot after passing every gate). A Modern
`formpanel` renders a real `<form>` with a hidden submit input; Ext's `Ext.form.Panel.onSubmit`
is supposed to `stopEvent()` under `standardSubmit: false` but did not in this 7.7 build, and a
config-level `listeners: { submit: { element: 'element' } }` never fires.

```js
// view
{ xtype: 'formpanel', reference: 'form', listeners: { painted: 'onFormPainted' } }
// controller
onFormPainted: function (form) {
    if (this._submitGuardAttached || !form.element || !form.element.dom) { return; }
    this._submitGuardAttached = true;
    var ctr = this;
    form.element.dom.addEventListener('submit', function (e) { e.preventDefault(); ctr.save(); });
}
```

Latent in **every** `formpanel` dialog; a global `Ext.form.Panel` override fixes it app-wide.
Probe technique: `window.__alive = 'yes'` sentinel + `page.on('framenavigated')` counter → press
Enter → assert sentinel survives, navigation delta 0, and the save side-effect happened.

## 7. Unchecked Modern `checkbox` serializes `null` → dropped from `getValues()`

`Ext.field.Checkbox.getSubmitValue()` returns `checked ? value : null`; `form.getValues()` omits
the key. A param-shaper that iterates present keys sends nothing for unchecked boxes → on a
partial-update PUT the backend keeps the old `1` (or a `values.x ? 1 : 0` loop never sees `x`).
`togglefield` always reports; `checkbox` does not.

```js
BOOLEAN_FIELDS: ['active', 'main', 'email_confirmed', 'two_factor_enabled'],
buildSaveParams: function (values) {
    var p = {}; this.BOOLEAN_FIELDS.forEach(function (f) { p[f] = values[f] ? 1 : 0; }); // absent → 0
    return Ext.apply(p, { name: values.name /* … */ });
}
```

Unit-test with an **all-absent fixture** — the case that separates "enumerate" from
"iterate present keys".

## 8. Deferred callbacks outlive the component

`Ext.defer(fn, 50)` from a `painted` listener; dialog closed within 50 ms → `owner.getViewModel()`
is `null` → `TypeError` × N fields. Guard at fire time:

```js
Ext.defer(function () {
    if (field.destroyed || owner.destroyed) { return; }
    var vm = owner.getViewModel(); if (!vm) { return; }
    // …
}, 50);
```

## 9. `save()` that masks then throws leaves the loadmask forever

`view.mask(); var p = this.buildParams(values); Api.put(...)` — a `TypeError` in `buildParams`
(e.g. `records.each` on an Array, a null record) escapes before the request, nothing unmasks, the
dialog is dead. Wrap the body: `try { … } catch (e) { view.unmask(); Api.toastError({message: e.message}); }`.
In promise chains call `view.unmask()` **first** in both `.then` and `.catch` — before branching on
`body.success`, before toasting; `FormErrorHandler.handleBody` starts with `view.unmask()` for
the same reason.

## 10. Wrapper-field two-way binds

A wrapper field (`appselectfield` = container with label + input + info button) exposes
`appselectfieldValue` etc. as `config` and publishes back through the wrapper (its inner field
binds `value: '{appselectfield_value}'` on the wrapper's own ViewModel; `updateAppselectfieldValue`
writes it). Three consequences:

- Bind `appselectfieldValue: '{record.field}'` to a **data path**; binding it to a **formula**
  makes the two-way publish warn (formulas are read-only) — derive in the controller instead.
- A config whose initial value equals its default (`null === null`) **never fires its
  updater** — set the VM data explicitly (`vm.set('x', value)`) when the initial value matters.
- Store-backed selects: the store may load after paint; the `painted` re-apply of the bound
  value is why the deferred guard in #8 exists.

## 11. Formulas may return HTML; escape user data

Status badges: `formulas.statusBadge` returns `'<span class="badge badge-' + status.toLowerCase() + '">' + Ext.String.htmlEncode(t('app_status_' + status.toLowerCase())) + '</span>'`,
bound to a component `html`. Always `Ext.String.htmlEncode` anything user- or backend-authored;
class names from the enum lowercased keep CSS declarative. Enumerate `'app_status_' + value`
families in the i18n sweep ([I18N_KEY_SWEEP](I18N_KEY_SWEEP.md)).

## 12. Custom `Ext.data.summary` types

To exclude voided rows from grid column totals:

```js
Ext.define('App.data.summary.LiveSum', {
    extend: 'Ext.data.summary.Sum', alias: 'data.summary.livesum',
    calculate: function (records, property, root, begin, end) {
        var sum = 0, rec;
        for (var i = begin; i < end; i++) {
            rec = records[i];
            if (rec && rec.get && rec.get('deleted')) { continue; }
            sum += Number(this.extractValue(rec, property, root)) || 0;
        }
        return sum;
    }
});
// column: { summary: 'livesum' } — and the VIEW that hosts the grid MUST list
// 'App.data.summary.LiveSum' in `requires`, or the dev loader never fetches it.
```

## 13. Store `load` payload is an Array; `findRecord` is startsWith

- The `load` event's `records` is an **Array** — `records.each` throws. Helpers that may be fed by
  `load`, `getRange()` or a Collection accept all three:
  `Array.isArray(r) ? r : typeof r.getRange === 'function' ? r.getRange() : (r.items || [])`.
- `store.findRecord('id', 1)` matches `10`, `100` (default `anyMatch=false`, but `startsWith`).
  Pass `exactMatch=true` (`findRecord(field, value, 0, false, false, true)`), or — better in a
  grid row button handler — read the **row ViewModel's** `record` (`btn.lookupViewModel().get('record')`)
  and fall back to the exact lookup only after a store reload.

## 14. Two build profiles

Wrapper field components usually **exist only in the desktop build**; the phone build styles raw
`textfield`/`selectfield`/`checkboxfield` via `ui` (`'default'`, `'default-picker'`,
`'default-checkbox'`, `'default-toggle'`) and has its **own `Application.scss` `ui` catalogue** —
names overlap (`primary-action-button`, `std-dialog`, `tooltip-*`) but diverge (e.g. the danger
button). Verify the `ui` in the build you are in; never import a desktop wrapper into phone;
cross-build logic lives in `app/shared/`. Every Sencha full build regenerates `generatedFiles/`
and drops the *other* profile's manifest — a phone e2e stuck at `LOADING…` after `build:desktop`
is that ([SENCHA_TOOLCHAIN_AND_BUILD](SENCHA_TOOLCHAIN_AND_BUILD.md)).

## 15. Stay-open dialogs must disarm Save

A create dialog that deliberately **stays open after a successful save** (to enable follow-up
buttons — send email/SMS, print) inherits none of the close-on-save protection: with no
in-flight guard, no mask, and Save still armed, every extra click POSTs a fresh duplicate. An
operator produced **twelve duplicate records** before noticing — the dialog gave zero feedback
that the first click had already succeeded. The full recipe, all four parts:

1. **Re-entry guard**: `if (this._saving || vm.get('createdRecord')) return;` at the top of
   `save()` — covers both the in-flight double-click and clicks after success.
2. **Mask during the POST** (`view.mask({xtype: 'loadmask'})`); the failure path unmasks via the
   shared error handler's contract, the success path unmasks explicitly.
3. **Disarm the button by state, not by code path**: `bind: { hidden: '{createdRecord}' }` on
   Save — once the record exists there is nothing left to save, and the binding survives every
   route into that state.
4. **`fireEvent('saved')`** so the opener refreshes — a stay-open dialog otherwise leaves the
   parent view stale behind it.

The e2e probe that pins it: call `save()` three times (two synchronous, one after success) and
assert exactly **one** wire POST and the button hidden.

## 16. Console ops against a live app: the first queried view is not the active one

When a backend endpoint has no UI yet (a delete/repair operation an operator needs *now*),
the right console vehicle is the app's own `Ext.Ajax` — it rides the session's global hooks
(CSRF token, host prefix, 401 handling), so no cookie/token hand-crafting. Two disciplines
make it safe:

1. **`Ext.ComponentQuery.query('xtype')[0]` is the FIRST instance, not the active one.**
   Apps that keep previously-opened views alive (tabbed detail views) return a background
   instance first — an operator pulled a *different record's* id from `[0]` and only
   noticed because the returned rows looked wrong. Enumerate before touching anything:
   `Ext.ComponentQuery.query('xtype').map((c,i)=>({i, visible: c.isVisible(true), key: …}))`
   and pick the `visible: true` row. Deriving ids from the picked view's own store/proxy
   state (`getProxy().getExtraParams()`) beats retyping them.
2. **List first, then destructive calls one at a time — never a loop.** Print the target
   rows (`console.table`) and confirm each id before its call; fire each destructive
   request individually and wait for its success log. A pasted cleanup loop once produced a
   13-request burst of 4xx that an edge fail2ban read as an attack and banned the
   operator's IP estate-wide (see [HARDENING.md](../../deployment/references/HARDENING.md) § fail2ban
   behind proxies).

## 17. `ui:` names are unchecked strings — an invented one renders invisible; theme vars can resolve dark

`ui: 'some-name'` on any component is a freeform string suffix for CSS class generation —
**nothing validates it exists**. A button given a ui name no SCSS defines renders with no
background/color styling at all: observed live as **white-on-white dialog footer buttons**
(fully functional, completely invisible) that every unit test and mock-mode e2e passed,
because styling is real-theme-only surface. Same family: a container styled with
`var(--highlight-color)` assumed a light grey; the Material theme resolves it **dark**,
producing theme-blue text on dark grey.

- ✅ **DO** copy the exact `ui:` pair from a sibling component of the same kind (dialogs'
  footer buttons have a house pair; grep a neighboring dialog) — and when a name looks
  plausible, `grep -r "$ui:" --include='*.scss'` (or the generated `$ui` list in the app's
  SCSS) before using it. Zero hits = invisible component.
- ✅ **DO** use explicit colors in new SCSS blocks unless you have verified what the theme
  variable resolves to in the *built* theme (dev and production themes can differ).
- ❌ **DON'T** expect any automated gate to catch this: Ext raises nothing, Jest stubs see
  nothing, mock-mode e2e asserts behavior not contrast. Real-theme rendering (pilot smoke,
  screenshot diffing if available) is the only surface that shows it — put new-chrome
  visibility checks in the smoke list whenever a change introduces a new `ui:` name or a
  new SCSS block.

## Related

- [JEST_EXT_STUB_HARNESS](JEST_EXT_STUB_HARNESS.md) — why the stub cannot catch #2 (define flatten).
- [PLAYWRIGHT_COMPONENTQUERY_E2E](PLAYWRIGHT_COMPONENTQUERY_E2E.md) — seed rows (#3), sentinel probe (#6).
- [SERVICE_LAYER](SERVICE_LAYER.md) — the write path #9 sits on.
