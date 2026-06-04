# Django `form_invalid` returns 200, not 422 — status alone is insufficient for HTMX flows

Django's `FormView` / `CreateView` / `UpdateView` default `form_invalid()` returns `render_to_response(...)` — status **200** with the re-rendered form-with-errors body. There's no 4xx/422 surface for validation failure.

HTMX clients that gate on response status (e.g. "close the modal on 2xx", listeners keying on `htmx:afterRequest` + `event.detail.successful`, walkers re-fetching lists on 2xx) interpret this as success: modals close on rejected submissions, the user loses their typed input, success toasts fire.

## Fix options

### Option 1 — Override `form_invalid` to return 422 (mixin)

Project-wide convention for HTMX views: a small mixin centralises it.

```python
class HTMXFormStatusMixin:
    """Return 422 on form_invalid for HTMX requests so clients can gate on status."""
    def form_invalid(self, form):
        if self.request.headers.get('HX-Request'):
            response = self.render_to_response(self.get_context_data(form=form))
            response.status_code = 422
            return response
        return super().form_invalid(form)
```

Pros: HTMX-side gating becomes `if (xhr.status >= 200 && xhr.status < 300)` — works as expected.
Cons: every form view needs the mixin / override; legacy views without it produce confusing client behaviour. **Requires** the paired client-side `htmx:beforeSwap` listener below.

### Option 2 — Gate on a canonical success `HX-Trigger` header (RECOMMENDED for HTMX flows)

The view emits `HX-Trigger` carrying a canonical success signal (e.g. `entityChanged`) ONLY on `form_valid`. The client checks for the header's presence:

```python
class ArticleUpdateView(UpdateView):
    def form_valid(self, form):
        article = form.save()
        response = render(self.request, 'partials/_article_detail.html', {'article': article})
        response['HX-Trigger'] = json.dumps({
            'entityChanged': {'type': 'article', 'id': article.pk, 'action': 'saved'},
        })
        return response
    # form_invalid stays default → 200 + form-with-errors, no HX-Trigger
```

```js
bodyEl.addEventListener('htmx:beforeSwap', (evt) => {
    const xhr = evt.detail && evt.detail.xhr;
    if (!xhr || xhr.status < 200 || xhr.status >= 300) return;
    const trigger = xhr.getResponseHeader('HX-Trigger') || '';
    if (trigger.indexOf('"entityChanged"') === -1) return;   // form_invalid → no signal → no close
    evt.detail.shouldSwap = false;
    closeModal();
});
```

Pros: no view-level mixin required if `entityChanged`-style events are already part of a state-refresh convention; same signal drives both the refresh walker and the modal close (single source of truth); status code stays canonical Django.
Cons: client gate is slightly more elaborate than a status-code check; only works when the project has a canonical success signal.

## Which to pick

| Project state | Fix |
|---|---|
| New project, all views HTMX-aware | Option 1 — `HTMXFormStatusMixin` at the base class |
| Existing project adding HTMX-aware modals piecemeal | Option 2 — `HX-Trigger` gate (Django defaults stay intact) |
| Mixed adoption | Option 2 — works regardless of view-side mixin coverage |

## Client side — HTMX won't swap 422 by default (pairs with Option 1)

Once the server returns `HttpResponse(body, status=422)`, HTMX's default non-2xx handling does **not** swap the body — it dispatches `htmx:responseError`. Symptom: form silently fails, console fills with `POST … 422 (Unknown Status)`, the global error toast fires, field-level errors never render.

Fix: one global `htmx:beforeSwap` listener registered at parse time alongside other htmx error globals.

```javascript
// .../static/<app>/js/htmx-error-handler.js
function onBeforeSwap(event) {
    if (!event.detail || !event.detail.xhr) return;
    if (event.detail.xhr.status !== 422) return;
    event.detail.shouldSwap = true;   // let HTMX put the form body in the target
    event.detail.isError = false;     // suppress the global error toast for 422
}
document.addEventListener('htmx:beforeSwap', onBeforeSwap);
```

Other non-2xx (4xx/5xx) still flow through the `htmx:responseError` → toast path. The listener is one-time setup; once registered, every form-fragment endpoint inherits it.

Wiring checklist for Option 1:

1. Server returns `HttpResponse(body, status=422)` on `form_invalid`.
2. Client has the global `htmx:beforeSwap` listener allowing 422 swap.
3. Form templates use `hx-target=".form-region"` + `hx-swap="outerHTML"` (or `innerHTML` per layout).

Any one missing produces silent-fail in a different way.

## Anti-patterns

- ❌ `event.detail.successful` on `htmx:afterRequest` — computed from status code; same trap, different name.
- ❌ Override every view's `form_invalid` to return JSON `{"errors": …}` — loses Django's form-rendering machinery.
- ❌ Detect form errors by parsing the response body's HTML — fragile; tied to template structure.
- ❌ Gate on response body content (empty vs non-empty) — brittle to any future success-body change.
- ❌ Per-form `hx-on::response-error="event.preventDefault(); …"` — works for one form, has to be remembered on every new form template.
- ❌ `hx-target-422="…"` via `htmx-ext-response-targets` — more configuration than the 5-line global listener covers.
- ❌ Return 200 instead of 422 to dodge client-side wiring — reintroduces the original modal-close-on-failure problem.

## Related references

- [`FORMS_INDEX.md`](../../django-frontend/references/FORMS_INDEX.md) — cross-skill form discoverability index.
- [`MODELFORM_POST_CLEAN_TRAP.md`](MODELFORM_POST_CLEAN_TRAP.md) — sibling Django form gotcha (instance mutation on `is_valid()` defeats change-detection).
- [`../../django-frontend/references/HTMX_PATTERNS.md`](../../django-frontend/references/HTMX_PATTERNS.md) § *Modal scoping* — three-gate composition on the client side; `HX-Trigger` event vocabulary that Option 2 leans on.
- [`../../django-frontend/references/FORM_RENDERING_PATTERNS.md`](../../django-frontend/references/FORM_RENDERING_PATTERNS.md) — form template rendering shapes; the templates that consume the 422 swap.
