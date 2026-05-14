# Django `form_invalid` returns 200, not 422 — status alone is insufficient for HTMX flows

## The gotcha

Django's `FormView` / `CreateView` / `UpdateView` default `form_invalid()` returns a response with status **200** and a re-rendered form-with-errors. The base class implementation is:

```python
def form_invalid(self, form):
    return self.render_to_response(self.get_context_data(form=form))
```

That's `render_to_response`, which defaults to `HttpResponse(status=200)`. There's no 4xx / 422 status surface for validation failure.

HTMX clients that gate on response status (e.g. "close the modal on 2xx") interpret this as success and act accordingly — closing modals that should stay open, refreshing lists that haven't been mutated, dispatching success toasts on rejected submissions.

## When this bites

- Modal flows that auto-close on successful save: a 2xx-only gate closes the modal on validation failure, the user loses their typed input.
- HTMX listeners that key on `htmx:afterRequest` + `event.detail.successful` (`successful = xhr.status >= 200 && xhr.status < 300`): the listener fires its success path on a validation failure.
- Walker/refresh modules that re-fetch lists on 2xx: they trigger spurious refreshes on rejected forms.

## Fix options

### Option 1 — Override `form_invalid` to return 422

Project-wide convention for HTMX views: explicitly set status 422 on validation failure.

```python
# views.py
from django.views.generic import UpdateView
from django.http import HttpResponse

class ArticleUpdateView(UpdateView):
    model = Article
    form_class = ArticleForm

    def form_invalid(self, form):
        if self.request.headers.get('HX-Request'):
            response = self.render_to_response(self.get_context_data(form=form))
            response.status_code = 422
            return response
        return super().form_invalid(form)
```

A small mixin centralises it:

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

Pros: HTMX-side gating becomes `if (xhr.status >= 200 && xhr.status < 300)` — works exactly as expected.

Cons: every form view needs the mixin / override; legacy views that don't have it produce confusing client behaviour.

### Option 2 — Gate on response body content (empty = success, non-empty = form-with-errors)

Some flows return an empty 200 on success (no body content to swap in) and a form-with-errors body on invalid. The client can distinguish by checking whether the response body is empty.

Brittle: any future redirect, success toast, or canonical-response-body change at the view layer breaks the client gate.

### Option 3 — Gate on a canonical success `HX-Trigger` header (RECOMMENDED for HTMX flows)

The view emits an `HX-Trigger` header containing a canonical success signal (e.g. `entityChanged`) ONLY on `form_valid`. The client checks for the header's presence:

```python
# views.py
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
// client-side modal close listener
bodyEl.addEventListener('htmx:beforeSwap', (evt) => {
    const xhr = evt.detail && evt.detail.xhr;
    if (!xhr) return;
    if (xhr.status < 200 || xhr.status >= 300) return;   // hard errors

    const trigger = xhr.getResponseHeader('HX-Trigger') || '';
    if (trigger.indexOf('"entityChanged"') === -1) return;   // form_invalid → no canonical signal → no close

    evt.detail.shouldSwap = false;
    closeModal();
});
```

Pros:
- No view-level mixin required if you're already emitting `entityChanged`-style events as part of a state-refresh convention.
- The same signal that drives the refresh walker also gates the modal close — single source of truth.
- Status code stays canonical Django (200 + form-with-errors on invalid). No semantic divergence from Django defaults.

Cons:
- Client gate is slightly more elaborate than a status-code check.
- Only works when the project has a canonical success signal in `HX-Trigger`.

## When to pick which

| Project state | Recommended fix |
|---|---|
| New project, all views HTMX-aware | Option 1 — `HTMXFormStatusMixin` at the base class level |
| Existing project adding HTMX-aware modals piecemeal | Option 3 — gate on `HX-Trigger` header (Django defaults stay intact) |
| Mixed project; some views adopted Option 1, some haven't | Option 3 — works regardless of view-side adoption |

## Anti-patterns

- ❌ **"Just check `event.detail.successful` on `htmx:afterRequest`"**. `successful` is computed from status code — same trap, different name.
- ❌ **Override every view's `form_invalid` to return JSON `{"errors": ...}`**. Loses Django's form-rendering machinery; you'd be re-implementing it on the client.
- ❌ **Detect form errors by parsing the response body's HTML**. Fragile; tied to template structure; breaks on every template refactor.

## Surfaced

teisutis IDEA-163 PR #443 cycles 3-5 — first fix gated modal close on `htmx:beforeSwap` + `xhr.status` 2xx. User manual eval revealed validation failure closed the modal because Django returned 200 + form-with-errors. Added `HX-Trigger: entityChanged` header check as third gate; modal stays open on form_invalid.

See [`../../django-frontend/references/HTMX_PATTERNS.md`](../../django-frontend/references/HTMX_PATTERNS.md) § *Modal scoping* for the three-gate composition on the client side.

**Last Updated**: 2026-05-14
