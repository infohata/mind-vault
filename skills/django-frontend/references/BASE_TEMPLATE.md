# Base Template + Theme

Companion reference to [`../SKILL.md`](../SKILL.md). Full `base.html` structure, Alpine theme store, Bulma message-to-notification conversion, and optional SCSS build pipeline.

## Canonical `base.html`

Alpine `x-data` on `<html>` makes theme and mobile-menu state accessible from every descendant without prop drilling:

```django
{% load static i18n %}
<!DOCTYPE html>
<html lang="{{ LANGUAGE_CODE }}"
      x-data="{ ...themeStore(), mobileMenu: false }"
      x-init="init()"
      :class="theme"
      class="h-full">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}App{% endblock %}</title>

    <!-- CSRF token for JavaScript access -->
    <meta name="csrf-token" content="{{ csrf_token }}">

    <!-- CSS: Bulma + theme (may be SCSS-compiled) + FontAwesome -->
    <link rel="stylesheet" href="{% static 'core/css/bulma.min.css' %}">
    <link rel="stylesheet" href="{% static 'core/css/theme.css' %}">
    <link rel="stylesheet" href="{% static 'core/css/fontawesome.min.css' %}">

    <!-- JavaScript: Alpine (defer), HTMX, site utilities, theme store -->
    <script src="{% static 'core/js/alpine.min.js' %}" defer></script>
    <script src="{% static 'core/js/htmx.min.js' %}"></script>
    <script src="{% static 'core/js/utils.js' %}"></script>
    <script src="{% static 'core/js/theme.js' %}"></script>
    <script src="{% static 'core/js/modal.js' %}"></script>

    {% block extra_head %}{% endblock %}
</head>
<body class="h-full">
    <div class="min-h-screen">
        <!-- Navigation with Alpine-driven mobile menu -->
        <nav class="navbar" role="navigation">
            <a role="button"
               class="navbar-burger"
               @click="mobileMenu = !mobileMenu"
               :class="{ 'is-active': mobileMenu }">
                <span aria-hidden="true"></span>
            </a>
            <div class="navbar-menu" :class="{ 'is-active': mobileMenu }">
                <!-- Menu items -->
            </div>
        </nav>

        <!-- Django messages → Bulma notifications -->
        {% if messages %}
        <div id="messages-container">
            {% for message in messages %}
            <div class="notification is-light
                        {% if 'success' in message.tags %}is-success{% endif %}
                        {% if 'error' in message.tags %}is-danger{% endif %}
                        {% if 'warning' in message.tags %}is-warning{% endif %}
                        {% if 'info' in message.tags %}is-info{% endif %}">
                <button class="delete" onclick="this.parentElement.remove()"></button>
                {{ message }}
            </div>
            {% endfor %}
        </div>
        {% endif %}

        <!-- Main content -->
        <main class="main">
            <div class="container">
                {% block content %}{% endblock %}
            </div>
        </main>
    </div>

    {% block extra_js %}{% endblock %}
</body>
</html>
```

## Alpine theme store (`static/core/js/theme.js`)

```javascript
function themeStore() {
    return {
        theme: "light",
        init() {
            const saved = localStorage.getItem("theme");
            if (saved) {
                this.theme = saved;
            } else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
                this.theme = "dark";
            }
        },
        setTheme(next) {
            this.theme = next;
            localStorage.setItem("theme", next);
        },
    };
}
window.themeStore = themeStore;
```

Apply to a toggle button anywhere on the page:

```django
<button class="button is-ghost" @click="setTheme(theme === 'light' ? 'dark' : 'light')">
    <span class="icon" x-show="theme === 'light'">{% fa_icon "moon" %}</span>
    <span class="icon" x-show="theme === 'dark'">{% fa_icon "sun" %}</span>
</button>
```

## Optional SCSS build

When the project uses SCSS to build `theme.css` (variables, mixins, component partials, mobile overrides):

- `scss/_variables.scss` — colours, spacing tokens, breakpoints.
- `scss/components/*.scss` — per-component overrides of Bulma defaults.
- `scss/mobile/*.scss` — responsive overrides.
- `scss/theme.scss` — root import that Bulma's compiler ingests.

Build targets in the Makefile:

```makefile
build-scss:
	docker compose exec web python manage.py compile_scss

static: build-scss
	docker compose exec web python manage.py collectstatic --noinput
```

**Never edit the compiled `theme.css` by hand** — the next SCSS build overwrites it. Edit the partial in `scss/` and rebuild.

When SCSS is not used, `theme.css` is hand-written CSS and lives alongside `bulma.min.css`. Either approach is fine for a typical Django project; the skill body is agnostic.

## CSS variables for theming

Light/dark toggling is driven by `:root` / `.dark` CSS variable sets, which Bulma components reference via `var(--bulma-primary)` etc. Keeping the variables in SCSS partials (or top of `theme.css`) lets designers change the palette without touching component code.

```css
:root {
    --surface: #ffffff;
    --text: #0a0a0a;
    --primary: hsl(171, 100%, 41%);
}

.dark {
    --surface: #0a0a0a;
    --text: #fafafa;
    --primary: hsl(171, 70%, 55%);
}
```

## CSS spec hazards: `min-height` > `max-height` clamp

When you set `max-height: 0` on an element to collapse its layout slot, ANY inherited or framework-default `min-height` greater than 0 will silently defeat the collapse. Per CSS spec ([CSS Box Sizing Module Level 3 § 6.6](https://www.w3.org/TR/css-sizing-3/#min-size-properties)): "If `max-height` is less than `min-height`, max-height is set to min-height."

**Symptom**: layout slot doesn't collapse despite `max-height: 0` in the computed styles. Element disappears visually (via `transform` or `overflow: hidden` + `opacity: 0`) but takes its full reserved height.

**Probe**: in DevTools, check the element's `min-height` computed value. If non-zero, you've hit this trap.

**Fix**: when collapsing via `max-height`, also set `min-height: 0` + `padding-{top,bottom}: 0` + `overflow: hidden`. Apply to the modifier class, not the base — don't break the visible state.

```scss
.navbar.navbar--hidden {
    transform: translateY(-100%);
    min-height: 0;       // override Bulma's 3.25rem min on .navbar
    max-height: 0;
    padding-top: 0;
    padding-bottom: 0;
    overflow: hidden;
}
```

Frameworks that bite this trap by default: Bulma (`.navbar { min-height: 3.25rem }`), Bootstrap (`.navbar { min-height: 56px }` in some themes), any Tailwind config that adds a navbar utility with min-height.

## Theme contrast picker (WCAG luminance)

When picking a foreground colour (`#181818` dark vs `#ffffff` light) against an arbitrary themed background — avatar initials, badge text, alert text on a colour-coded surface — the W3C-correct relative luminance formula requires gamma-decoded RGB values before applying the BT.709 coefficients. Most hand-written shortcuts skip the linearization step and produce wrong contrast picks for medium-tone colours.

**Wrong** (gamma-encoded shortcut):

```python
r, g, b = [c / 255.0 for c in rgb]
luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b   # WRONG — gamma-encoded
return '#181818' if luminance > 0.179 else '#ffffff'
```

**Right** (linearized per W3C spec):

```python
def _linearize(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

r_lin, g_lin, b_lin = [_linearize(c / 255.0) for c in rgb]
luminance = 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
return '#181818' if luminance > 0.179 else '#ffffff'
```

The 0.179 crossover threshold is calibrated against linearized luminance. Without the linearization step, medium-tone backgrounds (`#444`–`#666` range) get wrong-contrast foreground picks — `#555555` returns dark text at ~2.1:1 contrast when WCAG AA requires the white-text pick at ~7.6:1.

Reference: [WCAG 2.1 § Relative luminance](https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).

Implement once as a Django template filter (e.g. `on_color`) and reuse — the computation is a recurring need (avatar foreground, badge foreground, alert text, themed-pill text); each surface re-deriving it tends to drift back toward the shortcut.

---

**Last Updated**: 2026-05-07
