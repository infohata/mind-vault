# Shell-bound notifications — `uiNotify` is the canonical toast dispatch

When a project ships a shell-style frontend (cotton + HTMX + Alpine, with a top-right toast surface), there's exactly one allowed dispatch path for client-emitted notifications. Legacy `window.show*` helpers and direct `#messages-container` DOM writes paint full-width Bulma flash banners inside the shell — that's the regression every time.

## When to use

- Cotton/shell-style frontend with a toast surface (top-right stack, severity-driven auto-dismiss).
- Client-side JS modules that need to emit success/error/warning/info toasts.
- Migrating legacy modules into a shell — every legacy notify call site is a regression vector.

## When NOT to use

- Pre-shell project still using `_messages.html` Bulma flash + `HTMXMessagesMiddleware` — the legacy path IS the shipped path.
- Server-only flash messages — Django `messages.success(request, ...)` works; a `ToastNotifyMiddleware` (or equivalent) drains it into the toast surface via `HX-Trigger: uiNotify`.

## The canonical dispatch

```js
// ❌ Wrong — legacy full-width banner
if (typeof window.showSuccess === 'function') {
    window.showSuccess(message, { scrollToTop: false });
}

// ❌ Also wrong — local helper that does its own DOM write to #messages-container
function showNotification(message, type) {
    const container = document.getElementById('messages-container');
    const el = document.createElement('div');
    el.className = 'notification ' + cls;
    container.appendChild(el);
}

// ✅ Right — uiNotify CustomEvent dispatch; toast surface listens on window
window.dispatchEvent(new CustomEvent('uiNotify', {
    detail: {
        message: message,
        severity: severity,        // 'success' | 'info' | 'warning' | 'error'
        sticky: severity === 'error',  // errors default sticky; success auto-dismisses
    },
}));
```

The toast surface registers a `window` listener for `uiNotify` events. Server-emitted toasts arrive via `HX-Trigger: uiNotify` payload merged by the project's notify middleware (which drains Django `messages.success` / `messages.error` calls). The middleware then dispatches `uiNotify` events on the bridge entries.

**`uiNotify` is the single ingress for both client-originated AND server-originated toasts.** Any client-side path that bypasses it leaks the regression.

## Banned patterns — diagnostic recipe

When porting a widget into a shell-style surface, grep for these patterns first; every hit is a regression vector:

```bash
# Legacy show* family
grep -rEn "(window\.)?show(Success|Error|Warning|Info|Notification)\s*\(" \
    <touched-files>

# Local DOM-writing notify helpers
grep -rEn "messages-container.*append|appendChild.*notification|\.classList\.add\([\'\"]notification" \
    <touched-files>
```

Replace each call site with the `uiNotify` dispatch above. A small project-side `_emitUiNotify(message, severity, sticky)` helper that wraps the dispatch is fine — keep it adjacent to the call site, don't centralise into a misleadingly-named module.

## Server-side counterpart — don't double-dispatch

Django `messages.success(request, ...)` calls work as-is in the shell; the project's `ToastNotifyMiddleware` (or equivalent) drains them into the same `uiNotify` payload via `HX-Trigger`. **Do not** call `messages.add_message` AND set a custom `HX-Trigger: uiNotify` — the middleware's sanitiser handles the merge correctly when only one path is used.

```python
# View — Django messages
from django.contrib import messages

def article_approve(request, pk):
    article = get_object_or_404(Article, pk=pk)
    article.approved_by = request.user
    article.save()
    messages.success(request, _('Article approved.'))
    response = render(request, '_article_detail_body.html', {'article': article})
    response['HX-Trigger'] = 'articleApproved'  # for client-side post-action hook (see below)
    return response
```

## `HX-Trigger` event-name pattern for `outerHTML`-swap targets

When a cotton component's action button uses `hx-post` + `hx-target="closest .container"` + `hx-swap="outerHTML"`, **never** rely on `htmx:afterRequest` at document level for post-success client-side actions.

The trigger button is a child of the swap target — by the time `htmx:afterRequest` fires (after swap), the trigger is detached from DOM, the event can't bubble to document, and the listener never runs.

The fix: emit `HX-Trigger: <eventName>` from the view; bind the post-action listener on `body` (which survives the swap and always receives the event):

```python
# View
response['HX-Trigger'] = 'articleApproved'
```

```js
// Post-action listener — bound on body, survives outerHTML swap
document.body.addEventListener('articleApproved', (event) => {
    // re-fetch list, dispatch uiNotify, etc.
    window.dispatchEvent(new CustomEvent('uiNotify', {
        detail: { message: 'Article approved.', severity: 'success' },
    }));
});
```

The pattern is reusable for any `outerHTML`-swap target containing the trigger element. The event name should be specific enough to not collide (e.g. `articleApproved` not `approved`).

## Cross-cohort impact

This rule applies across every surface migration in a multi-IDEA shell-frontend cohort — every list/detail surface (article / event / FAQ / dashboard / chat / admin surfaces) will hit the same regression unless the rule is part of the migration checklist from the start. Cheaper to enforce as a self-sweep step than to surface as review-loop finding cycles.

## Pick ONE source per flow — server `messages.*` OR client `HX-Trigger` handler, never both

Once a project ships both server-emitted toasts (Django `messages.*` → notify middleware → `HX-Trigger: uiNotify`) and client-side `HX-Trigger` listeners that ALSO call `uiNotify`, double-toast bugs become routine. The user sees the same toast twice — once from the server's middleware-dispatched event, once from the client's named-event listener that fires on the same response.

The fix is at the design level: each flow's toast emits from exactly one source.

| Flow shape | Toast source | Why |
|---|---|---|
| Normal form submit → Django view → render | Server `messages.success(request, ...)` drained by middleware | The cleanest path; `HX-Trigger` carries data-events only, not toast text |
| HTMX action with `hx-swap="none"` | Server `HX-Trigger` header → JS handler dispatches `uiNotify` | No view-rendered context for a `messages.success` to land in |
| Server flash + client post-action work | Server `messages.success` for the toast; JS handler uses `refreshOnly: true` (does refresh work, no toast) | Avoids the double-fire when both layers want to know "save succeeded" |
| Pure client-side action (no server roundtrip) | JS dispatches `uiNotify` directly | No server involvement; nothing else to coordinate with |

The `refreshOnly: true` convention is what makes the third row work. Pattern:

```js
// JS handler for entitySaved — does the refresh, does NOT emit a toast
document.body.addEventListener('articleSaved', (event) => {
    const detail = _unwrapHtmxDetail(event.detail);
    if (detail && detail.refreshOnly) {
        _refreshList();
        return;     // toast was already emitted by messages.success → middleware → uiNotify
    }
    // Otherwise: this fired from a flow with no server messages.success
    // and we DO need to emit the toast.
    _refreshList();
    _emitUiNotify('Article saved.', 'success');
});
```

Server-side: when a view emits both `messages.success` AND an `HX-Trigger`, the trigger payload sets `refreshOnly: true`:

```python
response = render(request, '...', context)
messages.success(request, _('Article saved.'))
response['HX-Trigger'] = json.dumps({'articleSaved': {'refreshOnly': True}})
return response
```

The `refreshOnly` flag is the signal to the JS handler: "do your data-side work, skip the toast, the server already arranged for the toast via messages.success". Inverse for HTMX-trigger-only flows: the JS handler emits the toast because there's no `messages.success` path.

## Reference

Pairs with [`COTTON.md`](COTTON.md) for cotton component conventions and [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) for HTMX `HX-Trigger` value-wrapping shape. [`HTMX_PATTERNS.md`](HTMX_PATTERNS.md) § *Modal scoping* covers the three-gate listener that distinguishes form_valid from form_invalid responses.

**Last Updated**: 2026-05-14
