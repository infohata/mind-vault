# Cotton components

Companion reference to [`../SKILL.md`](../SKILL.md). [`django-cotton`](https://github.com/wrabit/django-cotton) component primitives — file layout, settings, call-site syntax, render-and-assert tests, and the cold-start `:prop`-coercion hazard with its JSON-seed fix.

**TRIGGER:** editing a `<c-*>` component or its slots; registering a new cotton component under `templates/cotton/`; passing `:prop` (Python expression) vs `prop` (literal string) attributes; configuring django-cotton in `TEMPLATES`; bootstrapping client state via `data-initial-*` from a cotton root.

## Cotton components for prop-shaped UI

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

❌ DON'T: use multi-line `{# … #}` comments **inside cotton component templates**. `{#` is single-line in Django; multi-line content between `{# … #}` is parsed as raw template content, and a literal `{% include %}` word inside the prose crashes the engine. Use `{% comment %}…{% endcomment %}` for prose blocks (full hazard write-up in [`../SKILL.md`](../SKILL.md) § *Template comment syntax — `{# inline #}` is single-line only* — same trap, applies inside cotton component templates too).

❌ DON'T: import vendor CSS via `@import url(...)` from compiled SCSS. Browser resolves relative URLs against the compiled CSS file's URL at runtime — if the compiled CSS path moves (e.g. an app rename like `core` → `ui`), the import 404s. Link vendor CSS via a sibling `<link>` in `base.html` instead, and let SCSS only handle theme + component styles. Full hazard write-up in [`../SKILL.md`](../SKILL.md) § *SCSS vendor-import hazard — `@import url()` is runtime, not compile-time*.

## Cotton `:prop` coercion is opaque — prefer JSON seed for cold-start client state

When a server-rendered page needs to bootstrap a client-side store with multi-field state (drawer initial open + selected entity type + selected identifier + title + url for a deep-link), the obvious shape is per-field cotton `:prop` attributes that flow through to `data-initial-*` on the rendered root:

```django
{# Looks clean — but cotton's boolean+string coercion is opaque #}
<c-preview-drawer :initial_open="preview_open"
                  :initial_type="parsed.type"
                  :initial_identifier="parsed.identifier"
                  :initial_title="title"
                  :initial_url="url" />
```

The trap: cotton coerces `:prop` values via Django's template engine — booleans become `"True"` / `"False"` strings, `None` becomes `"None"`, integers become decimal strings, but the JavaScript reading the rendered `data-initial-*` attribute has no way to know which type the server intended. `data-initial-open="0"` could mean closed-state-bool OR identifier-zero. Empty `data-initial-title=""` could mean missing OR empty-string. The bugs surface as silent client-state divergence — the cold-start drawer mounts but its body is empty because one of the per-frame attrs failed to round-trip.

**The fix — single JSON seed, single source of truth, same code path as hot-open**:

```django
{# Cotton root carries ONLY the boolean primitive that drives mount-state visual #}
<c-preview-drawer :initial_open="preview_open">
    {% block preview %}{% endblock %}
</c-preview-drawer>

{# Per-frame state goes in a JSON seed script the JS reads at init #}
{% if preview_open_seed_json %}
    <script type="application/json" id="ui-preview-cold-start">{{ preview_open_seed_json|safe }}</script>
{% endif %}
```

```javascript
// At alpine:init, read the seed and call the store's normal open() — the
// same code path hot-open clicks take. No "cold-start branch" in the store.
function _coldStartFromSeedScript() {
    const seedEl = document.getElementById('ui-preview-cold-start');
    if (!seedEl) return;
    let seed;
    try { seed = JSON.parse(seedEl.textContent || ''); } catch (err) { return; }
    if (!seed || !seed.type || !seed.identifier) return;
    Alpine.store('previewSurface').open(seed);
}
```

The view emits the seed:

```python
seed: dict[str, str] | None = None
if parsed is not None and parsed.type is OpenType.DEV_PREVIEW:
    seed = {
        'type': parsed.type.value,
        'identifier': parsed.identifier,
        'title': f'Dev preview {parsed.identifier}',
        'url': reverse('app:dev_preview_detail_fragment', args=[parsed.identifier]),
    }
context = {
    'preview_open': seed is not None,
    'preview_open_seed_json': mark_safe(json.dumps(seed)) if seed else '',
}
```

**Why this wins**:

- **Type fidelity**: `json.dumps` preserves bool/null/string/int — the JS `JSON.parse` round-trip is exact. No coercion ambiguity.
- **One code path**: the cold-start JS calls `store.open(seed)` — the same method hot-open clicks call. Bugs in cold-start ARE bugs in hot-open; can't diverge.
- **Empty-state is unambiguous**: `if (!seed || !seed.type || !seed.identifier) return` — single guard covers absent script tag, empty JSON, missing fields. No "is `data-initial-open=""` falsy or stringified-falsy or boolean-coerced" guessing.
- **Cotton root stays minimal**: only one `:prop` (the boolean that drives mount-state visual) — every other field flows through the seed. The cotton root's contract is small and testable: `data-initial-open="1"` or `"0"`, nothing else.

**Test contract — lock in that the cotton root carries EXACTLY one `data-initial-*` attribute**:

```python
def test_initial_open_is_the_only_initial_attribute_on_cotton_root(self):
    """Cotton root must carry only data-initial-open; per-frame seed flows
    via the JSON script, not via cotton :prop interpolation."""
    rendered = _normalise(_render_cotton(
        '<c-preview-drawer :initial_open="True" />',
        {'preview_open_title': 'Should not leak through cotton'},
    ))
    attrs = set(re.findall(r'data-initial-[a-z-]+', rendered))
    self.assertEqual(attrs, {'data-initial-open'},
        f'cotton root must carry only data-initial-open; found: {attrs}')
```

Any future contributor adding a per-frame attribute to the cotton root re-introduces the boolean+string coercion hazard; the test fails first.

## Three-layer cotton split — shared / per-entity workflow / composition

Once a project has 2+ entity surfaces (Article, Event, FAQ, …) that ALL need cotton component coverage, the natural shape is three concentric layers, not two:

| Layer | Lives in | Examples | Owned by |
|---|---|---|---|
| **Shared neutral** | `<ui-app>/templates/cotton/` | Edit / Delete / AI / generic pill / icon button | Cross-entity, identical lifecycle |
| **Per-entity workflow** | `<entity-app>/templates/cotton/` | Approve / Assign / Snooze / Mark-Executed | Per-entity, different lifecycles |
| **Composition cotton** | Either, by ownership of the "row" | `<c-article-card>`, `<c-event-detail-actions>` | Wires shared + workflow together |

The trap that the split prevents: hoisting "Approve" or "Snooze" into the shared layer because both Article and Event have an "Approve" button. They look identical visually, but their lifecycles diverge (Article-Approve flips a draft→published bit; Event-Approve assigns a reviewer + sets a date). Sharing one component forces N entity-specific branches inside the shared file, and adding a new entity means amending the shared file — exactly what the split was supposed to remove.

The composition layer is where the layout lives. Canonical pattern: workflow-cluster (entity-specific) → AI → Edit → `── horizontal rule ──` → Delete. The rule separates routine actions from destructive ones. The composition file is the right place for that ordering decision.

When promoting from `{% include %}` to cotton across an entity:

1. Start with the per-entity workflow components — they touch the most surface and don't need consensus across entities to ship.
2. Compose them with `<c-edit-button :href="..." />` / `<c-delete-button :href="..." />` from the shared layer.
3. Build the per-entity composition cotton (`<c-article-actions>`, `<c-event-detail-actions>`) last — it's the layout-decision layer and benefits from having both wings already stable.

## Dict-literal cotton props silently drop context vars

`django-cotton ≥ 2.6` does NOT evaluate template context variables inside dict-literal cotton-attr values. A prop declared as `:link_attrs="{'type': 'event-edit', 'identifier': event.pk}"` looks like it threads two values through — at render time it threads an **empty dict**, and any `{% if link_attrs.type %}` gate inside the cotton emits nothing. No JS error, no template-render error; the surface still LOOKS correct under casual inspection. Static-prop tests pass (literals flow); the bug only surfaces when a context variable is referenced from inside the dict.

Reproducer:

```python
from django.template import engines
from django_cotton.compiler_regex import CottonCompiler

tpl = '<c-edit-button :link_attrs="{\'identifier\': my_int}" />'
rendered = engines['django'].from_string(CottonCompiler().process(tpl)).render({'my_int': 54})
# `link_attrs` arrives as `{}` — not `{'identifier': 54}`.
# `{% if link_attrs.identifier %}` evaluates falsy; `<a data-identifier="...">` is NOT emitted.
```

**Workaround — two explicit props.** The colon-prefixed `:prop="single_var"` form DOES resolve context vars when the value is a single expression (just not a dict literal):

```html
{# ❌ Silently broken — dict literal swallows the context var #}
<c-edit-button :link_attrs="{'type': 'event-edit', 'identifier': event.pk}" />

{# ✅ Works — two single-value props #}
<c-edit-button preview_type="event-edit" :preview_identifier="event.pk" />
```

**When the cotton genuinely needs a dict shape** (e.g. Alpine `x-data` payload, CSS-style mapping), build it in the view and pass as a single context-var name:

```python
ctx["event_edit_link_attrs"] = {"type": "event-edit", "identifier": event.pk}
```

```html
<c-edit-button :link_attrs="event_edit_link_attrs" />
```

Regression-lock test (resolve from a context variable, not a literal):

```python
def test_preview_identifier_resolves_from_context_variable(self) -> None:
    tpl = '<c-edit-button :preview_identifier="event_pk" />'
    rendered = _render_cotton(tpl, {'event_pk': 7})
    self.assertIn('data-preview-identifier="7"', rendered)
    self.assertNotIn('data-preview-identifier="event_pk"', rendered)
```

(`_render_cotton` is a per-project test-fixture helper — same shape as the Reproducer above: `engines['django'].from_string(CottonCompiler().process(tpl)).render(ctx)`. Most projects with cotton coverage already define it in `tests/test_components.py` or equivalent; see the line-210 test for the same convention.)

Every cotton with a `:prop` expected to thread a context variable deserves one such test.

## Slot-based composition vs prop-driven enumeration for multi-action cottons

When a composition cotton wraps N child items with per-item visibility gates (per-permission, per-feature-flag, per-entity-state), two shapes are natural:

- **Prop-driven**: the wrapper takes `:actions=['workflow', 'ical', 'ai', 'edit', 'delete']` + a per-action bag (`:edit_href`, `:delete_confirm_url`, `:user_can_edit`, …). The wrapper iterates and conditionally renders each child.
- **Slot-based**: the wrapper provides `variant="detail|dropdown"` + a default slot. The call site composes children directly and wraps each in `{% if user_can_edit %}…{% endif %}`.

**Default to slot-based** for cluster wrappers. Prop-driven fits **leaf** cottons (single button, ≤4 well-defined props) where the call site naturally writes them out.

The slot-based default holds because:

- **Gates read naturally at the call site.** `{% if user_can_edit %}<c-edit-button ... />{% endif %}` is right next to the data the gate consults. Prop-driven hides the gate inside the wrapper's conditional chain — diff-readable only if you open both files.
- **API doesn't grow with action count.** Prop-driven wrappers hit 14+ props once a real surface ships (URL + message + permission ≈ 3 props × 5 actions). Adding a sixth action adds 3 wrapper props + touches every call site. Slot-based: just add `<c-new-action ... />` at the call site.
- **Compound gates work trivially.** `{% if user_can_edit and event.scope %}<c-ai-button ... />{% endif %}` is one line at the call site; prop-driven forces compound gates into the wrapper's API (`:can_show_ai`) or its internals.

Preserve canonical-order discipline (workflow → ical → ai → edit → delete) via call-site convention, documented in the wrapper:

```django
{% comment %}
<c-workflow-actions> — slot-based wrapper for the canonical action bar.

CALL SITE CONVENTION — children in this order inside the default slot:
  1. workflow cluster  2. iCal export  3. AI  4. Edit  5. Delete
{% endcomment %}
<div class="workflow-actions buttons are-small gap-2 mb-3">
    {{ slot }}
</div>
```

**When to switch back to prop-driven**: the canonical order is part of the wrapper's contract (sequence the cotton MUST emit even if the caller forgets), OR fewer than 3 actions with ≤10 total props. Breakpoint: ~4 actions / 10 props — past that, slot-based wins on every axis.

**Anti-shape**: a slot-based wrapper whose slot just `{% include %}`s a generic actions partial. That hoists the per-action gates back into the partial and defeats the slot's purpose — drop the wrapper and inline the actions in the parent template.

## `href` is the FRAGMENT URL on `data-preview-link` anchors

When a cotton primitive wraps an `<a data-preview-link>` (clicked → drawer fetches + opens), `href` must be the **fragment URL the drawer fetches**, not the shorthand URL the drawer pushes to history:

```django
{# ❌ Wrong — drawer fetches the SHELL HTML instead of the fragment #}
<a href="?open=article.{{ article.pk }}"
   data-preview-link
   data-preview-type="article"
   data-preview-identifier="{{ article.pk }}">{{ article.title }}</a>

{# ✅ Right — href is the fragment URL #}
<a href="/articles/ui/detail/{{ article.pk }}/"
   data-preview-link
   data-preview-type="article"
   data-preview-identifier="{{ article.pk }}">{{ article.title }}</a>
```

The drawer's click intercept reads `href` to know where to fetch from, then computes the history-push URL (`?open=article.<id>`) from `data-preview-type` + `data-preview-identifier`. Putting the shorthand in `href` lands shell HTML in the drawer body — visible regression (page-shell-inside-page-shell), no JS error.

## Nested anchors break the click intercept

Cotton primitives consumed inside `<a data-preview-link>` MUST NOT emit inner `<a>` tags. The HTML spec forbids nested anchors, so browsers split them at parse time → click hits the inner anchor → the outer `data-preview-link` never fires → drawer never opens → the user gets a hard page load instead.

```html
<!-- ❌ Browser splits the nested anchor; drawer intercept never fires -->
<a href="/articles/ui/detail/7/" data-preview-link>
    <c-event-row-header :event="event" />   <!-- emits <a href="...">Edit</a> inside -->
</a>
```

Detection: add a regex check to the cotton's test fixture asserting no `<a` tags in the rendered output for components designed to live inside preview-link wrappers:

```python
def test_no_nested_anchor(self):
    rendered = render_cotton('<c-event-row-header :event="event" />', ctx)
    self.assertNotRegex(rendered, r'<a\b')
```

The alternative — emitting `<button>` or `<span>` for actions inside a preview-link wrapper — keeps the click intercept intact. Action buttons that need their own navigation get a separate sibling outside the preview-link wrapper.

## Detail-variant cotton: `hx-target="this" hx-swap="none"`

Workflow-action cotton (Approve / Assign / Snooze) frequently has two consumers: the entity's CARD (inside a list) and the entity's DETAIL view (inside the preview drawer). The card variant naturally targets `closest .event-card` to outerHTML-swap the row. The detail variant has no `.event-card` ancestor — that selector throws `htmx:targetError` on every click.

Convention: parameterise the cotton with a variant prop and route the htmx attributes per variant:

```django
{# cotton/event_workflow_actions.html #}
{% if variant == 'detail' %}
    <button hx-post="..." hx-target="this" hx-swap="none">Approve</button>
{% else %}
    <button hx-post="..." hx-target="closest .event-card" hx-swap="outerHTML">Approve</button>
{% endif %}
```

The detail variant's `hx-swap="none"` works because the actual UI refresh rides on the `entityChanged` HX-Trigger header → a state-refresh walker fetches the detail body. The card variant outerHTML-swaps the row in place (no walker needed for that flow). Generalises to any cotton with both card + detail consumers.

## Default-true cotton props — `{% if X is not False %}` not `{% with %}`

A cotton prop that defaults to true (most callers want it enabled, opt-out with `:show_x="False"`) does NOT work via `{% with %}`:

```django
{# ❌ Wrong — {% with %} doesn't propagate to nested {% if %} as you'd expect #}
{% with show_actions=show_actions|default:True %}
    {% if show_actions %}...{% endif %}
{% endwith %}

{# ✅ Right — explicit not-False check #}
{% if show_actions is not False %}
    ...
{% endif %}

{# ✅ Also right — <c-vars> for multi-prop default declaration #}
<c-vars show_actions="True" show_metadata="True" />
{% if show_actions %}...{% endif %}
```

The cotton `<c-vars>` template tag (provided by django-cotton) is the right choice when 2+ props need defaults. Single-prop defaults can use `is not False`. Don't use `{% with %}` for prop defaults — its scope rules surprise everyone who reads the template later.

### `is not False` is insufficient when callers might pass the string `"false"`

`is not False` covers the bound-expression call site (`:show_x="False"` — the colon prefix evaluates the expression and the prop arrives as a real Python `False`). It does **NOT** cover an unbound string literal (`show_x="false"` — no colon, so the prop arrives as the **string** `"false"`, which is a non-empty string and therefore **truthy**). The two call shapes coexist in any real codebase (a test rendering `from_string("<c-table is_empty='false'>…")`, a caller who forgot the colon), so a primitive whose correctness flips on this prop needs the **dual guard**:

```django
{# ❌ Lets a string "false" through as truthy — table renders when caller meant empty #}
{% if is_empty %}…empty-state…{% endif %}

{# ❌ Catches :is_empty="False" but NOT is_empty="false" (string, truthy) #}
{% if is_empty is not False %}…{% endif %}

{# ✅ Dual guard — handles real-bool False AND any-case string "false"/"False" #}
{% if is_empty and is_empty|lower != 'false' %}…empty-state…{% endif %}

{# ✅ Same shape for a default-TRUE prop (opt-out): treat both falsy forms as off #}
{% if scroll != False and scroll|lower != 'false' %}<div class="scroll-wrapper">{% endif %}
```

This is the same opaque-`:prop`-coercion theme as the JSON-seed section above — cotton does not normalise `"false"`/`"False"`/`0` to a Python `False`; whatever the call site's quoting produces is what the template sees. The `|lower` keeps the guard case-insensitive so `"false"` and `"False"` both read as off — and the casing isn't arbitrary: Python's `str(False)` yields `"False"`, JS/JSON yields `"false"`, so a prop seeded across a language boundary can arrive in either case. It does **not** rescue an arbitrary truthy string like `"0"` or `"no"` (a Django template has no general string→bool coercion) — when a prop's value isn't a literal you control, pass it bound (`:prop="…"`) so it arrives as a real Python bool and the `!= False` half handles it. A multi-default primitive with several boolean modifiers (`striped` / `hoverable` / `fullwidth` / `scroll`, each default-on) repeats the `X != False and X|lower != 'false'` clause per modifier — verbose but unambiguous, and the only form that survives both call shapes. Lock it with a render-and-assert test that passes the prop as the **string** `"false"` (not just `:prop="False"`), since that's the case `is not False` silently misses.

## Slot truthiness sees whitespace as truthy — gate at the call site, not inside the cotton

Inside a cotton component, `{% if slot_name %}` is **TRUE whenever the slot was declared at the call site** — even when the slot's inner content evaluates to empty whitespace (template-block residue with falsy conditions inside). The whitespace + tag remnants make the slot variable non-empty for Django truthiness purposes.

```django
{# ❌ Caller declares the slot, lets inner condition decide — cotton then renders the slot wrapper around emptiness #}
<c-list-wrapper :key="articles" hx-target-id="article-list-items">
    {{ cards }}
    <c-slot name="pager">
        {% if has_more %}{% include "_load_more_pager.html" %}{% endif %}
    </c-slot>
</c-list-wrapper>

{# inside the cotton: #}
{% if pager %}<div id="…-load-more">{{ pager }}</div>{% endif %}
{# ↑ TRUE because the <c-slot> WAS declared, even when has_more is False #}

{# ✅ Gate at the call site — slot is only declared when content exists #}
<c-list-wrapper :key="articles" hx-target-id="article-list-items">
    {{ cards }}
    {% if has_more %}
        <c-slot name="pager">{% include "_load_more_pager.html" %}</c-slot>
    {% endif %}
</c-list-wrapper>
```

**Discipline: caller-decides-visibility.** Cotton primitives should detect "was the slot passed or not?", NOT "is the slot's user-content empty?". For slot visibility, the inverse of the usual "smart cotton, dumb caller" pattern is correct — dumb cotton, smart caller. The caller has the truth value (`has_more`, `items_present`); the cotton has only the rendered string.

Attempts to detect inner emptiness via `{% if pager|striptags|cut:" "|cut:"\n" %}` break the Django parser (literal whitespace in filter args). Don't go down that path; move the conditional out to the caller.

## Empty-state belongs INSIDE the slot for full-list-swap surfaces

When a cotton list-wrapper's outer is the `hx-target` of a filter form using `hx-swap="outerHTML"`, the partial's outer-wrapper REPLACES the prior render. **The empty-state must live INSIDE the cotton's slot**, alternating with the cards loop based on items presence:

```django
{# ✅ Empty-state inside slot — atomic swap, no orphan siblings #}
<c-list-wrapper :key="articles" hx-target-id="article-list-items">
    {% if articles %}
        {% for article in articles %}<c-article-card :article="article" />{% endfor %}
    {% else %}
        <div class="notification is-info is-light">No articles match the current filter.</div>
    {% endif %}
    {% if articles and has_more %}
        <c-slot name="pager">{% include "_load_more_pager.html" %}</c-slot>
    {% endif %}
</c-list-wrapper>
```

**Anti-pattern**: empty-state OUTSIDE the cotton (sibling div). On every filter swap, `outerHTML` only replaces the matched element — the prior render's empty-state sibling persists in DOM, and the response adds a new one. Result: **double empty-state** stacked visually, surfaces only on manual eval (render-and-assert tests don't catch the DOM-after-multiple-swaps state).

The cotton's inner items-container can still be unconditionally emitted (preserves structural invariant for OOB swap targets and for the load-more `beforeend` target). Only the *content* of the slot alternates — the cotton's structural shape is constant.

**Architect-amendment caveat**: when an architect says "move empty-state outside so the items container stays present", separate STRUCTURAL INTENT (items container always present — preserve) from CONSEQUENT MECHANICS (where empty-state lives — re-derive against actual swap behaviour). The "OOB swap target" usually refers to the pager wrapper, not the items container; conflating the two leads to the double-empty regression.

## Pager + empty-state must be mutually exclusive (page-beyond-end edge)

Naive composition — `{% if not items %}<empty>{% endif %}` plus an independent `{% if has_more %}<pager>{% endif %}` guard — renders BOTH when a paginated slice returns `items=[] AND total>0` (high-offset render, post-filter empty page, race after a delete). The pre-cotton templates often used a single mutex (`{% if not items %}empty{% elif items|length < total %}pager{% endif %}`) which the migration may have split apart by accident.

**Discipline**: the pager guard MUST include items truthiness:

```django
{% if items and items|length < filtered_total %}
    <c-slot name="pager">…</c-slot>
{% endif %}
```

Empty-state in the cards-or-empty alternation (see preceding section) is mutually exclusive with the pager by construction — items are either present (cards + maybe-pager) or absent (empty-state, no pager). Don't carry two independent visibility gates for them.

## A cotton primitive inside a Bulma layout class must render bare children — Bulma's descendant rules will grab any wrapper you add

When a cotton primitive lives inside a Bulma structural class (`.control.has-icons-right`, `.field`, `.card`), Bulma ships **descendant selectors that force-position any matching child** — and they fire on *your* markup, not just Bulma's own. The trap: you wrap an interactive glyph (a clear-✕ button) in Bulma's own helper class (`.icon`) for convenience, and Bulma's `.control.has-icons-right .icon { position:absolute; top:0; height:2.5em; … }` rule seizes it and pins it to the top of a `2.5em` box. On a normal-height input that's roughly centred by accident; on an `is-small` input it's visibly pushed off the vertical midline.

```html
<!-- ❌ Glyph wrapped in .icon → Bulma's `.control.has-icons-right .icon`
     forces top:0 / height:2.5em → mis-centred on is-small inputs. -->
<span class="icon is-right"><i class="fa fa-times"></i></span>
```

```scss
// ✅ Render the glyph as a bare child (a real <button>, no .icon wrapper) so
//    Bulma's descendant rule has nothing to match, then own the positioning —
//    centre it the way Bulma centres the native <select> arrow (the proven
//    recipe in the same framework), NOT the has-icons-right .icon box:
.c-search-input__clear {
  position: absolute;
  top: 50%;                 // ← select-arrow recipe (top:50% + translateY),
  right: 0.625em;           //    NOT the .icon box (top:0 / height:2.5em)
  transform: translateY(-50%);
}
```

Two transferable rules:

1. **Don't reuse a framework's auto-positioned helper class on a child you intend to position yourself** — the framework's descendant selector wins the cascade and you'll fight `!important`-adjacent specificity. Render bare and scope your own rule.
2. **When you do need to centre something the framework also centres elsewhere, copy the framework's *working* recipe for that case**, not a superficially-similar one. Bulma centres the native `<select>` arrow with `top:50% + translateY(-50%)` and the `has-icons-right .icon` with a fixed-height box; the former is the right donor for a vertically-centred affordance, the latter mis-centres at small sizes. The two look interchangeable until you test `is-small`.

This generalises beyond Bulma: any utility-CSS framework with "container class styles its known children" semantics (the icon-in-input, addon-in-field, media-object patterns) has the same trap for a cotton primitive that injects its own children into that container.

## A structural element that is itself an `hx-target` must persist even when empty — gate the empty-state OUTSIDE the primitive

A refinement of *caller-decides-visibility* (see § *Slot truthiness* and § *Empty-state belongs INSIDE the slot*) for the case where the swap target is a **structural element the primitive owns**, not a list-wrapper div. A table primitive that emits `<table><tbody>{{ slot }}</tbody></table>` and also lets the caller poll-refresh rows by targeting that `<tbody>` (`hx-target` on the inner `<tbody>`, `hx-swap="innerHTML"`) hits a hazard: if the primitive swaps the **whole** `<table>` out for an empty-state when there are zero rows, the poll's `hx-target` (`#…-tbody`) **no longer exists in the DOM**, and every subsequent poll silently no-ops — the list can never repopulate without a full reload.

```django
{# Primitive: empty-state replaces the table when is_empty is truthy #}
{% if is_empty and is_empty|lower != 'false' %}{{ empty_text }}{% else %}<table>…<tbody>{{ slot }}</tbody></table>{% endif %}

{# ✅ Poll-target call-site: keep the empty gate OUTSIDE the primitive,
   force :is_empty="False" so the <table>/<tbody> ALWAYS render,
   and put the "no rows yet" message inside the tbody slot instead. #}
<c-table :is_empty="False" …>
  {% for row in rows %}<tr>…</tr>{% empty %}<tr><td colspan="N">{% trans "No rows yet." %}</td></tr>{% endfor %}
</c-table>
```

The discipline: a primitive's built-in empty-state (collapse-to-message) is correct for a **filter-driven full-swap** surface (the whole component is the `hx-target`), but **wrong** for a **poll-into-inner-target** surface (a child is the `hx-target`). Same primitive, opposite empty-state placement, decided by *which element the caller targets*. Document both modes in the primitive's prop comment and make the poll mode an explicit `:is_empty="False"` opt-out rather than a silently-fragile default.
