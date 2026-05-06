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

❌ DON'T: import vendor CSS via `@import url(...)` from compiled SCSS. Browser resolves relative URLs against the compiled CSS file's URL at runtime — if the compiled CSS path moves (e.g. an app rename like `teisutis_core` → `teisutis_ui`), the import 404s. Link vendor CSS via a sibling `<link>` in `base.html` instead, and let SCSS only handle theme + component styles. Full hazard write-up in [`../SKILL.md`](../SKILL.md) § *SCSS vendor-import hazard — `@import url()` is runtime, not compile-time*.

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
