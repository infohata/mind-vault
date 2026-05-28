# Form rendering patterns — Bulma chrome, three valid shapes, one trap

**When this fires**: rendering a Django `ModelForm` (or any `Form`) inside a Bulma-themed shell. There are three valid template shapes that each produce correctly-themed output; one hybrid that LOOKS reasonable but produces unstyled native HTML. The hybrid is the recurring offender — surfaces piecemeal across every shell-form migration cohort, gets caught by visual review every time, deserves a single load-bearing reference.

## The three valid shapes + one trap

### Shape A — `{% crispy form %}` (preferred for simple ModelForms)

The default for any ModelForm extending a `BaseModelForm`-style base that wires `crispy-forms` setup in `__init__`. The base sets `self.helper = FormHelper()` + `self.helper.layout = Layout(*self.fields.keys())`, and `crispy-bulma` (the Bulma adapter) renders each field with the full chrome: `<div class="field"><div class="control"><input class="input"></div></div>`, `<div class="select"><select>…</select></div>` for ChoiceField, `<textarea class="textarea">` for Textarea widgets, `<p class="help">` (or `<div class="help">` — see § Help-text wrapper trap) for help_text.

```django
{% load crispy_forms_tags %}
<form method="post" hx-post="…" hx-target="…">
    {% csrf_token %}
    {% if form.errors %}
        <div class="notification is-danger is-light mb-4" role="alert" aria-live="assertive">
            <ul class="mb-0">
                {% for error in form.non_field_errors %}<li>{{ error }}</li>{% endfor %}
                {% for field in form.visible_fields %}
                    {% for error in field.errors %}<li><strong>{{ field.label }}:</strong> {{ error }}</li>{% endfor %}
                {% endfor %}
            </ul>
        </div>
    {% endif %}
    {% crispy form %}
    <div class="buttons mt-4">
        <button type="submit" class="button is-primary">{% trans "Save" %}</button>
    </div>
</form>
```

**Pros**: zero per-widget class maintenance; field-list changes don't require template edits; the helper layout can be tweaked centrally; matches the convention every working sibling form in the project uses.

**Cons**: no per-field template control inside the form area (everything renders uniformly); can't insert custom HTML between fields without breaking the layout to multiple `{% crispy form_subset %}` calls or going to Shape B.

### Shape B — manual `<input class="input">` markup with widget classes baked in

Used when the form has dynamic rows (per-instance permission grids, conditional reveal via Alpine `x-data`, formset table-rows) that don't fit a flat crispy render. Every input MUST explicitly carry the Bulma class via the template, not via the widget — the widget-attrs approach (Shape C below) is fragile to forget.

```django
<div class="field">
    <label class="label" for="{{ form.email.id_for_label }}">
        {% trans "Email" %}
    </label>
    <div class="control">
        <input type="email"
               name="{{ form.email.name }}"
               value="{{ form.email.value|default_if_none:'' }}"
               class="input {% if form.email.errors %}is-danger{% endif %}"
               id="{{ form.email.id_for_label }}"
               required>
    </div>
    {% if form.email.errors %}
        <p class="help is-danger">{{ form.email.errors.0 }}</p>
    {% endif %}
</div>
```

**Pros**: full per-field control; can interleave custom markup; the `class="input"` is explicit + impossible to lose by forgetting widget attrs.

**Cons**: per-field maintenance — every new field needs the wrapper markup; renaming a field on the form requires touching the template.

### Shape C — bare `{{ form.field }}` with widget-attrs class injection

Compromise shape — keep `{{ form.field }}` rendering but inject `class="input"` via the widget `attrs` in the form definition.

```python
# forms.py
class MyForm(BaseModelForm):
    email = forms.EmailField(
        label=_('Email'),
        widget=forms.EmailInput(attrs={'class': 'input'}),  # MANDATORY
    )
    timezone_other = forms.CharField(
        widget=forms.TextInput(attrs={'class': 'input', 'placeholder': '…'}),
    )
    note = forms.CharField(
        widget=forms.Textarea(attrs={'class': 'textarea', 'rows': 4}),
    )
```

```django
<div class="field">
    <label class="label" for="{{ form.email.id_for_label }}">{{ form.email.label }}</label>
    <div class="control">{{ form.email }}</div>
</div>
```

**Pros**: still per-field-controllable from the template (interleaving custom markup OK); widget class is one place in the form, not per-template per-field.

**Cons**: every widget needs the attrs explicitly — forgetting one produces an unstyled native `<input>`. Visual review is the only catcher; tests rarely assert presence of `class="input"`. Verifying coverage across N fields is mechanical but tedious. ChoiceField is the WORST case — `class="select"` on the widget doesn't work; the Bulma `<select>` chrome requires a wrapping `<div class="select">{{ form.field }}</div>`, NOT a class on the `<select>` itself. Shape C doesn't cleanly handle this; you end up with mixed Shape B + Shape C for the same form, which is its own recipe for confusion.

### The trap — bare `{{ form.field }}` WITHOUT widget classes

The hybrid that surfaces over and over: developers write Shape A's wrapper but skip the `{% crispy form %}` step, OR write Shape B's wrapper but render `{{ form.field }}` instead of explicit `<input class="input">`, OR use Shape C semantics but forget the widget attrs.

```django
{# Anti-pattern — produces <input type="text"> with NO class #}
<div class="field">
    <label class="label" for="{{ form.first_name.id_for_label }}">First name</label>
    <div class="control">{{ form.first_name }}</div>
</div>
```

`{{ form.first_name }}` renders to `<input type="text" name="first_name" id="…">` with no class. The `.control` wrapper provides nothing on its own — Bulma's `.control` is a layout helper, not a styling helper. The result: unstyled native HTML elements that visually break the form's appearance.

**Why it survives review**: the template LOOKS correct (Bulma-shaped wrappers around the field). The bug is one level down — the field itself renders unstyled. Developers reviewing the diff see `<div class="field">` + `<div class="control">` + `{{ form.field }}` and assume the chrome is correct. Only a visual render (manual or screenshot test) catches it.

## Help-text wrapper trap (Django framework quirk, not user-author bug)

Django's `PasswordChangeForm.new_password1.help_text` returns `password_validators_help_text_html()` — block-level HTML containing `<ul><li>…</li></ul>`. Some custom widgets do the same. When wrapped in `<p class="help">`:

```django
{# Anti-pattern — invalid HTML; <ul> inside <p> is parser error #}
<p class="help">{{ field.help_text|safe }}</p>
```

The browser's HTML parser implicitly closes `<p>` before `<ul>` and lifts the list outside:

```html
<!-- What the browser actually renders: -->
<p class="help"></p>
<ul><li>Password validator 1</li><li>Password validator 2</li></ul>
```

The empty `<p>` gets hidden by any downstream JS that converts `.field .help` to a tooltip (e.g. `form-help.js` ⓘ-button conversion), but the orphaned `<ul>` remains visible — defeating the tooltip pattern. Symptom: the field shows BOTH a tooltip icon AND a duplicate block of the same help text.

**Fix**: use `<div class="help">` whenever help_text MAY contain block-level HTML.

```django
{# Correct — <ul> is valid inside <div>; .help styling unchanged #}
<div class="help">{{ field.help_text|safe }}</div>
```

Both `<p class="help">` and `<div class="help">` are styled by Bulma's `.help` class identically (the class is the discriminator, not the tag). `<div>` accepts all flow content as children; `<p>` accepts only phrasing content. Block-level help text needs `<div>`.

**Default to `<div class="help">`** for any form rendering Django framework forms (`PasswordChangeForm`, `PasswordResetForm`, admin custom widgets) — even when current help_text is plain text. Future help_text changes may add block content, and pre-emptive `<div>` costs nothing.

## Choosing between shapes

| Form characteristic | Shape |
|---|---|
| Simple `ModelForm`, all fields render uniformly | A (`{% crispy form %}`) |
| Has dynamic rows (per-row permission grid, formset table) | B (manual markup) |
| Has Alpine conditional reveal (`x-data` showing/hiding a field based on another) | B (need template-level conditional) |
| Django framework form you can't change (`PasswordChangeForm`, `PasswordResetForm`) | B (can't add widget attrs to a built-in form without subclassing) |
| Modest form where you want template-level field control but no dynamic logic | C (widget attrs + bare `{{ form.field }}`) |

**When in doubt**: Shape A. It's the default convention across most shell-form migrations; widget-attr maintenance under Shape C scales worse than its perceived flexibility wins.

## Testing the rendered output

The bare-field trap can't be caught by `assertEqual(response.status_code, 200)` or `assertContains(response, 'form-field-name')`. The catchers that DO work:

- **Render-and-assert tests** for cotton primitives that render forms inline — assert `class="input"` / `<div class="select">` / `class="textarea"` presence on each field's output. The IDEA-197-era `c-section-header` test pattern (template engine `from_string` + literal string assertions) is the canonical shape.
- **Visual regression** (Playwright) — for the highest-value forms, take a screenshot of the cold-load + assert via image diff. Catches the bare-field trap without per-field assertions.
- **Manual eval checklist** — final-mile catcher. The user-walked M-walk is what surfaced the trap during the IDEA-153 cycle that produced this reference. Worth keeping in the loop until either render-assert OR visual-regression coverage exists.

## Related references

- [`FORMS_INDEX.md`](FORMS_INDEX.md) — cross-skill form discoverability index.
- [`COTTON.md`](COTTON.md) — cotton primitive authoring (different concern; cotton renders its OWN markup, not Django form fields).
- [`HTMX_PATTERNS.md`](HTMX_PATTERNS.md) — form `hx-post` + `hx-target` shape; orthogonal to field-class concern.
- [`SHELL_NOTIFICATIONS.md`](SHELL_NOTIFICATIONS.md) — `notify()` + toast on save; the OTHER half of "form submitted successfully".
- [`../../django/references/FORM_INVALID_STATUS.md`](../../django/references/FORM_INVALID_STATUS.md) — server-side `form_invalid` status code; complements the client-side rendering covered here.
- [`../../django/references/MODELFORM_POST_CLEAN_TRAP.md`](../../django/references/MODELFORM_POST_CLEAN_TRAP.md) — subtle Django `_post_clean()` mutation that defeats change-detection logic written around `request.user.field` reads.
