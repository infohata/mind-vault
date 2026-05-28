# `ModelForm.is_valid()` mutates the bound instance — snapshot detection fields BEFORE bind

**When this fires**: a Django view bound to a `ModelForm` wants to detect whether a specific field changed between submission and current state, typically to trigger side-effect work (cookie set, cache invalidation, audit log, conditional response shape). The natural read order — bind the form, call `is_valid()`, read `instance.field` — silently always returns the POST value, defeating the change-detection logic.

## The trap

```python
def post(self, request):
    form = MyForm(request.POST, instance=request.user)
    if not form.is_valid():
        return self._render_with_errors(form)

    # Looks reasonable — read the SAVED value, compare against cleaned_data.
    language_before = request.user.language
    form.save()
    language = form.cleaned_data['language']
    if language != language_before:
        # Trigger side-effect: cookie set, locale switch, etc.
        return self._response_with_language_switch(language)
    return self._response_normal()
```

`language_before` always equals `cleaned_data['language']`. The change-detection is structurally always False.

## Why

Django's `ModelForm.is_valid()` (via `_post_clean()`) calls `construct_instance(self, self.instance, opts.fields, opts.exclude)`. That function writes every cleaned field's value INTO `self.instance` (which is the same object reference as `request.user` when the view passed `instance=request.user`). The mutation happens BEFORE `is_valid()` returns; by the time the view reads `request.user.language`, it's already the POST value.

[Django source](https://github.com/django/django/blob/main/django/forms/models.py): `BaseModelForm._post_clean` → `construct_instance`. The method exists exactly so `clean_<fieldname>` validators can read clean values across all fields, including the unsaved-yet ones. Useful for validation. Confusing for change-detection.

## Why `form.changed_data` doesn't help either

The instinct is to use `form.changed_data` (which returns field names whose POST value differs from `initial`). Two failure modes:

1. **`form.initial` may be auto-populated by the form's `__init__`**, not by the saved instance. For example, a form with a "smart default" pattern:

   ```python
   class ProfileBasicsForm(BaseModelForm):
       language = forms.ChoiceField(choices=[], required=False, label=_('Language'))

       def __init__(self, *args, **kwargs):
           super().__init__(*args, **kwargs)
           # If user has no saved language, default the dropdown to the request locale
           if self.instance and not self.instance.language and self.request:
               from django.utils import translation
               current = translation.get_language() or settings.LANGUAGE_CODE
               if current and not self.initial.get('language'):
                   self.initial['language'] = current
   ```

   Result: `form.initial['language'] = 'en'` even though `user.language = ''` (saved-empty). POST sends `language='lt'`. `changed_data` says `['language']` — correctly. But POST sends `language='en'` (matching the auto-set initial). `changed_data` says `[]` — wrong; the SAVED value is `''`, the user is making an actual change to `'en'`.

   The form's `initial` is what's displayed in the form; the instance's saved value is something else.

2. **Boolean fields** in particular: an unset BooleanField default `False` plus a POST that doesn't include the field gets `cleaned_data['field'] = False`, matching `initial`. `changed_data` excludes it. But if the user EXPLICITLY unchecked a previously-checked field, the change happened in the database — change-detect says no, change-action says yes.

Both failure modes are subtle. `changed_data` is a UX concept (did the user change what they saw on the form?), not a database-change-detection concept (is the persisted value different from what we're about to write?). The two diverge whenever `form.initial` doesn't equal the saved instance.

## The fix

**Snapshot the field's saved value BEFORE binding the form.** Before constructing `MyForm(request.POST, instance=request.user, …)`, read `request.user.field` and stash it. Then after `form.save()`, read `form.cleaned_data['field']` and compare against the snapshot.

```python
def post(self, request):
    # Snapshot BEFORE the form binds — _post_clean hasn't mutated yet.
    language_before = request.user.language or ''

    form = MyForm(request.POST, instance=request.user)
    if not form.is_valid():
        return self._render_with_errors(form)
    form.save()
    language = form.cleaned_data.get('language', '').strip()
    language_changed = language != language_before

    if language_changed:
        return self._response_with_language_switch(language)
    return self._response_normal()
```

Three pieces:

1. **Read before bind**: `request.user.language` is the saved-DB value.
2. **Capture into a local**: `language_before` lives in the function scope, immune to subsequent instance mutations.
3. **Compare cleaned_data, not changed_data**: `cleaned_data['language']` is the POST value (validated); compare against the snapshot for the database-change signal.

## Where this bites in practice

- **Locale switching** (the IDEA-153-surfacing case): basics-section save detects whether the user changed language; if so, return `HX-Refresh: true` to reload the page in the new locale. The change-detect logic written naively (`if request.user.language != form.cleaned_data['language']`) was always False; the user changed `''` → `'lt'`, the view returned a vanilla 204 + toast, the cookie was set on the response but `<html lang>` never updated until manual refresh. Snapshot-before-bind fixes it.
- **Audit logs** keyed on "what fields actually changed in the database" (not "what the user touched in the form").
- **Cache invalidation**: invalidate user-specific caches when their `is_staff` flips OR their preferences change. Reading `instance.is_staff` after `is_valid()` always shows the new value.
- **Side-effect emails**: send a "your email has been changed" email when `request.user.email` changes. Same trap.
- **Webhooks / signals**: dispatch only when the field actually changed in the database. The `pre_save` / `post_save` signal pair handles this at the model layer, but for view-layer "I want to know HERE in the response, before save", the snapshot is the only safe pattern.

## Adjacent: model-layer `tracker` libraries

For genuinely complex change-detection (multiple fields, dirty-flag propagation, post-save reactive flows), libraries like [`django-model-utils`'s `FieldTracker`](https://django-model-utils.readthedocs.io/en/latest/utilities.html#field-tracker) handle this at the model layer:

```python
class User(AbstractUser):
    language = models.CharField(max_length=10, blank=True)
    tracker = FieldTracker(fields=['language'])

# In save():
if instance.tracker.has_changed('language'):
    # Reliable change-detect using model-level pre-save state capture.
    ...
```

Tracker works because it hooks `post_init` to snapshot field values at instance load time, then compares against current values in `pre_save`. For view-layer change-detection on a single field where you control the bind + save flow, the snapshot-before-bind pattern is sufficient and zero-dependency.

## When this DOESN'T apply

- Forms that aren't bound to an instance (`forms.Form` not `forms.ModelForm`): no `_post_clean` instance mutation; `cleaned_data` is the only source.
- Read-only forms (display-only, no `save()` call): trivially no change happens.
- Single-field detection where the field is set to its current value at `__init__` time and you trust `form.changed_data`: works IF `initial` matches the saved value (which it usually does unless the form has the smart-default pattern shown above).

## Test mechanics

Reproduce the trap in a test:

```python
def test_language_change_detect_with_naive_pattern_returns_no_change(self):
    """Demonstrates the trap — naive pattern returns no change for an actual change."""
    user = User.objects.create_user(language='')
    form = ProfileBasicsForm({'language': 'lt'}, instance=user)
    self.assertTrue(form.is_valid())
    # AT THIS POINT, request.user.language is already 'lt' — instance was mutated.
    self.assertEqual(user.language, 'lt')  # _post_clean did this.
    # The naive "compare instance.field to cleaned_data.field" pattern reads
    # equal here — change-detection fails before save() even fires.

def test_language_change_detect_with_snapshot_pattern_returns_change(self):
    """Demonstrates the fix — snapshot before bind preserves the saved value."""
    user = User.objects.create_user(language='')
    language_before = user.language  # Snapshot BEFORE the form binds.
    form = ProfileBasicsForm({'language': 'lt'}, instance=user)
    self.assertTrue(form.is_valid())
    # user.language is now 'lt' (instance mutated), but language_before='' (local).
    form.save()
    self.assertNotEqual(form.cleaned_data['language'], language_before)
```

## Compound provenance

Surfaced during a Django + HTMX shell-form migration where a locale-switching response branch (return `HX-Refresh` if language changed) failed validation testing. Debug session traced the assertion failure to "form_changed_data is empty, why?" → "_post_clean mutates instance" → fix. The pattern's been latent in Django since at least 1.x — surfaces only when a view tries to use the bound instance for change-detection rather than just saving.

## Related references

- [`FORM_INVALID_STATUS.md`](FORM_INVALID_STATUS.md) — sibling Django form gotcha; complementary (this one is about reading state; that one is about writing the response status).
- [`I18N.md`](I18N.md) — locale handling; the typical caller of language-change-detect logic.
- [`../../django-frontend/references/FORM_RENDERING_PATTERNS.md`](../../django-frontend/references/FORM_RENDERING_PATTERNS.md) — template side of form rendering; this reference handles the view-layer side.
