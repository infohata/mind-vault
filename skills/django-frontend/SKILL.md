---
name: django-frontend
description: Apply Django frontend conventions — HTMX partial responses, Alpine.js state, Bulma components, HTMX modal/formset JS contracts, safe query-string generation, dynamic hx-* attribute handling, and Cotton component primitives — pairing with django backend patterns. Includes hard hazard rules every template edit must respect — multi-line `{# … #}` Django comments leak as visible content (use `{% comment %}…{% endcomment %}` for prose blocks), Django tag literals inside JS `//` comments still compile and 500 the page, and SCSS `@import url('../vendor.css')` is browser-runtime-resolved (relocate-fragile; vendor CSS belongs in a `<link>` tag).
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
- [Alpine + HTMX Gotchas](references/ALPINE_HTMX_GOTCHAS.md) — Alpine 3 factory `x-data` auto-init trap, `HX-Trigger` value-wrapping shape, defer-vs-DOMContentLoaded ordering

## When to use

**TRIGGER when:** editing templates (`*.html`) in a Django project; wiring an HTMX partial endpoint; adding a Bulma modal / form / table / widget; writing an Alpine.js component; debugging `htmx.process` or URL-encoding issues in `hx-*` attributes; converting Django messages to Bulma notifications.

**SKIP for:** backend-only work (use [django](../django/SKILL.md)); real-time collaborative editing (WebSockets + React/Vue territory); offline-first PWAs; heavy client-side data processing; mobile native apps.

## Critical hazards (read these first)

Three high-blast-radius traps that ship as user-visible regressions if you skim past them. Each has a full section below — but you need to know they exist before writing the next template line:

1. **Multi-line `{# … #}` Django comments leak as visible page content.** `{#` is single-line only; multi-line content between `{#` and `#}` is parsed as raw template content. Always use `{% comment %} … {% endcomment %}` for any prose spanning more than one line. Full section: [`### Template comment syntax — `{# inline #}` is single-line only`](#template-comment-syntax--inline-is-single-line-only). *(Compounded twice now — teisutis IDEA-124 [PR #375](https://github.com/infohata/teisutis/pull/375) shipped one to a chat input; teisutis IDEA-136 [PR #409](https://github.com/infohata/teisutis/pull/409) shipped four more in filter-form templates two hours after I authored a cotton-section cross-ref to this rule. The pattern is recurrent enough that cross-refs aren't enough — the rule needs to be in the skill's first 100 lines.)*

2. **Django tags inside JS `//` comments still compile.** `// fallback uses {% trans %}` in a `<script>` block is NOT a JS comment to Django — the `{% trans %}` parses and `'trans' takes at least one argument` 500s the entire template. Full section: [`### Sibling trap — Django tag literals inside JS // comments`](#sibling-trap--django-tag-literals-inside-js--comments).

3. **SCSS `@import url('../vendor.css')` is browser-resolved at runtime, not Sass-compile-time.** If the compiled CSS file's path moves (e.g. relocating a Django app's static folder), the relative URL 404s in the browser even though Sass compiled cleanly. Vendor stylesheets belong in a `<link>` tag in the base template, NEVER in an SCSS `@import url(...)`. Full section: [`### SCSS vendor-import hazard — @import url() is runtime, not compile-time`](#scss-vendor-import-hazard--import-url-is-runtime-not-compile-time).

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

### Cotton components for prop-shaped UI

Use **[django-cotton](https://github.com/wrabit/django-cotton)** as the component framework when an element has a clear prop shape (object + literal attrs) or multiple call sites. Coexists with `{% include %}` — opportunistic migration only, no big-bang rewrite. `{% include %}` stays fine for single-call-site scaffolding.

**File layout per app:**

```
<app>/
├── templates/
│   ├── <app>/                    # plain Django templates
│   │   └── partials/
│   │       └── _scaffolding.html  # single-call-site, fine as-is
│   └── cotton/                    # cotton components
│       └── event_row_header.html  # called as <c-event-row-header />
```

Cotton resolves `<c-foo-bar />` to `<app>/templates/cotton/foo_bar.html` in any `INSTALLED_APPS` entry. Shared primitives (drawer, toast, modal, copy-button, collapsible) live in a dedicated UI-app's `templates/cotton/`; app-specific components live in that app's `templates/cotton/`.

**Settings (one-time setup):**

```python
SHARED_APPS = [  # or INSTALLED_APPS for non-multi-tenant
    # ...
    'django_cotton.apps.SimpleAppConfig',  # NOT 'django_cotton' — avoids
    # double-config when you want explicit loaders + builtins below.
]

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        # APP_DIRS=True is mutually exclusive with explicit loaders;
        # cotton requires its loader to wrap app_directories.Loader.
        'OPTIONS': {
            'loaders': [(
                'django.template.loaders.cached.Loader',  # under DEBUG=False;
                # Django bypasses cached.Loader automatically under DEBUG=True.
                [
                    'django_cotton.cotton_loader.Loader',
                    'django.template.loaders.filesystem.Loader',
                    'django.template.loaders.app_directories.Loader',
                ],
            )],
            'builtins': [
                'django_cotton.templatetags.cotton',
                # Lets <c-…> work without per-template {% load cotton %}.
            ],
        },
    },
]
```

**Call-site syntax:**

```django
{# Old: silent on missing kwargs, no slot semantics. #}
{% include 'kb/partials/_event_row_header.html' with event=event %}

{# New: cotton, with explicit prop binding. #}
<c-event-row-header :event="event" />

{# Literal string vs Python expression — the colon prefix matters: #}
<c-button label="Save" />              {# label = "Save" (string) #}
<c-event-card :event="event" />        {# event = the Python object #}
```

**Component template — props arrive as context variables:**

```django
{# templates/cotton/event_row_header.html #}
{% load i18n %}
<div class="event-row-header">
    <span>{{ event.date|date:"DATE_FORMAT" }}</span>
    {% if event.time %}<span>{{ event.time|time:"TIME_FORMAT" }}</span>{% endif %}
</div>
```

**Render-and-assert test pattern:**

```python
# tests/test_components.py
import re
from django.template import engines
from django.test import TestCase
from django.utils.translation import activate

# Captured ONCE during the migration commit by rendering the legacy
# include against the same fixture — paste the output verbatim here.
EXPECTED_EVENT_ROW_HEADER_HTML = """
<div class="event-row-header"><span>Jun 15, 2099</span><span>09:00</span></div>
""".strip()


def _norm(html: str) -> str:
    """Whitespace-collapse so cotton's stray newlines don't break equality."""
    return re.sub(r'\s+', ' ', html).strip()


class EventRowHeaderCottonComponentTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        activate('en')

    def test_renders_match_expected(self):
        event = build_fixture_event()
        cotton_html = engines['django'].from_string(
            '<c-event-row-header :event="event" />'
        ).render({'event': event})
        self.assertEqual(_norm(cotton_html), _norm(EXPECTED_EVENT_ROW_HEADER_HTML))
```

Key points:

- `engines['django'].from_string(...)` does **not** auto-process cotton syntax in the template string (cotton's regex transform only runs inside the loader path). For inline test rendering, install cotton's `templatetags.cotton` as a template `builtins` (above) and the `<c-…>` tag is recognised by the parser. If your test still receives the literal `<c-…>` text, fall back to invoking `CottonCompiler().process(template_string)` explicitly before rendering.
- Whitespace-normalise both sides — cotton may insert/drop a newline between sibling tags relative to the legacy `{% include %}` output. Asserting on structural equality, not byte-equality, keeps the test stable.
- Pin time-sensitive fixture data to a fixed future date (e.g. `date(2099, 6, 15)`) so renders that include `is_overdue`-derived markup don't drift as wall-clock advances.

**When to write cotton vs `{% include %}`:**

| Use cotton when... | Use `{% include %}` when... |
|---|---|
| Element has a clear prop shape (object + literal attrs) | Single-call-site scaffolding (form action row, page header) |
| 2+ call sites, especially across apps | One call site, never going to be reused |
| Slot semantics matter (header / body / footer override) | Linear template inclusion |
| Test pattern needs prop isolation | Test goes through the parent view |

❌ DON'T: bulk-migrate every `{% include %}` to cotton. Migration is opportunistic — when a surface is touched for other reasons, its partials migrate. The lack of prop validation is mitigated by a doc-comment header at the top of each cotton component listing required props.

❌ DON'T: use multi-line `{# … #}` comments **inside cotton component templates**. `{#` is single-line in Django; multi-line content between `{# … #}` is parsed as raw template content, and a literal `{% include %}` word inside the prose crashes the engine. Use `{% comment %}…{% endcomment %}` for prose blocks (already noted in *Template comment syntax* below — same hazard).

❌ DON'T: import vendor CSS via `@import url(...)` from compiled SCSS. Browser resolves relative URLs against the compiled CSS file's URL at runtime — if the compiled CSS path moves (e.g. an app rename like `teisutis_core` → `teisutis_ui`), the import 404s. Link vendor CSS via a sibling `<link>` in `base.html` instead, and let SCSS only handle theme + component styles. (See *SCSS / static-asset relocation* below if added — same blast radius.)

### Alpine.js global state on `<html>`

Put long-lived UI state (theme, mobile-menu open, global flags) at the top element so any descendant can read it without prop drilling:

```django
<html x-data="{ ...themeStore(), mobileMenu: false }" x-init="init()">
```

- `themeStore()` — JS factory returning `{ theme, setTheme, init }`; defined in `static/core/js/theme.js`.
- `mobileMenu` — local primitive consumed by the navbar burger.

Pattern is load-bearing because Alpine's `x-data` scope is lexical; putting it on `<html>` makes every element a consumer. Full `base.html` in [references/BASE_TEMPLATE.md](references/BASE_TEMPLATE.md).

**Caution — list every key any descendant references.** When adding new components that read root-scope keys (e.g. a theme toggle's `<span x-show="show_text">`, a navbar's `mobileMenu`, an analytics flag), the key MUST be declared in the root `x-data` initializer. Missing keys throw `Alpine Expression Error: <key> is not defined` at runtime — not at template-compile time. Easy to ship undetected if the test surface is render-and-assert (server-side HTML) and not a real browser. Grep all consumed templates for the keys they reference before editing the root `x-data`; legacy `base.html`'s root-scope shape is the contract until a new shell template fully replaces it.

### Alpine.js script load order — beware the defer microtask trap

When `alpine.min.js` is loaded `<script defer>`, Alpine auto-starts via `queueMicrotask(() => Alpine.start())` the moment its own defer task finishes — **before** subsequent defer scripts execute. So any `Alpine.data('foo', factory)` registration or `addEventListener('alpine:init', …)` listener in a later defer script registers too late: Alpine has already walked the DOM and tried to evaluate `x-data="foo()"` against an empty registry, and the user sees `Alpine Expression Error: foo is not defined` flooding the console.

**Symptom**: console floods with `Alpine Expression Error: <factory> is not defined` for every `x-data` expression, even though the JS file is on disk and serves correctly.

**Fix**: load shell-bundle JS that registers Alpine factories or `alpine:init` listeners as **blocking** `<script>` tags (no `defer`), placed in the document `<head>`. Blocking script execution interleaves with HTML parse, so the registration runs synchronously **before** alpine's defer task is scheduled. Alpine subsequently dispatches `alpine:init`, our listeners fire, factories register, the DOM walk finds them.

```django
<head>
    {# Alpine itself is fine to defer — its IIFE runs after our blocking
       scripts have already queued their alpine:init listeners. #}
    <script src="{% static 'core/js/alpine.min.js' %}" defer></script>

    {# Theme.js is blocking because the root <html> x-data calls themeStore()
       (see "Alpine.js global state on <html>" above). Same justification
       applies to ANY shell-bundle JS that registers Alpine factories. #}
    <script src="{% static 'core/js/theme.js' %}"></script>
    <script src="{% static 'app_ui/js/nav-overflow.js' %}"></script>  {# blocking — Alpine.data #}
    <script src="{% static 'app_ui/js/drawer.js' %}"></script>        {# blocking — Alpine.data #}

    {# Anything that doesn't register Alpine factories can stay defer. #}
    <script src="{% static 'core/js/htmx.min.js' %}" defer></script>
    <script src="{% static 'core/js/utils.js' %}" defer></script>
</head>
```

The microtask-vs-defer ordering is **not platform-stable across browsers in all edge cases**, but the symptom is reliably reproducible in Chromium-family browsers when the bundle JS is defer'd after alpine. Don't rely on the order; load shell-essential factories blocking.

### Toggleable containers — `inert` not `aria-hidden`

For drawers / modals / dialogs / dropdowns / off-canvas panels that toggle visibility via CSS: bind the **`inert` HTML attribute** (boolean), not `aria-hidden`. Browser a11y validators (Chromium DevTools, axe-core) flag a focus-trap when `aria-hidden` flips to `"true"` while a descendant button retains keyboard focus — for one frame the focus sits inside an aria-hidden ancestor, which the WAI-ARIA spec forbids:

> `Blocked aria-hidden on an element because its descendant retained focus.`

**The fix**: use `inert` instead. `inert` is a boolean HTML attribute (Chrome 102+, Firefox 112+, Safari 15.5+) that:

1. Removes the entire subtree from the accessibility tree (same as `aria-hidden`).
2. **Proactively blurs any focused descendant** before applying — closes the race window.
3. Prevents pointer + focus events into the subtree.

In Alpine:

```django
{# Wrong — race-window focus-trap when isOpen flips to false #}
<aside :aria-hidden="(!isOpen).toString()">

{# Right — inert proactively blurs descendants #}
<aside :inert="!isOpen">
```

Single-attribute swap; no test fixture changes needed (tests rarely assert on `aria-hidden`). The same rule applies to modal backdrops, dropdown panels, off-canvas drawers, command palettes, lightboxes — anything whose visibility is JS-toggled and that contains focusable children.

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

### Audio playback feature-detection — `<audio>` `error` event, not `canPlayType`

`HTMLMediaElement.canPlayType(mime)` returns one of `''`, `'maybe'`, `'probably'`. With a **bare MIME** (no codec parameters — e.g. `audio/webm`, `audio/ogg`), browsers disagree on what `'maybe'` means: Safari treats `'maybe'` as "I might fail to decode this", Chrome and Firefox treat it as "I will probably play this." Pick either interpretation and you false-negative on the other set of browsers. The teisutis IDEA-124 audio-playback fallback oscillated through four bugbot cycles trying to land a `canPlayType` thresholding rule that worked everywhere; none of them did.

Replace feature-detection with **the actual decode result** via the `<audio>` element's native `error` event:

```html
<div x-data="{ failed: false }">
    <audio controls preload="metadata"
           src="{{ url }}"
           x-show="!failed"
           @error="failed = true"></audio>
    <a x-show="failed" x-cloak href="{{ url }}" download>{% trans "Download to play" %}</a>
</div>
```

The browser tries to decode; if it can't, it fires `error`; the listener flips state and the fallback link replaces the player. No browser-difference guessing, no per-MIME thresholding, no oscillation between cycles.

For JS-rendered audio attachments use the same shape with `addEventListener('error', ..., { once: true })` and replace the `<audio>` element with a fallback `<a>` in the handler. Mirror the template partial's DOM shape exactly so live-echo and refresh produce identical chips.

When NOT to use: codec-aware probes (`audio/webm; codecs="opus"`) where `canPlayType` is reliable because the codec is fully specified. The trap is bare MIMEs only.

### Alpine.js reactivity — reassign objects, don't `delete` keys

Alpine wraps `x-data` state in a Proxy. Mutations the Proxy intercepts (`obj.foo = bar`, array `push` / `splice`) trigger reactive updates; mutations it cannot intercept (`delete obj[key]`, raw `Map.delete`) silently fail to fire reactive bindings. A getter that reads `Object.keys(obj).length` will return the correct number on the next access — but `x-show` / `:disabled` bindings derived from that getter will not re-evaluate, so the UI freezes in the pre-delete state until something else triggers a render.

Symptom: a derived flag (e.g. `get transcribing() { return Object.keys(this.controllers).length > 0; }`) stays `true` forever after the last in-flight controller is removed; UI stays disabled.

Fix: rebuild and reassign the whole object instead of deleting a key:

```javascript
// ❌ delete — Proxy doesn't fire, dependent getters look stuck
delete this.controllers[id];

// ✅ reassign — Proxy fires; getters re-evaluate
const next = {};
for (const key in this.controllers) {
    if (key !== String(id)) {
        next[key] = this.controllers[key];
    }
}
this.controllers = next;
```

Same trap applies anywhere Alpine derives reactive state from object identity rather than the values themselves: `x-for` keyed by `obj`, computed getters over `Object.keys`/`Object.values`/`Object.entries`. When in doubt, treat Alpine state objects as immutable from the outside — clone and reassign rather than mutate-in-place.

### Animation loops — pause `requestAnimationFrame` on `visibilitychange`

A `requestAnimationFrame` loop fed off audio analyser data (or canvas charts, scroll effects, anything continuous) keeps doing the work even when the tab is backgrounded. Modern browsers reduce rAF tick rate on hidden tabs but do not pause arbitrary work on the listener side, and analyser nodes / WebSocket subscriptions / camera streams keep producing data. Result: drained battery on mobile, hot fans on laptops.

Wire a `visibilitychange` listener that suspends and resumes the loop in lockstep with tab visibility:

```javascript
this.rafId = window.requestAnimationFrame(renderFrame);

this._visibilityHandler = () => {
    if (document.visibilityState === 'hidden') {
        if (this.rafId) {
            window.cancelAnimationFrame(this.rafId);
            this.rafId = null;
        }
    } else if (!this.rafId && this.analyser) {
        this.rafId = window.requestAnimationFrame(renderFrame);
    }
};
document.addEventListener('visibilitychange', this._visibilityHandler);
```

On teardown remove the listener (`document.removeEventListener('visibilitychange', this._visibilityHandler)`) before disconnecting the source — orphan listeners keep references alive and prevent the audio context / analyser from being garbage-collected.

Pair with: `audioContext.close()` returning a Promise — wrap in `.catch(() => {})` because `close()` rejects when already closed (e.g. fast stop-then-stop) and an unhandled rejection from a teardown path will surface in production logs.

### Server template + JS render-helper sharing a DOM shape

When the same UI element is rendered both server-side (Django partial — first paint, history reload) and client-side (JS `renderXxx(item)` helper — live append, optimistic echo), the two render paths are a contract: any change to the partial's DOM must land in the JS helper in the same commit, and vice versa. Drift between them shows up at runtime as "the chip looks different after refresh than it did when it was just sent" — visible to users, not caught by tests unless you specifically assert DOM equality.

Concrete shape: write a one-line "mirror partner" docstring at the top of each side pointing at the other:

```django
{# Mirror partner (live-echo path):
 #     web/<app>/static/<app>/js/chat.js :: renderAudioAttachment(att)
 # Both sides share the same DOM contract — keep them in lockstep.
 #}
```

```javascript
/**
 * Mirror of templates/partials/_audio_attachment.html.
 * Same DOM shape, same Alpine bindings, same fallback behaviour.
 * Edits land here AND in the partial; tests assert both produce identical chips.
 */
function renderAudioAttachment(att) { ... }
```

Tests: render both sides with the same input and `assertEqual` on the result, OR snapshot the partial output and assert the JS helper's `outerHTML` matches. The drift-detection test is the load-bearing piece — if the contract is invisible to CI, it will rot.

When NOT to apply: one-direction-only renderers (server-only partial, or JS-only client-side helper for a feature that doesn't refresh-survive). The pattern is for the both-paths case specifically.

### Template comment syntax — `{# inline #}` is single-line only

Django has two comment syntaxes and they are not interchangeable:

| Syntax | Multi-line? | Use for |
| --- | --- | --- |
| `{# … #}` | **No** — single-line only | A short inline note on one line |
| `{% comment %} … {% endcomment %}` | Yes | Anything spanning multiple lines |

The failure mode when the wrong one is used: **content leak**. If a `{#` opens and a newline appears before the closing `#}`, Django's tokeniser fails to recognise the construct as a comment and emits the entire block as plain text into the rendered output. No template error, no test failure — just literal "comment" text shown to end users.

```django
{# This is fine — opens and closes on the same line. #}

{# THIS IS BROKEN — multi-line {# #} renders as visible
   text on the page because Django's tokeniser only matches
   {# … #} when both delimiters are on the same line. #}

{% comment %}
    This works for any number of lines. Use this whenever
    the comment doesn't fit on a single line, especially
    documentation comments above template blocks.
{% endcomment %}
```

Worked example — teisutis IDEA-124 PR #375 ([fix commit](https://github.com/infohata/teisutis/commit/c68905ab)): a multi-line `{# … #}` block documenting the audio-fallback behavior leaked its contents onto the rendered chat-input area. Visible to every user picking a voice file pre-send. Bugbot didn't catch it because the regression suite tested the partial in isolation and the comment was in chat.html itself, not the partial. Surfaced immediately on first manual browser hit on staging.

**Detection during review**: grep for `{#` followed by a newline before `#}`:

```python
import re, pathlib
for path in pathlib.Path('.').rglob('*.html'):
    text = path.read_text(errors='replace')
    for m in re.finditer(r'\{#', text):
        rest = text[m.start():]
        nl, end = rest.find('\n'), rest.find('#}')
        if end == -1 or (nl != -1 and nl < end):
            line_no = text[:m.start()].count('\n') + 1
            print(f'{path}:{line_no}: multi-line {{# #}} — convert to {{% comment %}}')
```

CI hook this as a pre-commit lint when the templates surface starts to grow.

### Sibling trap — Django tag literals inside JS `//` comments

A literal `{% tag %}` in a JS `//` comment inside a `<script>` block compiles too — Django parses every `{% ... %}` regardless of surrounding language context. A bare `{% trans %}` (no args) raises `TemplateSyntaxError: 'trans' takes at least one argument` at compile time → the whole template 500s.

```django
{# ❌ TemplateSyntaxError: 'trans' takes at least one argument #}
// fallback uses the {% trans %} tag in the template body; no JS key needed.

{# ✅ Plain prose — no literal token #}
// fallback uses the trans template tag in the template body; no JS key needed.

{# ✅ {% verbatim %} wrap when the literal token must round-trip #}
{% verbatim %}// uses {% trans %} below{% endverbatim %}
```

Plain-prose rewrite is the right answer when the comment is documentation. Reach for `{% verbatim %}` only when the comment must literally cite the tag.

Detection: extend the multi-line `{# #}` linter — bare `{% tag %}` inside `<script>` blocks is a strong signal:

```python
# Same loop as the {# #} hunt; for each match, check whether the offset
# falls inside a <script>...</script> region.
re.finditer(r'\{%\s*(trans|blocktrans|url|static)\s*%\}', text)
```

Both traps are the same family — Django's template engine treats the file as one template; the host language's comment syntax is invisible.

### SCSS vendor-import hazard — `@import url()` is runtime, not compile-time

When a Django project compiles SCSS to CSS via libsass / dart-sass / `compile_scss` and serves the result through `collectstatic`, an `@import url('../vendor/bulma.min.css')` inside the SCSS source is **NOT** resolved by Sass at compile time. Sass copies the `@import url(...)` line verbatim into the compiled `.css`; the **browser** resolves the relative URL at runtime, against the COMPILED CSS file's URL.

Failure mode: the SCSS source lives at a stable repo path (e.g. `myapp/static/myapp/scss/theme.scss`) and the vendor file sits as a sibling (`myapp/static/myapp/vendor/bulma.min.css`), so during dev with the SCSS importer everything looks fine. After `collectstatic` deploys the compiled `theme.css` somewhere else (the destination depends on the app's static config and `STATIC_ROOT`), the `../vendor/bulma.min.css` relative URL points at a different place than where collectstatic put the vendor file. **Sass compiled cleanly**; the **browser logs a 404** for `bulma.min.css`; the page renders unstyled.

The trap recurs whenever:
- a Django app is renamed (e.g. `app_core` → `app_ui`) and its compiled CSS file's `STATIC_URL` path shifts
- `STATIC_ROOT` changes between dev and prod
- `collectstatic --no-default-ignore` flags differ between environments
- a sibling app's static directory is reorganised

```scss
// ❌ DON'T — runtime-resolved against compiled CSS path; breaks on relocation.
@import url('../vendor/bulma.min.css');
// ... project styles below ...

// ✅ DO — vendor CSS goes in a <link> in base.html (or app-specific base).
//        SCSS only handles theme + component styles.
```

```django
{# base.html — vendor links FIRST so theme CSS can override defaults #}
<link rel="stylesheet" href="{% static 'myapp/vendor/bulma.min.css' %}">
<link rel="stylesheet" href="{% static 'myapp/css/theme.css' %}">
```

Why a `<link>` survives where `@import url()` doesn't: `{% static %}` resolves through Django's staticfiles finders to the correct URL for the current settings, regardless of where collectstatic happens to put the file. The HTML resolution is settings-aware; the CSS resolution is path-relative-to-compiled-output.

Compounded from teisutis IDEA-135 [PR #409](https://github.com/infohata/teisutis/pull/409) where the SCSS lived inside `teisutis_core` originally, the IDEA relocated it to `teisutis_ui` (a new shell app), and the compiled `theme.css`'s URL shifted from `/static/teisutis_core/css/theme.css` to `/static/teisutis_ui/css/theme.css`. The `@import url('../css/bulma.min.css')` line in the SCSS pointed at `../css/bulma.min.css` relative to the compiled CSS — now resolving to `/static/teisutis_ui/css/bulma.min.css`, but `bulma.min.css` was sitting at `/static/teisutis_core/css/bulma.min.css` (didn't move). Browser 404'd; UI rendered unstyled until the `<link>` migration landed.

**Detection during review**: grep SCSS source for `@import url(`:

```bash
grep -rn '@import url(' --include='*.scss' static/ web/ src/ | grep -v node_modules
```

Any hit is a candidate for migration to a `<link>` tag. The exception is when the imported file is itself part of the same compiled output (i.e. another SCSS partial bundled by Sass) — in that case it's a Sass-time `@use` / `@import` of a sibling source, not a runtime URL fetch, and the syntax is `@import 'partial';` (no `url()`, no extension). The hazard is specifically `@import url(...)`.

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
- [Alpine + HTMX Gotchas](references/ALPINE_HTMX_GOTCHAS.md) — Alpine 3 factory `x-data` auto-init trap, `HX-Trigger` value-wrapping shape, defer-vs-DOMContentLoaded ordering
- [Vendoring JS Bundles](references/VENDORING_JS_BUNDLES.md) — vendor pre-built JS to `static/vendor/`, zero Node toolchain in CI/Docker; disposable container build for ESM-only libraries (precedent: EasyMDE; planned: TipTap)
- [django](../django/SKILL.md) — backend pairing (BaseModel, DRF, ORM optimisation, permissions)
- [surgical-tdd](../surgical-tdd/SKILL.md) — testing approach for Django apps
- [`RULE_i18n-workflow`](../../rules/RULE_i18n-workflow.md) — translation hard rules
- [HTMX Documentation](https://htmx.org/docs/)
- [Alpine.js Documentation](https://alpinejs.dev/)
- [Bulma CSS Documentation](https://bulma.io/documentation/)
- [Django Crispy Forms](https://django-crispy-forms.readthedocs.io/)

**Last Updated**: 2026-05-01
