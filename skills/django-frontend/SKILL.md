---
name: django-frontend
description: Apply Django frontend conventions — HTMX partial responses, Alpine.js state, Bulma components, HTMX modal/formset JS contracts, safe query-string generation, and dynamic hx-* attribute handling — pairing with django backend patterns.
license: MIT
metadata:
  author: mind-vault
  version: '2.0'
---

# django-frontend

Production frontend patterns for Django using **HTMX** for server-driven partial swaps, **Alpine.js** for local client state, **Bulma** for styling, and **Django Crispy Forms** for server-rendered form markup. Philosophy: server renders HTML, HTMX swaps fragments, Alpine holds UI state, Bulma provides components — progressive enhancement, minimal JavaScript.

**Pairs with:** [django](../django/SKILL.md) for backend conventions. Load both on full-stack HTMX features (e.g. a view returning `kb/partials/_article_list.html` on `HX-Request` and the full page otherwise).

**Stack:**

| Tool                | Version                             | Role                                   |
| ------------------- | ----------------------------------- | -------------------------------------- |
| HTMX                | 1.9+ (most 2.x patterns compatible) | Server-driven AJAX, partial swaps      |
| Alpine.js           | 3.x                                 | Lightweight reactive components        |
| Bulma CSS           | 0.9+                                | CSS-only component framework           |
| Django Crispy Forms | 2.x+                                | Server-side form rendering             |
| FontAwesome         | 6.x                                 | Icons via `{% fa_icon %}` template tag |

Compatibility: Django 4.2+ (tested through 5.2 LTS), any database.

**Optional extensions** (load on demand):

- [Base Template + Theme](references/BASE_TEMPLATE.md) — full `base.html`, Alpine theme store, SCSS build pipeline
- [Modal System](references/MODAL_SYSTEM.md) — `openModal` / `closeModal` / `confirmAction` implementation
- [HTMX Widgets](references/HTMX_WIDGETS.md) — autocomplete, file upload, colour/icon pickers
- [Advanced Components](references/ADVANCED_COMPONENTS.md) — theme store, notifications, utilities
- [HTMX Patterns](references/HTMX_PATTERNS.md) — detailed HTMX implementation patterns

## When to use

**TRIGGER when:** editing templates (`*.html`) in a Django project; wiring an HTMX partial endpoint; adding a Bulma modal / form / table / widget; writing an Alpine.js component; debugging `htmx.process` or URL-encoding issues in `hx-*` attributes; converting Django messages to Bulma notifications.

**SKIP for:** backend-only work (use [django](../django/SKILL.md)); real-time collaborative editing (WebSockets + React/Vue territory); offline-first PWAs; heavy client-side data processing; mobile native apps.

## Pattern

### Partial-vs-full template dispatch

The foundational pattern: one view URL returns either the full page (normal navigation) or just the changed fragment (HTMX swap), dispatched on the `HX-Request` header.

**Backend — `HTMXMixin`:**

```python
# core/mixins.py
class HTMXMixin:
    """Select a partial template when the request is an HTMX swap."""
    def get_template_names(self):
        if self.request.headers.get("HX-Request"):
            ml = self.model._meta
            return [f"{ml.app_label}/partials/_{ml.model_name}_list.html"]
        return super().get_template_names()
```

**View:**

```python
class ArticleListView(HTMXMixin, ListView):
    model = Article
    template_name = "kb/article_list.html"
    # partial fallback: kb/partials/_article_list.html
```

**Full-page template** contains a swap target that the partial replaces:

```django
<div id="article-list">
    {% include "kb/partials/_article_list.html" %}
</div>

<form hx-get="{% url 'kb:article_list' %}"
      hx-target="#article-list"
      hx-swap="innerHTML">
    <!-- filter inputs -->
</form>
```

HTMX requests to the same URL return only the partial; HTMX swaps it into `#article-list`; the page doesn't navigate.

✅ DO: One URL, two templates, dispatched on `HX-Request`.
❌ DON'T: Separate `/articles/` and `/articles/partial/` endpoints — duplicates the queryset and permission logic.

### Alpine.js global state on `<html>`

Put long-lived UI state (theme, mobile-menu open, global flags) at the top element so any descendant can read it without prop drilling:

```django
<html x-data="{ ...themeStore(), mobileMenu: false }" x-init="init()">
```

- `themeStore()` — JS factory returning `{ theme, setTheme, init }`; defined in `static/core/js/theme.js`.
- `mobileMenu` — local primitive consumed by the navbar burger.

Pattern is load-bearing because Alpine's `x-data` scope is lexical; putting it on `<html>` makes every element a consumer. Full `base.html` in [references/BASE_TEMPLATE.md](references/BASE_TEMPLATE.md).

### Modal management with HTMX

Modals load content from an HTMX endpoint — opening a modal is an HTMX GET against a form URL, the response swaps into the modal body.

**API:**

```javascript
openModal(url, title, modalId = "formModal");  // load + show
closeModal(modalId);                              // hide (or all if omitted)
confirmAction(url, { title, message, confirmText, confirmClass, onSuccess });
```

**Critical gotcha — `htmx.process()` after attribute mutation:** HTMX binds listeners at initial load and does not observe `setAttribute` changes. After dynamically setting `hx-post` (e.g. in `confirmAction`), re-bind:

```javascript
form.setAttribute("hx-post", url);
if (typeof htmx !== "undefined") htmx.process(form);
```

Full `openModal` / `closeModal` / `confirmAction` implementation, lifecycle events (`itemCreated`, `itemUpdated`, Escape-to-close), widget re-init after swap, and loading-location rule in [references/MODAL_SYSTEM.md](references/MODAL_SYSTEM.md).

**Loading location:** `modal.js` goes in `base.html` globally, not per-page `{% block extra_head %}`. Pages that include the modal partial but forget the script get `confirmAction is not defined` runtime errors.

### Safe URL query-string generation

**Never build query strings by hand in templates** — raw `&` in `href`/`hx-get` breaks HTML entity parsing (`&copy=1` renders as `©=1`), and unencoded spaces corrupt the URL.

Use a `{% query_string %}` template tag wrapping `urllib.parse.urlencode()`:

```python
# core/templatetags/core_tags.py
from urllib.parse import urlencode
from django import template

register = template.Library()

@register.simple_tag
def query_string(**kwargs):
    return "?" + urlencode({k: v for k, v in kwargs.items() if v is not None})
```

```django
{# ❌ WRONG: manual concat, HTML-entity landmines #}
<a href="?property={{ property.id }}&copy_context_from={{ conv.id }}">

{# ✅ CORRECT #}
{% load core_tags %}
<a href="{% query_string property=property.id copy_context_from=conv.id %}">
```

Same rule for HTMX attributes — the URL you hand to `hx-get` / `hx-post` must be pre-encoded:

```django
<div hx-get="{% query_string search=query copy_mode='true' %}">
```

✅ DO: Route every dynamic URL through `{% query_string %}`, `href` and `hx-*` alike.
❌ DON'T: Concatenate `&` params in templates.

### HTMX dynamic attributes need `htmx.process()`

HTMX binds listeners at initial page load. **Changing `hx-*` attributes via `setAttribute()` does NOT rebind** — the form submits to the wrong URL (usually the current page), yielding 405 Method Not Allowed.

```javascript
form.setAttribute("hx-post", newUrl);
if (typeof htmx !== "undefined") htmx.process(form);   // required
```

Applies to `hx-get`, `hx-post`, `hx-target`, `hx-swap`, `hx-trigger` — any attribute HTMX reads at bind time.

### HTMX headers: quote hyphenated keys in JSON

When building header objects for HTMX (CSRF, custom `HX-*` headers), quote hyphenated names — otherwise JavaScript parses `X-CSRFToken` as `X − CSRFToken`, a SyntaxError at literal-parse time:

```javascript
// ❌ SyntaxError
JSON.stringify({ X-CSRFToken: value })

// ✅
JSON.stringify({ "X-CSRFToken": value })
```

### Global single-submit locking

Prevent double-submits and rapid multi-clicks without sprinkling `onsubmit` JS across every form. Global listener + `.sync-submit-button` class + `data-sync-submit` attribute:

- On submit: disable the button, inject a spinner/"in-flight" label.
- On `htmx:sendError` or `htmx:responseError`: reset to active.
- On `htmx:afterRequest` success: reset to active (or keep disabled with a "done" state, depending on flow).

Details in [references/HTMX_PATTERNS.md](references/HTMX_PATTERNS.md).

### Sticky-navbar aware error scrolling

`element.scrollIntoView()` hides the target under fixed/sticky navbars. Compute the offset explicitly:

```javascript
const y = errorSummary.getBoundingClientRect().top + window.scrollY - navbarHeight;
window.scrollTo({ top: y, behavior: "smooth" });
```

### Formset tables — shared partial + JS contract

For modelformsets (reminders, profile defaults, row-based editors), reuse a single partial + JS module across all formsets by fixing a contract:

**Template contract** (backend renders):

- Management form (`TOTAL_FORMS`, `INITIAL_FORMS`, `MIN/MAX_NUM_FORMS`).
- `<tbody id="…">` — row container.
- `<template id="…">` — one empty row using Django's `__prefix__` in name/id attributes.
- A single CSS class on each data row (e.g. `reminder-row`) for the script to target.

**JS contract:**

- **Add row:** clone the template, replace `__prefix__` with current index, append to `<tbody>`, increment `TOTAL_FORMS`.
- **Delete new row (no pk):** remove from DOM, reindex names/ids to `0..n-1`.
- **Delete existing row (has pk):** leave in DOM, tick hidden `DELETE` checkbox; Django removes on submit.

**Backend wiring:** the view passes `empty_form_template_id`, `add_button_id`, `table_body_id`, `row_partial`, `row_css_class` into the shared partial. Same contract = same JS across every formset.

### Date / time / duration responsive row

When a form shows **date**, **time**, and **duration** together, use a single Crispy `Div` with Bulma `columns` + responsive classes so the three inline on desktop and stack on mobile:

```python
Div(
    Column("event_date", css_class="column is-2-widescreen is-full-mobile"),
    Column("event_time", css_class="column is-2-widescreen is-full-mobile"),
    Column("duration",   css_class="column is-2-widescreen is-full-mobile"),
    css_class="columns",
)
```

They belong together semantically; resist the reflex to put each on a full-width row.

### Save-then-attach lifecycle

For entities requiring attachments (files, images, references) alongside scalar fields, **don't process attachments during `CreateView`**:

- **Create mode:** hide attachment dropzones, show an info notice ("Save this record first to attach files").
- **Edit mode:** render the attachment manager.

Prevents orphaned uploads on failed submits, simplifies multipart edge cases, and avoids cross-FK race conditions.

### Server-computed date context

Individual views computing `datetime.now()` drift across server timezone, user timezone, and browser `new Date()`. Register a global context processor (convention: `today_iso`) that resolves the current date in the user's timezone, and expose it to client-side JS:

```django
<script id="today_iso" type="application/json">{{ today_iso|escapejs }}</script>
```

Then JS reads a deterministic server-computed date instead of asking the browser. Avoids validation bugs where client and server disagree on "today".

### Vanilla-JS deprecation hazard

This stack uses vanilla JS — no TypeScript compilation, no ESLint pipeline enforcing no-dead-imports. **Removing a function definition doesn't fail the build if something still calls it**; the error surfaces at runtime as `ReferenceError`.

Before deleting an "orphan" JS function, grep callers across `static/`:

```bash
rg "functionName\(" static/
```

Remove callers before removers. Silent function deletes are a common AI-refactor regression.

## Bulma template standards

Compact reference for consistency across projects. Full discussion in [references/ADVANCED_COMPONENTS.md](references/ADVANCED_COMPONENTS.md).

### Buttons

| Role                                  | Class                        |
| ------------------------------------- | ---------------------------- |
| Primary action (Save, Create, Submit) | `button is-primary`          |
| Secondary action (View, Manage)       | `button is-info`             |
| Cancel / Back                         | `button is-light`            |
| Danger / Delete                       | `button is-danger`           |
| Row-level edit in a table             | `button is-small is-primary` |
| Ellipsis / menu trigger               | `button is-ghost is-small`   |

Never use `is-outlined` or `is-text`. Cancel/back uses `is-light`.

### Icon + label composition

```django
<button class="button is-primary">
    <span class="icon">{% fa_icon "save" %}</span>
    <span>{% trans "Save" %}</span>
</button>
```

Icons always via `{% fa_icon "name" %}`. Exceptions: dynamic Alpine `:class` bindings, brand icons (`fab`), dynamically-computed `{{ trigger_icon }}` in navbar submenus.

### Cards

Use `card-content`, never `card-body` (Bootstrap leak):

```html
<div class="card">
    <div class="card-header"><div class="card-header-title">Title</div></div>
    <div class="card-content">…</div>
</div>
```

### Tables

- Wrap in `table-scroll-container`, not `table-responsive`.
- Classes: `table is-fullwidth is-hoverable is-striped`.
- Always `scope="col"` on `<th>`.

### Status tags

Bulma `tag`, never Bootstrap `badge`:

```html
<span class="tag is-success">Active</span>
<span class="tag is-warning">Pending</span>
<span class="tag is-danger">Cancelled</span>
```

### Notifications

Always include `is-light` for dark-theme compatibility:

```html
<div class="notification is-success is-light">…</div>
```

### Empty states

- Full: `has-text-centered py-6` block with icon, heading, subtitle, action button.
- Text-only: `<p class="has-text-grey">{% trans "No items found." %}</p>`.
- Never `text-muted` (Bootstrap leak) — use `has-text-grey`.

### i18n

All user-visible text in `{% trans %}` / `{% blocktrans %}`. Template tag arguments (modal titles passed via `with`, button labels from includes) must also be translated.

## When NOT to use these patterns

- **SPA-scale interactivity** — real-time collaborative editing, complex client-side state graphs, rich offline capability. Use a proper client framework (React, Vue, Svelte) + API backend.
- **Mobile native** — native iOS/Android or React Native are different stacks entirely.
- **Public marketing site with no interactive state** — a static site generator (Hugo, Eleventy, Astro) is simpler and faster.
- **Content-heavy editorial site** — CMS-first tooling (Wagtail, Netlify CMS) wins on content modelling.

## References

- [Base Template + Theme](references/BASE_TEMPLATE.md)
- [Modal System](references/MODAL_SYSTEM.md)
- [HTMX Widgets](references/HTMX_WIDGETS.md) — autocomplete, file upload, colour/icon pickers
- [Advanced Components](references/ADVANCED_COMPONENTS.md) — theme store, notifications, utilities
- [HTMX Patterns](references/HTMX_PATTERNS.md) — detailed HTMX implementation patterns
- [django](../django/SKILL.md) — backend pairing (BaseModel, DRF, ORM optimisation, permissions)
- [surgical-tdd](../surgical-tdd/SKILL.md) — testing approach for Django apps
- [`RULE_i18n-workflow`](../../rules/RULE_i18n-workflow.md) — translation hard rules
- [HTMX Documentation](https://htmx.org/docs/)
- [Alpine.js Documentation](https://alpinejs.dev/)
- [Bulma CSS Documentation](https://bulma.io/documentation/)
- [Django Crispy Forms](https://django-crispy-forms.readthedocs.io/)

**Last Updated**: 2026-04-17
**Version**: 2.0
