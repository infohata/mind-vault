# Single-source HTMX filter-form trigger

When several filter forms across an app each carry a hand-written `hx-trigger="…"` attribute, the strings **drift**: one form fires on `change` where the others fire on `submit`, one debounces text at `400ms` and another at `500ms`, a newly-added input `type` is wired into some forms but not others. The drift is invisible at author time and surfaces as "search-as-you-type works on the article list but not the FAQ list" — a per-surface inconsistency no single template review catches, because the bug is the *difference between* templates.

Consolidate the trigger string into one source of truth: a module-level constant rendered through a template tag that every filter form references. Adding a new input type, or retuning the debounce, is then a one-line change that propagates to every surface at once.

## The pattern

**1. One constant** in a shared utils module:

```python
# <app>/utils.py
FILTER_FORM_HX_TRIGGER: str = (
    'submit, '
    'change from:select, '
    'change from:input[type=checkbox], '
    'keyup changed delay:400ms from:input[type=text], '
    'keyup changed delay:400ms from:input[type=search]'
)
```

This is a **form-level, event-filtered** trigger (one `hx-trigger` on the `<form>`, not per-input `hx-*`). HTMX's `from:<selector>` modifier scopes each event to matching descendants, so a single form-level trigger covers every child control by type:

- `submit` — the form's own submit (Enter key, the clear-✕ button's programmatic `htmx.trigger(form, 'submit')`, a submit button).
- `change from:select` — every `<select>` (scope/property/category) refilters on selection. No debounce — change is discrete.
- `change from:input[type=checkbox]` — toggle filters (assigned-to-me, unassigned) refilter on toggle.
- `keyup changed delay:400ms from:input[type=text]` and `… from:input[type=search]` — search-as-you-type, debounced. `changed` suppresses fires when the value didn't actually change (arrow keys, modifier keys). **Both `type=text` and `type=search` are listed** so a search field declared as `type="search"` (for the native mobile search keyboard + the webkit affordance) still triggers — listing only `type=text` is the classic drift bug when a field is migrated to `type="search"`.

**2. One template tag** returning the constant, so templates don't import Python:

```python
# <app>/templatetags/<app>_tags.py
@register.simple_tag
def filter_form_trigger() -> str:
    """Return the canonical ``hx-trigger`` string for filter forms (single source of truth)."""
    return FILTER_FORM_HX_TRIGGER
```

(Projects that namespace their template tags will prefix the tag name, e.g. `<app>_filter_form_trigger`.)

**3. Every filter form references it** — no literal trigger strings anywhere:

```django
{% load <app>_tags %}
<form hx-get="…" hx-target="…" hx-trigger="{% filter_form_trigger %}">
  …filters…
</form>
```

## Drift-guard test

The whole point is defeated if a future edit re-introduces a literal `hx-trigger` on one form. Lock it with a test that (a) pins the constant's value, (b) asserts the tag returns it, and (c) **greps every filter-form template for the tag** so a hand-written trigger fails CI:

```python
def test_all_filter_forms_use_the_trigger_tag(self):
    for tpl in FILTER_FORM_TEMPLATES:           # the N partials, enumerated
        src = (TEMPLATE_DIR / tpl).read_text()
        self.assertIn('{% filter_form_trigger %}', src,
                      f"{tpl} hand-wrote its hx-trigger — use the tag")
        self.assertNotRegex(src, r'hx-trigger="(?!\{% filter_form_trigger)',
                             f"{tpl} has a literal hx-trigger string")
```

The enumerated-list + grep is the cheap insurance against the exact regression the consolidation exists to prevent.

## JS double-fire avoidance

If the app also has a JS listener that manually triggers the form on input (e.g. a tag-filter coordinator that calls `trigger()` on text change), it will **double-fire** alongside HTMX's own `keyup` trigger once the form-level trigger covers that input type. The JS must check whether HTMX already handles the type before triggering:

```js
// Read the form's own hx-trigger; if HTMX already fires on this input type,
// the JS listener must NOT also trigger (double-fetch).
var htmxFiresOnText =
    hxTrigger.indexOf('from:input[type=text]') !== -1 ||
    hxTrigger.indexOf('from:input[type=search]') !== -1;   // ← check BOTH, mirroring the constant
function triggerText() { if (!htmxFiresOnText) trigger(); }
```

The `|| type=search` is the JS-side counterpart of the constant's two-line text/search coverage: miss it and migrating a field to `type="search"` silently restores the double-fire.

## The search field's clear-✕ rides the same trigger

A clear-✕ on the search input should clear **only** the search term and refresh the list **carrying every other filter's current value** — not a full-page reload, not a clear-all. Because the trigger is form-level, the clear handler just empties the field and re-submits the form; the in-DOM values of scope/property/category/tags ride along:

```js
// document-delegated — survives HTMX swaps that replace the form
document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('[data-search-clear]');
    if (!btn) return;
    e.preventDefault();
    var input = btn.closest('.c-search-input').querySelector('[data-search-input]');
    if (!input || input.value === '') { input && input.focus(); return; }
    input.value = '';
    input.focus();
    var form = input.closest('form');
    if (window.htmx) window.htmx.trigger(form, 'submit');   // ← 'submit' is in the trigger
    else if (form.requestSubmit) form.requestSubmit();
});
```

Two details that matter:

- **Document-delegated, not bound to the button** — the form (and the ✕) is replaced on every HTMX swap, so a directly-bound listener dies after the first refilter. Delegate from `document` and match `[data-search-clear]`.
- **Visibility is pure CSS, no JS** — hide the ✕ while the field is empty via `input[type="search"]:placeholder-shown ~ .clear { display: none; }`. This requires a non-empty `placeholder` on the input (default one in the component). The ✕ being `display:none` when empty also removes it from the tab order, so it stays keyboard-reachable only when actionable (don't add `tabindex="-1"` — it's a real interactive control; WCAG 2.1.1).

The server side must interpret "form submitted with empty `q`" as *clear the search term* (not *ignore the absent field and keep the old one*). The submit-sentinel pattern that distinguishes a real submit from a session-restore lives in [`SESSION_FILTER_PERSISTENCE.md`](SESSION_FILTER_PERSISTENCE.md) (`_filter_form=1` real-submit marker); empty-`q`-clears is the same family of "absence means cleared, on a real submit only" logic.

## Why this is reusable

Any server-rendered app with HTMX-driven filter forms across multiple list surfaces has this shape — and the drift is silent until a user notices one surface behaves differently. The constant-plus-tag-plus-drift-test trio is the minimum that keeps N forms genuinely uniform. Pair it with a single `<c-search-input>` cotton primitive (one input markup shared verbatim) so neither the trigger *nor* the field markup can drift per surface.
