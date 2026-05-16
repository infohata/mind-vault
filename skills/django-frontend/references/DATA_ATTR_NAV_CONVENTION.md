# Data-attribute markers + JS click handler — vs raw `hx-*` on nav links

**When this fires**: a Django + HTMX project ships top-level nav (`<a>` tags for `/articles/`, `/events/`, `/dashboard/`, etc.) that should swap a region of the page instead of full-loading. The obvious shape — put `hx-get`, `hx-target`, `hx-swap`, `hx-push-url` directly on each `<a>` — appears to work but has structural problems that surface only after the application grows.

The cleaner shape is to put **only a data-attribute marker** on the link (`<a data-shell-nav-link href="/events/">…</a>`) and have a **single document-level JS click handler** translate that marker into an `htmx.ajax(…)` call. The URL update becomes a deliberate `history.pushState` step in the handler, not a side-effect of the swap.

## The shape

### Anti-pattern — `hx-*` on the link itself

```html
<a href="/events/"
   hx-get="/events/"
   hx-target="#shell-swap-target"
   hx-swap="outerHTML"
   hx-push-url="true"
   hx-headers='{"HX-Shell-Fragment": "1"}'>
   Events
</a>
```

What's wrong:

1. **URL update is tied to swap success.** `hx-push-url="true"` makes HTMX push the URL only when the swap completes. If the swap fails (5xx, network error, timeout), the URL bar stays at the old path. That's the *good* failure mode. The *bad* failure mode is harder to reach: when the swap completes against the wrong target (selector resolved to `<body>` because `#shell-swap-target` was missing in the DOM), the URL advances anyway and the user is left with a URL that doesn't match what they're seeing.
2. **The link is a polymorphic surface.** A future feature wants the same link to ALSO dispatch a Custom Event (e.g. "user navigated to Events"). With `hx-*` on the link, you stack `hx-on::after-request="…"` next to `hx-get`, which executes in a JS scope that's NOT Alpine's evaluator (see [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) #4). The hx-on dispatch can't read `$store`. The next feature is more friction than the first.
3. **Per-template repetition.** Every nav cotton that emits a link repeats the same `hx-*` block, with one or two attributes diverging per usage. The divergence creates the "did I forget to set `hx-push-url` here?" maintenance burden.
4. **Cannot share the click-decision logic across surfaces.** When the same nav-click needs slightly different behaviour on mobile vs desktop (e.g. mobile should also dismiss an open drawer pane before the swap, desktop preserves it), the `hx-*` declarative path can't gate on `matchMedia`. You'd have to fork the cotton per breakpoint.

### Convention — data-attribute marker + JS handler

The cotton emits just the marker:

```html
<a data-shell-nav-link
   data-nav-slug="events"
   href="/events/">
   Events
</a>
```

The handler is one IIFE in a shell-level JS module:

```javascript
document.addEventListener('click', function (e) {
    var link = e.target && e.target.closest
        ? e.target.closest('a[data-shell-nav-link]')
        : null;
    if (!link) return;
    // Defence: never both markers on the same link (disjoint vocabulary).
    if (link.hasAttribute('data-other-vocabulary-link')) return;
    // Honour open-in-new-tab / modifier-key behaviour.
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (e.button !== 0) return;
    var url = link.getAttribute('href');
    if (!url) return;
    if (!window.htmx || typeof window.htmx.ajax !== 'function') return;
    e.preventDefault();
    // Stash the intended URL commit; the htmx:afterSwap listener applies
    // pushState once the swap actually lands. See HTMX_DEFERRED_PUSHSTATE
    // for the rationale (and see ALPINE_HTMX_GOTCHAS gotcha 3 for the
    // head-loaded-IIFE caveat about subscribing on `document`, not
    // `document.body`).
    var intendedPath = new URL(url, window.location.href).pathname;
    _pendingShellNavCommit = {intendedPath: intendedPath, url: url};
    window.htmx.ajax('GET', url, {
        target: '#shell-swap-target',
        swap: 'outerHTML',
        headers: {'HX-Shell-Fragment': '1'},
    });
});

document.addEventListener('htmx:afterSwap', function (evt) {
    if (!_pendingShellNavCommit) return;
    if (!evt.detail || !evt.detail.target) return;
    if (evt.detail.target.id !== 'shell-swap-target') return;
    var commit = _pendingShellNavCommit;
    _pendingShellNavCommit = null;
    try {
        window.history.pushState({shellNavUrl: commit.url}, '', commit.url);
    } catch (_) { /* cross-origin / sandboxed contexts — bail silently */ }
});
```

## Why this wins

### 1. URL update is a deliberate step, not a swap side-effect

The handler can implement any URL policy (push, replace, no-change) independently of the swap result. Failure modes are explicit — if the swap fails, the handler still has the original URL in the `_pendingShellNavCommit` slot but the `afterSwap` consumer never fires, so the URL bar stays where it was. The contract is observable in one place.

### 2. The click decision is composable

Mobile-specific behaviour gates trivially:

```javascript
// Mobile-only drawer dismiss before the swap.
if (window.matchMedia('(max-width: 768px)').matches
    && window.uiPreviewSurface
    && typeof window.uiPreviewSurface.closeForShellNav === 'function') {
    window.uiPreviewSurface.closeForShellNav();
}
```

No template fork. The marker stays the same; the handler branches.

### 3. Disjoint vocabularies enforceable in tests

Once you have two marker families (e.g. `data-shell-nav-link` for region swaps and `data-preview-link` for preview-drawer opens), a structural test asserts that no `<a>` carries both markers. The handler's first line also bails if the wrong marker is present, providing defence-in-depth.

```python
def test_click_handler_bails_on_other_marker_co_presence(self):
    """Disjoint-vocabulary invariant — markers never co-occur on one element."""
    src = (Path(__file__).resolve().parent.parent / 'static' / 'shell-nav.js').read_text()
    self.assertIn('link.hasAttribute(\'data-preview-link\')', src)
```

### 4. Three nav cottons share one snippet

The marker, href, and any data-* slugs go in a shared include:

```django
{# cotton/_shell_nav_link_attrs.html #}
href="{{ item.url }}"{% if item.shell_migrated %} data-shell-nav-link{% endif %} data-nav-slug="{{ item.slug }}"
```

Every nav cotton (top-bar, mobile-bottom-tab, more-sheet) includes the same snippet:

```django
<a {% include "cotton/_shell_nav_link_attrs.html" %}
   class="nav-item">…</a>
```

When the convention evolves (new attribute, renamed slug field), one edit fans out everywhere.

### 5. Discriminator header avoids `HX-Request` overload

The handler sets `HX-Shell-Fragment: 1` (or your project's chosen discriminator name) so the server-side view can distinguish this nav-click swap from other HTMX request types (load-more pagination, inline form submission, etc.). All of those would carry `HX-Request: true`; the discriminator separates them cleanly:

```python
def event_list_view(request):
    if request.headers.get('HX-Shell-Fragment') == '1':
        return render(request, 'events/_shell_swap_target.html', ctx)
    if request.headers.get('HX-Request') == 'true':
        return render(request, 'events/_load_more_fragment.html', ctx)
    return render(request, 'events/list.html', ctx)
```

## Trade-offs

### What you give up

- **JS-disabled fallback** is now the link's plain `href` navigation (full page load to `/events/`). HTMX's hx-* on the link did the same thing on JS-disabled, so net-zero — but the handler convention makes it more explicit.
- **One small JS module** to maintain (~50 LoC including the popstate listener and the bfcache `pageshow` recovery).
- **One marker attribute** per link instead of one declarative attribute family. Both are 1-2 extra attributes per `<a>` in practice.

### What you avoid

- All four problems listed in the anti-pattern section.
- The `hx-on::*` Alpine-scope mismatch that surfaces when you later want the link to do MORE than just swap (see [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) #4).
- The polymorphism trap when mobile vs desktop want different behaviour for the same nav-click.
- The deferred-pushState race (see § *Why this wins* point 1) — built into the convention.

## When NOT to use this convention

- Single-page app where every link is a region swap and there's exactly one swap target with no breakpoint variation. The hx-* declarative path is fine when the swap-decision logic is trivial.
- Static link to a different site / external URL — those should be plain `<a href>` with no JS handler.
- An admin / debug surface where consistency with the rest of the application isn't a goal.

## Related references

- [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) — gotchas 1 / 3 / 4 / 10 all touch the handler-vs-attribute design surface from different angles.
- [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md) — the other marker family (`data-preview-link`) referenced as the disjoint-vocabulary sibling.
- [`HTMX_PATTERNS.md`](HTMX_PATTERNS.md) — `HX-Shell-Fragment`-style discriminator headers in the broader HTMX response-routing context.

---

**Last Updated**: 2026-05-16
