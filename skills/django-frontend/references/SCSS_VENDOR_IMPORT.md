# SCSS vendor-import hazard — `@import url()` is runtime, not compile-time

**When this fires**: a Django project compiles SCSS to CSS via libsass / dart-sass / `compile_scss` and serves the result through `collectstatic`. An `@import url('../vendor/bulma.min.css')` inside the SCSS source is **NOT** resolved by Sass at compile time — Sass copies the `@import url(...)` line verbatim into the compiled `.css`; the **browser** resolves the relative URL at runtime, against the COMPILED CSS file's URL. The django-frontend SKILL.md body's SCSS-vendor-import section holds the firing-conditions stub; this reference holds the failure mode + recurrence triggers + fix + detection grep.

## Failure mode

The SCSS source lives at a stable repo path (e.g. `myapp/static/myapp/scss/theme.scss`) and the vendor file sits as a sibling (`myapp/static/myapp/vendor/bulma.min.css`), so during dev with the SCSS importer everything looks fine. After `collectstatic` deploys the compiled `theme.css` somewhere else (the destination depends on the app's static config and `STATIC_ROOT`), the `../vendor/bulma.min.css` relative URL points at a different place than where collectstatic put the vendor file. **Sass compiled cleanly**; the **browser logs a 404** for `bulma.min.css`; the page renders unstyled.

## When this trap recurs

- A Django app is renamed (e.g. `app_core` → `app_ui`) and its compiled CSS file's `STATIC_URL` path shifts
- `STATIC_ROOT` changes between dev and prod
- `collectstatic --no-default-ignore` flags differ between environments
- A sibling app's static directory is reorganised

## The fix — vendor CSS goes in a `<link>` tag, not an SCSS `@import url()`

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

## Worked example

The SCSS lived inside `core` (an app) originally, an IDEA relocated it to `ui` (a new shell app), and the compiled `theme.css`'s URL shifted from `/static/core/css/theme.css` to `/static/ui/css/theme.css`. The `@import url('../css/bulma.min.css')` line in the SCSS pointed at `../css/bulma.min.css` relative to the compiled CSS — now resolving to `/static/ui/css/bulma.min.css`, but `bulma.min.css` was sitting at `/static/core/css/bulma.min.css` (didn't move). Browser 404'd; UI rendered unstyled until the `<link>` migration landed.

## Detection during review

Grep SCSS source for `@import url(`:

```bash
grep -rn '@import url(' --include='*.scss' static/ web/ src/ | grep -v node_modules
```

Any hit is a candidate for migration to a `<link>` tag. The exception is when the imported file is itself part of the same compiled output (i.e. another SCSS partial bundled by Sass) — in that case it's a Sass-time `@use` / `@import` of a sibling source, not a runtime URL fetch, and the syntax is `@import 'partial';` (no `url()`, no extension). The hazard is specifically `@import url(...)`.
