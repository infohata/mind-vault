# Service layer — `Api` singleton, `FormErrorHandler`, and the migration precondition

Reads are stores (a shared proxy owns the envelope). Writes are **not** store writers; they go
through one promise wrapper over `Ext.Ajax` plus per-domain services that own URL strings.

## 1. Envelope truth table

| HTTP | Body | `Api` outcome | Caller |
| --- | --- | --- | --- |
| 2xx | `{success:true, result}` | resolve(body) | use `result` |
| 2xx | `{success:false, msg}` | **resolve(body)** | branch on `success`, toast `msg` |
| 400 | `{success:false, errors:{field:[…], reason?}}` | reject(err) — `err.errors` set | `FormErrorHandler.handleError(view, err)` marks fields |
| 404/409/422 | `{success:false, msg}` | reject(err) — `err.message = msg` | toast |
| 401 | anything | reject(err) **and** the global `requestexception` hook redirects to login | nothing extra |
| 5xx / no body | — | reject(err) — `message` = translated default | toast |

`message` resolution (three-branch, identical in `Api` and `FormErrorHandler`):
`errors.reason` → joined `field: msg` lines → `body.msg` → `t('app_common_server_error')`.

**Why the layer is a precondition, not a refactor.** A raw `Ext.Ajax.request` site with
`failure: function (r) { toast(JSON.parse(r.responseText).msg) }` shows *nothing* on a 400
(`errors`, no `msg`); a site that reads `errors` shows nothing on 409. Any new error UX that
depends on backend error bodies (a 409 "already issued" text, per-field marks) must first move
the site onto `Api` — otherwise the other shape is silently swallowed and the dialog just unmasks.

## 2. `Api` sketch (generic)

```js
Ext.define('App.service.Api', function () {
    function defaultError() { return App.util.TranslateText.t('app_common_server_error'); }

    function normalizeError(response) {
        var body = response.responseText ? Ext.decode(response.responseText, true) : null,
            errors = (body && body.errors) || null, message;
        if (errors) {
            var lines = [];
            for (var f in errors) {
                if (f === 'reason') { continue; }
                lines.push(f + ': ' + (Array.isArray(errors[f]) ? errors[f].join(', ') : errors[f]));
            }
            message = errors.reason || lines.join('<br>') || defaultError();
        } else {
            message = (body && body.msg) || defaultError();
        }
        return { status: response.status, errors: errors, body: body, message: message, response: response };
    }

    function request(cfg) {
        return new Ext.Promise(function (resolve, reject) {
            var ajax = Ext.apply({}, cfg);
            ajax.success = function (r) { resolve((r.responseText && Ext.decode(r.responseText, true)) || {}); };
            ajax.failure = function (r) { reject(normalizeError(r)); };
            Ext.Ajax.request(ajax);            // NEVER fetch/XHR — the global hooks own host prefix, CSRF, 401
        });
    }

    function verb(method) {
        return function (url, payload, opts) {
            var cfg = { url: url, method: method };
            if (payload) { cfg[(opts && opts.json) ? 'jsonData' : 'params'] = payload; }
            return request(cfg);
        };
    }

    return {
        singleton: true,
        request: request, get: verb('GET'), post: verb('POST'), put: verb('PUT'), del: verb('DELETE'),
        // The house toast for fire-and-forget writes. Api itself NEVER calls it.
        toastError: function (err) {
            Ext.toast({ message: (err && err.message) || defaultError(), alignment: 't-t', ui: 'tooltip-error', timeout: 5000 });
        }
    };
});
```

Invariants: rides `Ext.Ajax` (the app's `beforerequest` hook prepends `Ext.API_CONFIG.url` and
`X-CSRF-TOKEN`; `requestexception` handles 401) · never toasts · resolves 2xx even when
`success:false` · one normalized error shape · `del` not `delete` (reserved word in old parsers).
Pin with a Jest test (verbs → `Ext.Ajax.request` cfg; error normalisation) **and** an e2e that
proves the class loads in the dev build.

## 3. Domain service

```js
Ext.define('App.service.Entities', {
    singleton: true,
    requires: ['App.service.Api'],
    list:   function (params)   { return App.service.Api.get('/api/entities', params); },
    save:   function (data, id) { return id ? App.service.Api.put('/api/entities/' + id, data, { json: true })
                                            : App.service.Api.post('/api/entities', data, { json: true }); },
    remove: function (id)       { return App.service.Api.del('/api/entities/' + id); }
});
```

Keep endpoint quirks **in the service** (`with_relations: 1`, `id` kept in the body on update);
controllers never hardcode `/api/...` for writes.

## 4. `FormErrorHandler` contract

```js
Ext.define('App.util.FormErrorHandler', {
    singleton: true,
    handleFailure: function (view, response) {           // legacy raw-response twin
        var obj; try { obj = response.responseText ? JSON.parse(response.responseText) : {}; } catch (e) { obj = null; }
        this.handleBody(view, obj);
    },
    handleError: function (view, err) { this.handleBody(view, (err && err.body) || null); },   // Api twin
    handleBody: function (view, obj) {
        view.unmask();                                   // CONTRACT: unmask FIRST — dialogs mask before save
        var def = App.util.TranslateText.t('app_common_server_error'), toast = function (m) {
            Ext.toast({ message: m, alignment: 't-t', ui: 'tooltip-error', timeout: 5000 });
        };
        if (obj === null) { return toast(def); }
        if (obj.errors) {
            var lines = [];
            for (var f in obj.errors) {
                if (f === 'reason') { continue; }
                var cmp = view.down('[name="' + f + '"]'); if (cmp) { cmp.addCls('x-invalid'); }
                lines.push(f + ': ' + (Array.isArray(obj.errors[f]) ? obj.errors[f].join(', ') : obj.errors[f]));
            }
            return toast(obj.errors.reason || lines.join('<br>') || def);
        }
        toast(obj.msg || def);
    }
});
```

Sinks — **the caller picks, `Api` never toasts**: `Api.toastError(err)` for fire-and-forget
writes (grid toggles, deletes); `FormErrorHandler.handleError(view, err)` for dialog/form saves
(unmask → mark → toast). Field marking needs the field's `name` to equal the backend key.

## 5. Controller before / after

```js
// ❌ before — one shape read, no unmask on throw, URL inline
save: function () {
    var view = this.getView(); view.mask();
    Ext.Ajax.request({
        url: '/api/entities/' + this.getViewModel().get('record.id'), method: 'PUT',
        params: this.lookup('form').getValues(),
        success: function (r) { view.unmask(); view.fireEvent('saved'); view.close(); },
        failure: function (r) { view.unmask(); Ext.toast(JSON.parse(r.responseText).msg); }   // 400 → "undefined"
    });
}

// ✅ after
requires: ['App.service.Entities', 'App.service.Api', 'App.util.FormErrorHandler'],   // dev-loader indexing!
save: function () {
    var view = this.getView(), vm = this.getViewModel(), form = this.lookup('form');
    if (view.isMasked && view.isMasked()) { return; }
    if (!form.validate()) { return; }
    view.mask({ xtype: 'loadmask', message: App.util.TranslateText.t('app_common_saving') });
    try {
        App.service.Entities.save(this.buildSaveParams(form.getValues()), vm.get('editId'))
            .then(function (body) {
                view.unmask();
                if (!body.success) { return App.service.Api.toastError({ message: body.msg }); }
                view.fireEvent('saved', view, body.result); view.close();
            }, function (err) { App.util.FormErrorHandler.handleError(view, err); });
    } catch (e) { view.unmask(); App.service.Api.toastError({ message: e.message }); }
}
```

## 6. `requires` indexing — why inline-only refs break the dev build

Production concatenates the whole graph (Cmd's analyzer scans inline `App.x.Y` usages).
Development uses the dynamic loader: `app.js` is a stub, classes load on demand through the
`paths` map in `generatedFiles/<profile>.json`, built **only from declared dependencies**
(`requires`/`extend`/`xtype`/alias). A class referenced inline only is not in the map; a bare
`App.service.Api` reads `undefined`; `Ext.create`/`Ext.syncRequire` 404 at
`app/<build.id>/src/service/Api.js`. Symptom: works in production, `Cannot read properties of
undefined (reading 'Api')` in dev and in every dev-server e2e. Every consuming class lists its
`util`/`service` classes in `requires`; verify with `curl -s localhost:<port>/generatedFiles/desktop.json | grep service`.
In e2e, `Ext.syncRequire('App.service.Api')` before a bare namespace access.

## 7. Migration recipe (opportunistic, feature-by-feature)

1. Add/extend the domain service method (URL + verb + payload shape + quirks).
2. Replace the call site with `service.X.method(...).then(ok, sink)`; keep bespoke failure text;
   add the `requires`.
3. Delete hand-rolled `JSON.parse`/failure plumbing.
4. Don't migrate behavior you can't verify — a real-backend smoke of that feature is the gate;
   the mock e2e only proves the request shape.

Documenting a domain: a "dialogs ↔ endpoints ↔ statuses" table (surface · class · endpoint(s) ·
payload/notes) plus the error bodies each endpoint answers is the shape reviewers can check a
change against.
