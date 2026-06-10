---
name: django-frontend
description: Apply Django frontend conventions — HTMX partial responses, Alpine.js state, Bulma components, HTMX modal/formset JS contracts, safe query-string generation, dynamic hx-* attribute handling, and Cotton component primitives — pairing with django backend patterns. Includes hard hazard rules every template edit must respect — multi-line `{# … #}` Django comments leak as visible content (use `{% comment %}…{% endcomment %}` for prose blocks), Django tag literals inside JS `//` comments still compile and 500 the page, and SCSS `@import url('../vendor.css')` is browser-runtime-resolved (relocate-fragile; vendor CSS belongs in a `<link>` tag).
license: Apache-2.0
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

## When to use

**TRIGGER when:** editing templates (`*.html`) in a Django project; wiring an HTMX partial endpoint; adding a Bulma modal / form / table / widget; writing an Alpine.js component; debugging `htmx.process` or URL-encoding issues in `hx-*` attributes; converting Django messages to Bulma notifications.

**SKIP for:** backend-only work (use [django](../django/SKILL.md)); real-time collaborative editing (WebSockets + React/Vue territory); offline-first PWAs; heavy client-side data processing; mobile native apps.

## Critical hazards (read these first)

Three high-blast-radius traps that ship as user-visible regressions if you skim past them. Each has a full section below — but you need to know they exist before writing the next template line:

1. **Multi-line `{# … #}` Django comments leak as visible page content.** `{#` is single-line only; multi-line content between `{#` and `#}` is parsed as raw template content. Always use `{% comment %} … {% endcomment %}` for any prose spanning more than one line. Full section: [`### Template comment syntax — `{# inline #}` is single-line only`](#template-comment-syntax--inline-is-single-line-only). *(Recurrent — the rule needs to be in the skill's first 100 lines, not just buried in cross-refs.)*

2. **Django tags inside JS `//` comments still compile.** `// fallback uses {% trans %}` in a `<script>` block is NOT a JS comment to Django — the `{% trans %}` parses and `'trans' takes at least one argument` 500s the entire template. Full section: [`### Sibling trap — Django tag literals inside JS // comments`](#sibling-trap--django-tag-literals-inside-js--comments).

3. **SCSS `@import url('../vendor.css')` is browser-resolved at runtime, not Sass-compile-time.** If the compiled CSS file's path moves (e.g. relocating a Django app's static folder), the relative URL 404s in the browser even though Sass compiled cleanly. Vendor stylesheets belong in a `<link>` tag in the base template, NEVER in an SCSS `@import url(...)`. Full section: [`### SCSS vendor-import hazard — @import url() is runtime, not compile-time`](#scss-vendor-import-hazard--import-url-is-runtime-not-compile-time).

## Pattern

### Partial/fragment response

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

### Component system

This stack's component system is **django-cotton** (composition) paired with **Bulma
standards** (styling — see `## Bulma template standards` below); full primitives in
[references/COTTON.md](references/COTTON.md).

**TRIGGER:** editing a `<c-*>` component or its slots; registering a new cotton component under `templates/cotton/`; passing `:prop` (Python expression) vs `prop` (literal string) attributes; configuring django-cotton in `TEMPLATES` settings; bootstrapping client state via `data-initial-*` from a cotton root.

Two pitfalls sharp enough to flag in primary context:

1. **`:prop` coercion is opaque** — cotton coerces `:prop` values through Django's template engine, so booleans become `"True"` / `"False"` strings, integers become decimal strings, `None` becomes `"None"`. For multi-field client-state seeding, prefer a single `<script type="application/json">` seed over per-field `:prop` attributes; the cotton root carries only the boolean that drives mount-state visual. Full walkthrough in the reference.

2. **Multi-line `{# … #}` comments inside cotton component templates** crash the engine the same way they leak in regular templates — Django's tokeniser doesn't recognise multi-line `{# … #}`, and a literal `{% include %}` (or any tag) inside the prose 500s. Use `{% comment %}…{% endcomment %}` for prose blocks (same trap as *Template comment syntax* below — applies inside cotton component templates too).

The reference covers: file layout (`templates/cotton/`); settings (loader + builtins, why `SimpleAppConfig`); call-site syntax (`:prop` vs `prop`); render-and-assert test pattern using `engines['django'].from_string` with the cotton-builtins workaround; the cotton-vs-`{% include %}` decision table; the `:prop`-coercion bug walked end-to-end with the JSON-seed fix and a single-attribute-on-root test contract.

### App-shell layout — fixed viewport + per-pane scroll containers

**Fires when** building a single-page-feel app shell (Slack/Discord/Gmail-style: top nav + workspace pane + centre + preview pane) where the document never scrolls — every scroll happens inside one of the named panes. The `html.shell-html` class scope keeps legacy document-scroll pages unaffected.

Mechanics — `shell-html` / `shell-body` / `shell-main` / `shell-center` SCSS primitives, the load-bearing **"unstable child" rule** (`min-height: 0` at every flex chain link whose descendant has `overflow-y: auto`), where modals/toasts/sticky-within-pane elements live, the shared `scroll-utils.findScrollContainer` walk-up helper, the `scrollHeight > clientHeight` filter, regressions when migrating from document-scroll (window-scroll readers go quiescent, modal scroll-position snapshots become no-ops), and the render-and-assert test contract — are in [`references/APP_SHELL_LAYOUT.md`](references/APP_SHELL_LAYOUT.md). Read that reference when this section fires.

### Reactivity model

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
       (see "Reactivity model" above). Same justification
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

### Alpine.store coordinators with delayed-registered consumers — `onRegister` callback pattern

**Fires when** an `Alpine.store('foo')` coordinator needs to drive a per-instance consumer (a registered drawer instance, a registered modal instance, a per-component Alpine factory) and the consumer registers asynchronously-after-store-init. The store exists at `alpine:init`, but each consumer's `x-data` factory runs during the DOM walk that follows — so the store can't talk to a registered consumer synchronously.

The fragile pattern this replaces — `Alpine.effect`-poll-instance — has implicit re-evaluation, stacking monkey-patches across re-runs, unobservable teardown, and instance-replacement leaks. Symptom: "feature works the first time, breaks after the consumer re-registers" — N hours of debugging timing. The fix is an explicit register-or-queue API on the coordinator store: `register(name, ...)` paired with `onRegister(name, callback)`. Mechanics — full coordinator + consumer shapes, why one-shot semantics + sync-or-deferred transparency + no-reactive-deps + failure-isolation matter, generalisation to modal / drawer / preview-surface stores — are in [`references/ALPINE_STORE_COORDINATORS.md`](references/ALPINE_STORE_COORDINATORS.md). Read that reference when this section fires.

### Active-state tracking — `aria-current="true"` + CSS `:has()` instead of JS class toggling

**Fires when** a list of links has a "currently selected" item that should style differently. The obvious shape — JS-side `classList.add('--selected')` driven by `Alpine.effect` or a click handler — creates two sources of truth (store state + DOM class) that JS has to keep in sync, and HTMX swaps race against the JS re-walk.

The fix is `aria-current="true"` on the link as the single source of truth, with SCSS `:has(a[aria-current="true"])` targeting the parent row for the visual. Server template emits `aria-current` on cold-start; JS keeps it in sync; CSS owns the visual. Free a11y as a side effect — screen readers announce `aria-current` as "current item". Mechanics — full anti-pattern + fix + scss `:has()` browser support + HTMX-swap-friendliness + test contract + when-NOT-to-use (hover effects / client-only states stay client-only) — are in [`references/ACTIVE_STATE_TRACKING.md`](references/ACTIVE_STATE_TRACKING.md). Read that reference when this section fires.

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

### Form-submission lock

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

`HTMLMediaElement.canPlayType(mime)` returns one of `''`, `'maybe'`, `'probably'`. With a **bare MIME** (no codec parameters — e.g. `audio/webm`, `audio/ogg`), browsers disagree on what `'maybe'` means: Safari treats `'maybe'` as "I might fail to decode this", Chrome and Firefox treat it as "I will probably play this." Pick either interpretation and you false-negative on the other set of browsers. A worked audio-playback fallback oscillated through four review-loop cycles trying to land a `canPlayType` thresholding rule that worked everywhere; none of them did.

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

**Fires when** writing comments inside Django templates. `{# … #}` is single-line only; multi-line comments must use `{% comment %} … {% endcomment %}`. Mixing them produces a silent **content leak**: a multi-line `{#` opens, hits a newline before `#}`, and Django's tokeniser emits the entire block as plain text on the rendered page. No template error, no test failure — just literal comment text shown to end users.

Mechanics — full syntax matrix, leak failure-mode example, worked example (audio-fallback comment leaked into chat-input UI), and the grep-based detection recipe (`{#` followed by a newline before `#}`) suitable for CI pre-commit lint — are in [`references/TEMPLATE_COMMENT_SYNTAX.md`](references/TEMPLATE_COMMENT_SYNTAX.md). Read that reference when this section fires.

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

**Fires when** a Django project compiles SCSS to CSS via libsass / dart-sass / `compile_scss` and serves the result through `collectstatic`. The trap: `@import url('../vendor/bulma.min.css')` inside SCSS is NOT resolved by Sass at compile time — Sass copies the line verbatim into the compiled `.css`; the **browser** resolves the relative URL at runtime against the COMPILED CSS file's URL. App relocation, `STATIC_ROOT` change, or sibling-app reorg → `bulma.min.css` 404s; page renders unstyled while Sass compiled cleanly.

The fix: vendor CSS goes in a `<link>` tag in base.html (`{% static %}` resolves through Django's staticfiles finders, settings-aware); SCSS only handles theme + component styles. Mechanics — full failure-mode walkthrough, four recurrence triggers, ❌/✅ syntax examples, worked example (an app rename broke the compiled-CSS URL), grep-based detection recipe, and the partial-import exception (`@import 'partial';` is Sass-time, not the hazard) — are in [`references/SCSS_VENDOR_IMPORT.md`](references/SCSS_VENDOR_IMPORT.md). Read that reference when this section fires.

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

- [App-shell layout](references/APP_SHELL_LAYOUT.md) — fixed-viewport + per-pane-scroll layout primitives, "unstable child" `min-height: 0` rule, `scroll-utils.findScrollContainer` helper, document-scroll-migration regressions, edge-affordance-lip reserved-gutter placement doctrine
- [Nav / chrome consolidation](references/NAV_CHROME_CONSOLIDATION.md) — one canonical chrome component fed by context: a `variant` rendering different markup is still a fork; single-slot placement policy for cross-surface affordances (badge: in app-nav when present, else header, exactly one per page); identity-slot mutual exclusion (`{% if authed %}user-menu{% else %}sign-in{% endif %}` in one shared slot); the generation-vs-display debugging tell (audit the render target before debugging working generation)
- [Sub-entity presentation tier](references/SUB_ENTITY_PRESENTATION_TIER.md) — migrating a dashboard's sub-entity collections onto the shell: **bounded** → inline preview-drawer drilldown (no standalone surface); **unbounded/historical** → bounded teaser (actionable slice, not first-N) + dedicated filterable centre sub-surface at an additive URL; keep `active_surface` on the parent, one uniform permission selector across teaser/surface/row-actions
- [Alpine.store coordinators with delayed-registered consumers](references/ALPINE_STORE_COORDINATORS.md) — `onRegister` callback pattern: register-or-queue API, one-shot semantics, sync-or-deferred transparency, replaces fragile `Alpine.effect`-poll-instance idiom; + when NOT to use a store — the inbound-command CustomEvent bridge for triggering a scoped method from outside the tree
- [Active-state tracking](references/ACTIVE_STATE_TRACKING.md) — `aria-current="true"` + CSS `:has()` instead of JS class-toggling for "currently selected" list items: single source of truth, free a11y, HTMX-swap-friendly
- [Template comment syntax](references/TEMPLATE_COMMENT_SYNTAX.md) — `{# inline #}` is single-line only; multi-line uses `{% comment %}`; content-leak failure mode; grep-based detection recipe for CI lint
- [SCSS vendor-import hazard](references/SCSS_VENDOR_IMPORT.md) — `@import url()` is runtime, not compile-time; vendor CSS belongs in `<link>`; failure-mode + recurrence triggers + detection grep
- [SCSS responsive patterns](references/SCSS_RESPONSIVE_PATTERNS.md) — shared styling that differs at a breakpoint / across surfaces: (1) `@extend` can't cross `@media` → use a `@mixin` (+ the compiler-path-masking trap — verify on the strict e2e/CI compiler, not just the permissive dev build); (2) cascading CSS custom property on the root as one source for a responsive footprint consumed by ≥2 components; (3) additive-padding collapse — designate one gutter owner, zero nested layers' horizontal padding at the constrained breakpoint; (4) a rule shared across N shell surfaces via an enumerated `.surface-role` selector list or per-pane inline copy **fails open** on a new surface (silently mis-styled, no error) — use ONE base class surfaces opt into / a mixin they `@include`; audit "which shared conventions must a new surface adopt?" as a checklist item
- [Base Template + Theme](references/BASE_TEMPLATE.md) — full `base.html`, Alpine theme store, SCSS build pipeline
- [Modal System](references/MODAL_SYSTEM.md) — `openModal` / `closeModal` / `confirmAction` implementation
- [HTMX Widgets](references/HTMX_WIDGETS.md) — autocomplete, file upload, colour/icon pickers
- [Advanced Components](references/ADVANCED_COMPONENTS.md) — theme store, notifications, utilities
- [HTMX Patterns](references/HTMX_PATTERNS.md) — detailed HTMX implementation patterns
- [Alpine + HTMX Gotchas](references/ALPINE_HTMX_GOTCHAS.md) — Alpine 3 factory `x-data` auto-init trap, `HX-Trigger` value-wrapping shape, defer-vs-DOMContentLoaded ordering, `hx-on::*` plain-JS scope (not Alpine), `hx-trigger="click once"` doesn't fire on synthetic state changes, **Alpine `:class="cond && 'str'"` short-circuit doesn't remove SSR-applied classes (gotcha 10 — use object syntax)**, gotcha 8 permanent-bind + active-discriminator (+ the `MutationObserver`-mirror variant for a consumer with no native event of its own)
- [CSS `display: contents` selector traps](references/CSS_DISPLAY_CONTENTS_SELECTOR_TRAPS.md) — CSS selectors see DOM hierarchy, not box-tree transparency; widen every breakpoint's selectors symmetrically when inserting `display: contents` intermediates; the asymmetric-fix anti-pattern (desktop widened, mobile missed)
- [Data-attribute markers + JS click handler convention](references/DATA_ATTR_NAV_CONVENTION.md) — `<a data-shell-nav-link>` + single document-level JS handler instead of raw `hx-*` on the link; URL update is a deliberate `history.pushState` step, not a swap side-effect; shareable click-decision composition; disjoint vocabulary across marker families
- [Router action vocabulary — atomic, never procedural](references/ROUTER_ACTION_VOCABULARY.md) — routers / dispatchers / state-machines emit `{action: '<verb>', …}` with atomic decision verbs (`open` / `push` / `close`) only, never compound procedures (`syncToTokens` / `applyAll` / `reconcile`); two-of-three-callers structural test; dispatcher switch stays one-line-per-case
- [HTMX Scroll Preservation](references/HTMX_SCROLL_PRESERVATION.md) — two scenarios: (1) Load-older / inverse-pagination prepend primitive via marker-offsetTop diff math (robust to `display: contents` wrappers + concurrent below-marker mutations); (2) in-place *replace* refresh (delete-a-row / refresh-on-event) where `outerHTML` resets `scrollTop` to 0 — capture-before / rAF-restore-after on the resolved scroll container, universal `document.body` listener
- [Diagnostic instrumentation hygiene — `_trace()` arg-eval trap](references/DIAGNOSTIC_INSTRUMENTATION_HYGIENE.md) — flag-gated JS diagnostics: ship a lazy `_traceFn(label, () => payload)` variant from the start; JS evaluates args before the wrapper's flag check, so eager payloads run unconditionally. Gate at handler-call-sites; cache values shared by code path + trace
- [Cotton Components](references/COTTON.md) — django-cotton primitives: file layout, settings, call-site syntax (`:prop` vs `prop`), render-and-assert tests, and the `:prop`-coercion → JSON-seed pattern; three-layer split (shared / per-entity workflow / composition); `data-preview-link` href-as-fragment-url convention; nested-anchor anti-pattern; detail-variant `hx-target="this"`; default-true prop pattern + the `|lower != 'false'` case-insensitive string-coercion dual-guard; the Bulma-`.icon`-wrapper force-position trap (render bare, copy the select-arrow centring recipe); structural-element-persists-when-child-is-`hx-target` (poll-into-tbody → gate empty-state outside, `:is_empty="False"`)
- [Filter-Form Trigger Single Source](references/FILTER_FORM_TRIGGER_SINGLE_SOURCE.md) — one `FILTER_FORM_HX_TRIGGER` constant + `{% filter_form_trigger %}` tag shared by every filter form (kills per-surface `hx-trigger` drift); form-level event-filtered trigger covering `select`/`checkbox`/`text`/`search` by `from:` selector; `type=search` listed alongside `type=text` (+ JS `htmxFiresOnText` double-fire guard mirrors it); enumerate-and-grep drift-guard test; clear-✕ clears only `q` and re-submits carrying other filters (document-delegated, CSS `:placeholder-shown` visibility)
- [Preview Drawer URL Stack](references/PREVIEW_DRAWER_URL_STACK.md) — `?open=&push=` URL contract + state-mutation primitives (`store.top` snapshot trap, walker rebind, edit-frame guard, universal edit→detail invariant, empty-snapshot pop fallback, `data-preview-route="open"`, `openWith()` LCP-dedupe natural-parent stacking)
- [Drawer Form-State Preservation](references/DRAWER_FORM_STATE_PRESERVATION.md) — clone-mirror-strip snapshot pipeline + `previewSurface:beforeSnapshot` cleanup hook
- [Session Filter Persistence](references/SESSION_FILTER_PERSISTENCE.md) — per-entity vs cross-entity filter session split (`cross_filters_<org_id>`, `<namespace>_<entity>_filters_<org_id>`); `_filter_form=1` real-submit sentinel; `?clear=1` 302; `CHECKBOX_TOGGLE_KEYS` allowlist for unchecked-checkbox absence-as-uncheck; resolver `filter_keys` must be a superset of what the render fn reads (under-scoping silently starves the toggles — symptom mis-points at the render fn); one `namespace` across write-path form + read-path refresh partial (else submit-persists / refresh-evaporates); chip-row + per-filter-clear endpoint
- [Script-tag JSON escaping](references/SCRIPT_TAG_JSON_ESCAPING.md) — server-rendered JSON embedded in a `<script>` block is a stored-XSS vector (`mark_safe(json.dumps(...))` doesn't escape `<`/`>`/`&` → an entity name with `</script>` breaks out); escape as `\uXXXX` via one shared `escape_seed_json` helper (or `{{ value|json_script }}`); sweep ALL sibling views, not just the flagged one; test with a `</script>`-bearing name
- [CSP inline-handler → delegation](references/CSP_INLINE_HANDLER_DELEGATION.md) — converting native `on*=` / `javascript:` URIs to body-level `addEventListener` delegation to drop `script-src 'unsafe-inline'` (Alpine `@click`/`hx-on::` are eval-based — keep `'unsafe-eval'`, untouched). Three traps: (1) **drop `|escapejs`** when a value moves from a JS-string context into a `data-*` HTML attribute (escapejs emits `\uXXXX` that renders literally; rely on HTML autoescape); (2) `textContent` does NOT decode HTML entities but `getAttribute` does (hardcoded `&quot;` in a JS fallback renders raw); (3) bind drawer widgets on `htmx:afterSettle` not `afterSwap`. Delete dead handlers, don't convert; lock with source-assert + e2e CSP-violation probe (curl can't see CSP refusals)
- [Shell Notifications](references/SHELL_NOTIFICATIONS.md) — `uiNotify` CustomEvent canonical toast dispatch; legacy `window.show*` + `#messages-container` writes forbidden; `HX-Trigger: <eventName>` for `outerHTML`-swap targets containing the trigger
- [Collapsible Patterns](references/COLLAPSIBLE_PATTERNS.md) — native `<details>` + `toggle` event for chevron + lazy-fetch + sessionStorage persist (eliminates Alpine state-machine desync); lazy-load bucket recipe for multi-bucket surfaces with cheap counts upfront
- [HTMX Widget Lifecycle](references/HTMX_WIDGET_LIFECYCLE.md) — the shared (re-)init / teardown / idempotency / `readyState`-safe-boot contract every HTMX-swapped JS widget follows; canonical home that `VENDORING_JS_BUNDLES` (always-loaded glue) and `LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV` (lazy-injected binder) both build on instead of restating
- [Listener rebind on swap](references/LISTENER_REBIND_ON_SWAP.md) — per-container / per-pane JavaScript listeners (not document-delegated) that die silently when their binding element gets `outerHTML`-swapped. Distinct from `HTMX_WIDGET_LIFECYCLE` §6 (widgets re-mount inside a swap target via synthetic events). 3rd-recurrence pattern across tag-filter pills + navbar scroll-hide + sticky section-nav scroll-spy. Includes the adjacent scroll-container-ownership-after-flex-stretch failure mode (listener IS bound but scroll happens elsewhere because a child claimed `overflow: auto`).
- [stopPropagation kills document-delegated handlers](references/DELEGATED_HANDLER_STOPPROPAGATION_TRAP.md) — a `@click.stop` / `onclick="event.stopPropagation()"` guard on a dropdown/kebab wrapper halts the bubble before it reaches `document`, so a document-delegated action handler inside (confirm-trigger, preview-open) never fires — Delete silently dead-ends. The guard is usually unnecessary too (the sibling open-handler is already `closest()`-scoped). Plus: drive click affordances with an Alpine click-toggle, never Bulma `is-hoverable` (hover-only → no click feedback, dead on touch). The inverse of `LISTENER_REBIND_ON_SWAP` (delegate from `document` to survive swaps; this one keeps an upstream guard from strangling that delegation).
- [Scroll-spy patterns](references/SCROLL_SPY_PATTERNS.md) — two non-obvious gotchas: (1) `IntersectionObserver` flickers between adjacent sections at threshold crossings — use rAF-throttled scroll handler reading ALL targets every frame, monotonic; (2) any conditional CSS property that affects intrinsic width (font-weight, padding, letter-spacing) ripples sibling positions during scroll-spy — use color-only differentiation for active state, or same-axis pre-reservation when emphasis truly needs more weight.
- [Hyphenate narrow labels](references/HYPHENATE_NARROW_LABELS.md) — `hyphens: auto` + vendor prefixes + `<html lang>` for table headers / nav chrome / chip labels that squeeze on narrow viewports in inflected languages (lt/pl/ru/nb/de/et/lv). Browser dictionary keyed off lang attribute; `overflow-wrap: break-word` as the fallback when a locale lacks a dictionary. Adjacent to the i18n-side "Add X" verb-form convention in `../django/references/I18N_WORKFLOW.md`.
- [Forms — cross-skill index](references/FORMS_INDEX.md) — entry point for form work spanning rendering / status+swap / validation / formsets / uploads / filter-form session / drawer-state; bridges django backend form refs without a grep.
- [Form rendering patterns](references/FORM_RENDERING_PATTERNS.md) — three Bulma shapes (`{% crispy form %}` / manual `<input class="input">` / widget-attrs) + the unstyled-bare-field trap + help_text `<p>`-vs-`<div>` wrapper trap.
- [Vendoring JS Bundles](references/VENDORING_JS_BUNDLES.md) — vendor pre-built JS to `static/vendor/`, zero Node toolchain in CI/Docker; disposable container build for ESM-only libraries (precedent: EasyMDE; planned: TipTap)
- [Lazy-load heavy assets on HTMX nav](references/LAZY_LOAD_HEAVY_ASSETS_ON_HTMX_NAV.md) — heavy per-surface bundles (diagram renderer, rich-text editor) live in `extra_js` OUTSIDE the swapped region, so they never load on cross-surface shell-nav. "Declare once, render twice": one server manifest → cold-load `<script>` tags AND a nav-time `data-*` attribute (`static()`-resolved at REQUEST time — hashed-static can't be hardcoded client-side); a loader with its own `htmx:afterSwap` reads the FRESH node, injects sequentially, in-flight-dedupes, always re-inits. `ready()` must validate the bundle's LAST global (partial load = stuck half-loaded otherwise); injected binders need a `readyState`-safe boot + idempotent container-scoped init. Shell-infra scripts stay eager.
- [HTMX + Alpine Waits](references/HTMX_ALPINE_WAITS.md) — Playwright wait recipes: four-class HTMX swap completion, Alpine readiness via `Alpine.$data()`, HTMX-during-Alpine-init race
- [Multi-tenant Playwright](references/MULTI_TENANT_PLAYWRIGHT.md) — django-tenants Playwright fixtures: Host-header injection, schema seeding, storage_state cookie pre-baking inside `schema_context`
- [Visual-acuity tests via Playwright](references/VISUAL_ACUITY_TESTS_VIA_PLAYWRIGHT.md) — Playwright-vs-render-and-assert decision table + Docker/Django bootstrap traps (full list in the reference)
- [Visual Baseline Bumps](references/VISUAL_BASELINE_BUMPS.md) — AI agents NEVER auto-`--update-snapshots`; baseline regen requires explicit human invocation; default-locale baselines + structural-only locale assertions
- [django](../django/SKILL.md) — backend pairing (BaseModel, DRF, ORM optimisation, permissions)
- [surgical-tdd](../surgical-tdd/SKILL.md) — testing approach for Django apps
- [`RULE_i18n-workflow`](../django/references/I18N_WORKFLOW.md) — translation hard rules
- [HTMX Documentation](https://htmx.org/docs/)
- [Alpine.js Documentation](https://alpinejs.dev/)
- [Bulma CSS Documentation](https://bulma.io/documentation/)
- [Django Crispy Forms](https://django-crispy-forms.readthedocs.io/)
