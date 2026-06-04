# Forms — discoverability index

Entry point for form work across `django` (backend) and `django-frontend` (templates/JS). Use this when a task touches Django form validation, rendering, status codes, file uploads, FK validation, or form-driven HTMX swaps — instead of grepping for "form" across both skills.

## Rendering (template + widget)

- [`FORM_RENDERING_PATTERNS.md`](FORM_RENDERING_PATTERNS.md) — three valid shapes (`{% crispy form %}` / manual `<input class="input">` / bare `{{ form.field }}` with widget-attrs) + the bare-field trap + Django help_text `<p>` vs `<div>` wrapper trap.

## Status + swap (server ↔ HTMX client contract)

- [`../../django/references/FORM_INVALID_STATUS.md`](../../django/references/FORM_INVALID_STATUS.md) — `form_invalid` returns 200 by default; HTMX-aware views need 422 (via `HTMXFormStatusMixin`) OR `HX-Trigger` header gating. Paired client-side `htmx:beforeSwap` listener required to let HTMX swap 422 bodies.

## Validation (Django form internals)

- [`../../django/references/MODELFORM_POST_CLEAN_TRAP.md`](../../django/references/MODELFORM_POST_CLEAN_TRAP.md) — `ModelForm._post_clean()` writes `cleaned_data` INTO `self.instance` during `is_valid()`; reading `instance.field` after that always returns the POST value, defeating change-detection. Fix: snapshot before binding.
- [`../../django/references/TENANT_SCOPED_FK_VALIDATION.md`](../../django/references/TENANT_SCOPED_FK_VALIDATION.md) — multi-tenant FK validate-and-prune helpers walking shared-schema `org_id`-carrying models must filter `org_id=` explicitly; schema routing alone doesn't cover them.

## File uploads

- [`../../django/references/FILEFIELD_MIME_CAPTURE.md`](../../django/references/FILEFIELD_MIME_CAPTURE.md) — `FieldFile.content_type` is always empty (use `self.file.file.content_type`); capture browser MIME at upload + drift-guard `assert` against the canonical set.

## Formsets

- `../django/SKILL.md` § *Formsets with `UniqueConstraint`* — formset-level `clean()` collecting constrained fields from each form's `cleaned_data` to surface duplicates as `ValidationError` instead of `IntegrityError → 500`.
- `SKILL.md` § *Formset tables — shared partial + JS contract* — shared row-partial + JS contract (management form, `__prefix__` template cloning, reindex on delete) across all modelformsets.

## Filter forms (HTMX-driven session-persisted filters)

- [`FILTER_FORM_TRIGGER_SINGLE_SOURCE.md`](FILTER_FORM_TRIGGER_SINGLE_SOURCE.md) — one `FILTER_FORM_HX_TRIGGER` constant + `{% filter_form_trigger %}` tag shared across surfaces; form-level event-filtered trigger; clear-✕ behaviour.
- [`SESSION_FILTER_PERSISTENCE.md`](SESSION_FILTER_PERSISTENCE.md) — per-entity vs cross-entity session split; `_filter_form=1` real-submit sentinel; `CHECKBOX_TOGGLE_KEYS` allowlist for absent-as-unchecked.

## Form state preservation

- [`DRAWER_FORM_STATE_PRESERVATION.md`](DRAWER_FORM_STATE_PRESERVATION.md) — clone-mirror-strip snapshot pipeline for drawer-hosted forms swapped behind preview surfaces.

## Submit ergonomics

- `SKILL.md` § *Sync-submit button* — global listener + `.sync-submit-button` class for double-submit prevention without per-form JS.

## Related (form-adjacent, not strictly form work)

- [`../../django/references/I18N_WORKFLOW.md`](../../django/references/I18N_WORKFLOW.md) § *Always-plural button labels via verb form* — `Add X` form-submit-button convention sidesteps adjective-noun gender agreement in inflected locales.
- [`HTMX_PATTERNS.md`](HTMX_PATTERNS.md) § *Modal scoping* — `HX-Trigger`-gated modal close, the client-side pair of `FORM_INVALID_STATUS`'s Option 2.
