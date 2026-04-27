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

The same root cause (Django's template engine doesn't know about JavaScript comment syntax) bites a *different* symptom when a JS comment in an inline `<script>` block contains a literal Django tag:

```django
<script>
    var keys = {
        // IDEA-XXX — fallback link uses the {% trans %} template tag below;
        // no JS-side translation key is needed for it.
        downloadLabel: "{% trans 'Download'|escapejs %}",
        // ...
    };
</script>
```

Django parses every `{% ... %}` everywhere in the file, regardless of surrounding language context. The `{% trans %}` inside the JS comment becomes an empty (zero-argument) `trans` tag, raising `TemplateSyntaxError: 'trans' takes at least one argument` at template-compile time. The whole template 500s — the comment isn't even rendered.

```django
{# ❌ Surfaces in the browser as "TemplateSyntaxError: 'trans' takes at least one argument" #}
// IDEA-XXX — uses the {% trans %} tag in the template body; no JS key needed.

{# ✅ Plain prose — no literal token #}
// IDEA-XXX — uses the trans template tag in the template body; no JS key needed.

{# ✅ Wrap in {% verbatim %} #}
{% verbatim %}// IDEA-XXX — uses the {% trans %} tag in the template body{% endverbatim %}
```

Worked example — teisutis 2026-04-27 staging-tree test loop hit this trap **twice** in the same session: PR #375 line 449 ([fix commit `a3b6f074`](https://github.com/infohata/teisutis/commit/a3b6f074)) and PR #376 line 441 (rolled into the blob-direct pivot commit `002ccd98`). Both occurrences were JS comments documenting that a particular UI string used a `{% trans %}` tag in the template body rather than a JS-side translation key — the comment author cited the tag literally. Both cases, the chat URL 500'd until the literal token was rewritten in plain prose.

Detection: extend the multi-line `{# #}` linter above with a second check — bare `{% tag %}` (no args) inside `<script>` blocks is a strong signal:

```python
# Same loop as the {# #} hunt; add:
if re.search(r'<script[^>]*>(.*?)</script>', text, re.DOTALL):
    for m in re.finditer(r'\{%\s*(trans|blocktrans|url|static)\s*%\}', text):
        # check that we're inside a <script> block at this offset
        ...
```

CI-hook the same way: pre-commit lint when the templates surface grows. The two traps (`{# #}` multi-line + Django tag literals in JS comments) are the same family — Django's template engine treats the file as one big template, the JS comment syntax is invisible to it.

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
- [Vendoring JS Bundles](references/VENDORING_JS_BUNDLES.md) — vendor pre-built JS to `static/vendor/`, zero Node toolchain in CI/Docker; disposable container build for ESM-only libraries (precedent: EasyMDE; planned: TipTap)
- [django](../django/SKILL.md) — backend pairing (BaseModel, DRF, ORM optimisation, permissions)
- [surgical-tdd](../surgical-tdd/SKILL.md) — testing approach for Django apps
- [`RULE_i18n-workflow`](../../rules/RULE_i18n-workflow.md) — translation hard rules
- [HTMX Documentation](https://htmx.org/docs/)
- [Alpine.js Documentation](https://alpinejs.dev/)
- [Bulma CSS Documentation](https://bulma.io/documentation/)
- [Django Crispy Forms](https://django-crispy-forms.readthedocs.io/)

**Last Updated**: 2026-04-27 (afternoon) — extended "Template comment syntax" with the sibling trap "Django tag literals inside JS `//` comments" (`TemplateSyntaxError: 'trans' takes at least one argument` → 500), compounded from two same-session occurrences in the teisutis 2026-04-27 staging test loop ([PR #375](https://github.com/infohata/teisutis/pull/375) [fix commit `a3b6f074`](https://github.com/infohata/teisutis/commit/a3b6f074), PR #376 in commit `002ccd98`). Same root cause as the multi-line `{# #}` case (Django parser ignores JS comment syntax), different symptom (compile-time error vs render-time content leak). Previous: 2026-04-27 morning — added "Template comment syntax — `{# inline #}` is single-line only" under Pattern; compounded from teisutis IDEA-124 [PR #375](https://github.com/infohata/teisutis/pull/375) ([fix commit](https://github.com/infohata/teisutis/commit/c68905ab)). The failure mode is a content leak (literal comment text shown to end users), not a template error — no CI signal until someone hits the page. Previous: 2026-04-26.
**Version**: 2.2
