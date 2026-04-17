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

**Last Updated**: 2026-04-17
