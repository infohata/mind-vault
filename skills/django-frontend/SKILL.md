---
name: django-frontend
description: Django frontend patterns for building modern web interfaces with HTMX, Alpine.js, and Bulma CSS for server-driven interactivity and responsive design.
---

# SKILL: Django Frontend Patterns with HTMX, Alpine.js, and Bulma

## Overview

Production-ready frontend architecture for Django applications using **HTMX** for server-driven interactivity, **Alpine.js** for client-side state management, and **Bulma CSS** for responsive design. This pattern emphasizes progressive enhancement, minimal JavaScript, and server-side rendering with dynamic partial updates.

**Stack:**
- **HTMX** (1.9+): Server-driven AJAX, partial page updates
- **Alpine.js** (3.x): Lightweight reactive components
- **Bulma CSS** (0.9+): CSS-only framework (no JavaScript dependencies)
- **Django Crispy Forms**: Server-side form rendering
- **FontAwesome**: Icon system

**Compatibility:** Django 4.2+, Crispy Forms 2.x+, PostgreSQL/MySQL/SQLite

**Philosophy:** Server renders HTML, HTMX handles interactions, Alpine.js manages component state, Bulma provides styling.

**Integration:** Works seamlessly with [Django skill backend patterns](../django/SKILL.md) for views, forms, and multi-tenancy.

---

## When to Use

**Ideal for:**
- Django projects needing rich interactivity without SPA complexity
- Multi-tenant applications with server-side permission enforcement
- Teams preferring server-side rendering over client-side frameworks
- Projects requiring SEO-friendly, progressively enhanced UIs
- Applications with complex forms and dynamic filtering

**Not ideal for:**
- Real-time collaborative editing (use WebSockets + React/Vue)
- Offline-first applications
- Heavy client-side data processing
- Mobile apps (use native or React Native)

---

## Pattern

### 1. Base Template Architecture

**Base template** (`base.html`) establishes global structure with Alpine.js state and HTMX configuration:

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
    
    <!-- CSS: Bulma + Custom Theme (theme.css may be built from SCSS) -->
    <link rel="stylesheet" href="{% static 'core/css/bulma.min.css' %}">
    <link rel="stylesheet" href="{% static 'core/css/theme.css' %}">
    <link rel="stylesheet" href="{% static 'core/css/fontawesome.min.css' %}">
    
    <!-- JavaScript: Alpine.js (defer), HTMX, utilities -->
    <script src="{% static 'core/js/alpine.min.js' %}" defer></script>
    <script src="{% static 'core/js/htmx.min.js' %}"></script>
    <script src="{% static 'core/js/utils.js' %}"></script>
    <script src="{% static 'core/js/theme.js' %}"></script>
    
    {% block extra_head %}{% endblock %}
</head>
<body class="h-full">
    <div class="min-h-screen">
        <!-- Navigation -->
        <nav class="navbar" role="navigation">
            <!-- Navbar content with Alpine.js mobile menu toggle -->
            <a role="button" class="navbar-burger" 
               @click="mobileMenu = !mobileMenu">
                <span aria-hidden="true"></span>
            </a>
            <div class="navbar-menu" :class="{ 'is-active': mobileMenu }">
                <!-- Menu items -->
            </div>
        </nav>
        
        <!-- Django Messages (converted to Bulma notifications) -->
        {% if messages %}
        <div id="messages-container">
            {% for message in messages %}
            <div class="notification {% if 'success' in message.tags %}is-success{% endif %}">
                <button class="delete" onclick="this.parentElement.remove()"></button>
                {{ message }}
            </div>
            {% endfor %}
        </div>
        {% endif %}
        
        <!-- Main Content -->
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

**Key patterns:**
- Alpine.js `x-data` on `<html>` for global state (theme, mobile menu)
- HTMX loaded globally (no initialization needed)
- CSS variables for theming (light/dark mode)
- Django messages container for server-side notifications

**Theme CSS / SCSS (optional):** Some projects build `theme.css` from SCSS (variables, mixins, component partials, mobile overrides). Edit the relevant partial in `scss/` (e.g. `scss/components/_buttons.scss`, `scss/mobile/_responsive.scss`); run `make build-scss` or `make static` (build-scss + collectstatic) so the compiled CSS is updated. Never edit `theme.css` by hand when SCSS is the source. See project docs (e.g. Frontend UI guide, CSS_PREPROCESSOR_OPTIONS) for structure.

---

### 2. HTMX Partial Template Pattern

**Views return different templates for HTMX requests:**

```python
# views.py
class ArticleListView(ListView):
    model = Article
    template_name = 'kb/article_list.html'
    context_object_name = 'articles'
    paginate_by = 20
    
    def get_template_names(self):
        """Return partial template for HTMX requests."""
        if self.request.headers.get('HX-Request'):
            return ['kb/partials/_article_list.html']
        return super().get_template_names()
    
    def get_queryset(self):
        queryset = super().get_queryset()
        
        # Apply filters from GET params
        category_id = self.request.GET.get('category')
        if category_id:
            queryset = queryset.filter(category_id=category_id)
        
        search_query = self.request.GET.get('q')
        if search_query:
            queryset = queryset.filter(
                Q(title__icontains=search_query) |
                Q(content__icontains=search_query)
            )
        
        return queryset.order_by('-created_at')
```

**Full page template** (`article_list.html`):

```django
{% extends 'core/base.html' %}
{% load static %}

{% block extra_head %}
<script src="{% static 'kb/js/article-filters.js' %}"></script>
{% endblock %}

{% block content %}
<div id="article-list-container">
    <!-- Page Header -->
    <header class="level">
        <div class="level-left">
            <h1>Articles</h1>
        </div>
        <div class="level-right">
            <a href="{% url 'kb:article_create' %}" class="button is-primary">
                <span class="icon"><i class="fas fa-plus"></i></span>
                <span>New Article</span>
            </a>
        </div>
    </header>
    
    <!-- Filters (HTMX form) -->
    <form id="article-filters" 
          method="get" 
          hx-get="{% url 'kb:article_list' %}" 
          hx-target="#article-list" 
          hx-swap="innerHTML">
        <div class="field">
            <label class="label">Category</label>
            <div class="select">
                <select name="category">
                    <option value="">All Categories</option>
                    {% for category in categories %}
                    <option value="{{ category.id }}">{{ category.name }}</option>
                    {% endfor %}
                </select>
            </div>
        </div>
        
        <div class="field">
            <label class="label">Search</label>
            <input class="input" type="text" name="q" placeholder="Search articles...">
        </div>
        
        <button type="submit" class="button is-primary">Apply Filters</button>
    </form>
    
    <!-- Article List (swapped by HTMX) -->
    <div id="article-list">
        {% include 'kb/partials/_article_list.html' %}
    </div>
</div>
{% endblock %}
```

**Partial template** (`partials/_article_list.html`):

```django
{% load static %}

<div class="articles-grid">
    {% if articles %}
        {% for article in articles %}
            {% include 'kb/partials/_article_card.html' %}
        {% endfor %}
        
        <!-- Pagination -->
        {% if is_paginated %}
        <nav class="pagination">
            {% if page_obj.has_previous %}
            <a href="?page={{ page_obj.previous_page_number }}" class="pagination-previous">Previous</a>
            {% endif %}
            {% if page_obj.has_next %}
            <a href="?page={{ page_obj.next_page_number }}" class="pagination-next">Next</a>
            {% endif %}
        </nav>
        {% endif %}
    {% else %}
        <div class="has-text-centered py-6">
            <p class="has-text-grey">No articles yet</p>
        </div>
    {% endif %}
</div>
```

**JavaScript for auto-submit filters** (`article-filters.js`):

```javascript
document.addEventListener('DOMContentLoaded', function() {
    const filterForm = document.getElementById('article-filters');
    
    if (filterForm) {
        // Prevent default form submission - let HTMX handle it
        filterForm.addEventListener('submit', function(event) {
            event.preventDefault();
        });
        
        const selects = filterForm.querySelectorAll('select');
        const inputs = filterForm.querySelectorAll('input[type="text"]');
        
        // Auto-submit on select change
        selects.forEach(select => {
            select.addEventListener('change', function() {
                filterForm.dispatchEvent(new Event('submit'));
            });
        });
        
        // Debounced auto-submit on text input
        inputs.forEach(input => {
            input.addEventListener('input', debounce(function() {
                filterForm.dispatchEvent(new Event('submit'));
            }, 500));
        });
    }
});
```

---

### 3. Modal Management with HTMX

**Generic modal template** (`partials/generic_form_modal.html`):

```django
{% load i18n %}
<div id="{{ modal_id|default:'formModal' }}" class="modal">
    <div class="modal-background" onclick="closeModal('{{ modal_id|default:'formModal' }}')"></div>
    <div class="modal-card">
        <header class="modal-card-head">
            <p class="modal-card-title" id="{{ modal_id|default:'formModal' }}-title">Form</p>
            <button class="delete" aria-label="close" 
                    onclick="closeModal('{{ modal_id|default:'formModal' }}')"></button>
        </header>
        <section class="modal-card-body" id="{{ modal_id|default:'formModal' }}-body">
            <!-- Form content loaded here via HTMX -->
        </section>
    </div>
</div>
```

**Modal JavaScript** (`modal.js`):

```javascript
// Assumes getCsrfToken() is available (see ADVANCED_COMPONENTS.md utilities)

/**
 * Opens a modal with HTMX-loaded content
 */
function openModal(url, title, modalId = 'formModal') {
    const modalTitle = document.getElementById(`${modalId}-title`);
    const modalBody = document.getElementById(`${modalId}-body`);
    const modal = document.getElementById(modalId);
    
    if (!modalTitle || !modalBody || !modal) {
        console.error(`Modal elements not found for: ${modalId}`);
        return;
    }
    
    modalTitle.textContent = title;
    modalBody.innerHTML = 'Loading...';
    modal.classList.add('is-active');
    
    fetch(url, {
        headers: { 
            'HX-Request': 'true',
            'X-CSRFToken': getCsrfToken()
        }
    })
    .then(response => {
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.text();
    })
    .then(html => {
        modalBody.innerHTML = html;
        // Re-initialize any widgets in loaded content
        if (window.initColorPickers) window.initColorPickers();
        if (window.initIconPickers) window.initIconPickers();
    })
    .catch(error => {
        console.error('Failed to load modal content:', error);
        modalBody.innerHTML = `<div class="notification is-danger is-light">
            <p>Error loading form. Please try again.</p>
            <p class="is-size-7 mt-2">${error.message}</p>
        </div>`;
    });
}

/**
 * Closes a modal
 */
function closeModal(modalId) {
    if (modalId) {
        const modal = document.getElementById(modalId);
        if (modal) modal.classList.remove('is-active');
    } else {
        // Close all active modals
        document.querySelectorAll('.modal.is-active').forEach(modal => {
            modal.classList.remove('is-active');
        });
    }
}

// Close modal on Escape key
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        document.querySelectorAll('.modal.is-active').forEach(modal => {
            modal.classList.remove('is-active');
        });
    }
});

// Listen for custom events to close modal after successful form submission
document.addEventListener('itemCreated', () => closeModal());
document.addEventListener('itemUpdated', () => closeModal());

// Make functions globally available
window.openModal = openModal;
window.closeModal = closeModal;
```

**Usage in templates:**

```django
<!-- Trigger button -->
<button onclick="openModal('{% url 'kb:tag_create' %}', 'Create Tag')" 
        class="button is-primary">
    New Tag
</button>

<!-- Include modal in page -->
{% include "core/partials/generic_form_modal.html" %}
```

**Modal script loading:** Load `modal.js` in the base template when modals are used project-wide, rather than per-page in `{% block extra_head %}`, to avoid "confirmAction is not defined" when a page includes the modal but forgets the script.

### Confirm-Then-Submit Modal

For actions that need user confirmation before submitting (e.g. "Mark as broken", "Revoke access"), use a shared modal instead of native `confirm()` or `alert()`.

**Pattern:**
- Shared modal partial with configurable title, message, confirm button text
- `confirmAction(url, options)` in `modal.js` — configures form and shows modal
- Form uses HTMX to POST; on success, reload or trigger custom event
- **Critical:** After setting `hx-post` dynamically, call `htmx.process(form)` so HTMX binds to the new URL

**Options:** `{ title, message, confirmText, confirmClass, onSuccess }`

### Formset table (shared partial + JS)

For **modelformsets** (e.g. reminders, profile defaults), use a **shared partial** and one JS module so multiple formsets share the same behaviour:

- **Template contract**: Management form (TOTAL_FORMS, INITIAL_FORMS, MIN/MAX_NUM_FORMS), a `<tbody id="…">`, a `<template id="…">` with one row using Django's `__prefix__` in name/id, and an "Add row" button. Each data row has a single CSS class (e.g. `reminder-row`) for the script to reindex and handle DELETE.
- **JS behaviour**: On "Add", clone template, replace `__prefix__` with current index, append to tbody, increment TOTAL_FORMS. On DELETE for a new row (no pk), remove from DOM and reindex names/ids to 0..n-1; for existing rows leave in DOM (Django will treat as deleted on submit).
- **Backend**: Pass formset, `empty_form_template_id`, `add_button_id`, `table_body_id`, `thead_partial`, `row_partial`, `row_css_class`; optional caption and add_button_text.

**Why**: One implementation for all formset tables; consistent add/remove/reindex; frontend and backend stay in sync via a fixed contract.

### Date/time/duration layout (responsive row)

When a form has **date**, **time**, and **duration** (or similar) in one row, use a single Crispy `Div` with Bulma `columns` and responsive column classes (e.g. `column is-2-widescreen is-full-mobile`) so the three fields are inline on desktop and stack on mobile. Avoid separate full-width rows when they belong together semantically.

### Dynamic hx-* Attributes

HTMX binds event listeners at page load. When you change `hx-post`, `hx-get`, etc. via `setAttribute()`, HTMX does **not** automatically pick up the new values. The form may submit to the wrong URL (e.g. current page) → 405 Method Not Allowed.

**Fix:** Call `htmx.process(element)` after modifying attributes:

```javascript
form.setAttribute('hx-post', url);
if (typeof htmx !== 'undefined') htmx.process(form);
```

### HTMX Headers: Hyphenated Keys in JSON

When building headers for HTMX (e.g. CSRF), use **quoted keys** for hyphenated header names in object literals:

```javascript
// ❌ BAD - X-CSRFToken parsed as X minus CSRFToken (SyntaxError)
JSON.stringify({ X-CSRFToken: value })

// ✅ GOOD
JSON.stringify({ 'X-CSRFToken': value })
```

### Global Single-Submit Locking (HTMX + Standard)

To prevent double-submissions, rapid multi-clicks, or missing spinners without polluting forms with ad-hoc `onsubmit` JS:
**Pattern**: Use a global event listener (e.g. `sync_form_submit.js`) combined with a `.sync-submit-button` CSS class and `data-sync-submit` attributes.
- On submit, script immediately disables the button and injects an `__in-flight-label` (like a spinner).
- Listens to HTMX's `htmx:sendError` and `htmx:responseError` to securely reset the button state back to active on failure.

### Sticky-Navbar Aware Scrolling

When validating forms (both standard and HTMX), scrolling to an error summary using native `element.scrollIntoView()` often hides the error behind sticky or fixed top navigation bars.
**Fix**: Abandon `scrollIntoView()` for validation errors. Calculate the explicit viewport offset and use `window.scrollTo`:
```javascript
const y = errorSummary.getBoundingClientRect().top + window.scrollY - navbarHeightOffset;
window.scrollTo({ top: y, behavior: 'smooth' });
```

### Save-Then-Attach Lifecycle (Complex Forms)

For entities that require complex attachments (files, images, references) alongside standard fields, do **not** try to process attachments simultaneously during the `CreateView`.
**UX Convention**:
- **Create Mode**: Hide attachment dropzones entirely. Display an info notice: "Save this record first to attach files."
- **Edit Mode**: Display the attachment manager.
**Why**: Prevents orphaned uploads on failed submits, simplifies DRF serializer edge-cases, and avoids complex multi-part generic creation bugs.

### Shared "Today" ISO Date Context

Instead of having individual views compute and inject the current date into template context (which drifts or misses tz edges):
**Pattern**: Rely on a globally registered context processor (e.g. `today_iso`) that resolves the exact current date/time based on the user's timezone.
Expose it to frontend scripts via `<script id="today_iso" type="application/json">{{ today_iso }}</script>` or Alpine's `x-data`. This prevents logical bugs where JS "new Date()" ignores server timezone contexts for validation logic.

---

## Template Standards (Bulma)

When building templates with Bulma, follow these conventions for consistency and dark-theme compatibility:

### Buttons
| Role | Class | Example |
|------|-------|---------|
| Primary action | `button is-primary` | Save, Create, Submit |
| Secondary action | `button is-info` | View, Manage |
| Cancel / Back | `button is-light` | Cancel, Go Back |
| Danger | `button is-danger` | Delete |
| Edit (header) | `button is-primary` | Edit on detail pages |
| Edit (table row) | `button is-small is-primary` | Edit in table actions |
| Ghost / Menu trigger | `button is-ghost is-small` | Ellipsis dropdowns |

**Never use**: `is-outlined`, `is-text` (use `is-light` for cancel/back).

### Button Icon Pattern
```html
<button class="button is-primary">
    <span class="icon">{% fa_icon "save" %}</span>
    <span>{% trans "Save" %}</span>
</button>
```

### Icons
Always use `{% fa_icon "name" %}` template tag. Exceptions: dynamic Alpine.js `:class` bindings, brand icons (`fab`), dynamic `{{ trigger_icon }}` in navbar submenus.

### Cards
Use `card-content`, never `card-body` (Bootstrap leak). Structure:
```html
<div class="card">
    <div class="card-header">
        <div class="card-header-title">Title</div>
    </div>
    <div class="card-content">...</div>
</div>
```

### Tables in Cards
- Use `table-scroll-container` wrapper, never `table-responsive`
- Table classes: `table is-fullwidth is-hoverable is-striped`
- Always `scope="col"` on `<th>`

### Status Tags
Use Bulma `tag`, never Bootstrap `badge`:
```html
<span class="tag is-success">Active</span>
<span class="tag is-warning">Pending</span>
<span class="tag is-danger">Cancelled</span>
```

### Notifications
Always include `is-light` for dark-theme compatibility:
```html
<div class="notification is-success is-light">...</div>
<div class="notification is-danger is-light">...</div>
```

### Empty States
- Full: `has-text-centered py-6` with icon, heading, subtitle, action button
- Text only: `<p class="has-text-grey">{% trans "No items found." %}</p>`
- Never use `text-muted` (use `has-text-grey`)

### Inline Styles
- `style="display: none;"` is acceptable for JS-toggled elements
- Dynamic CSS custom properties (`--pill-color`, `--tag-color`) are acceptable
- All other styles should be in SCSS files

### i18n
All user-visible text must be wrapped in `{% trans %}` or `{% blocktrans %}`. Template tag arguments (e.g., modal titles passed via `with`) must also be translated.

---

## Why It's Generic

**Applicable across Django projects:**

1. **Framework-agnostic patterns**: HTMX + Alpine.js work with any backend
2. **Django conventions**: Leverages Django's template system, forms, messages
3. **Progressive enhancement**: Works without JavaScript, enhanced with it
4. **Accessibility**: Semantic HTML, ARIA attributes, keyboard navigation
5. **Responsive design**: Bulma's mobile-first approach
6. **Theme flexibility**: CSS variables allow easy customization
7. **Minimal dependencies**: No npm/bundler for core stack; optional SCSS build for theme (`make build-scss`)

**Not project-specific:**
- No business logic in JavaScript
- Reusable widget patterns (autocomplete, color picker, file upload)
- Generic modal/notification systems
- Standard Django view patterns

**Theme build (when SCSS is used):** One optional build step for theme CSS: compile SCSS → `theme.css` (e.g. `python manage.py compile_scss` or `make build-scss`). Run before `collectstatic` when SCSS changes; `make static` often does both. No npm/bundler required for the core stack.

---

## Example Use Cases

**Production usage in Teisutis (multi-tenant knowledge base):**

1. **Article filtering**: HTMX form with auto-submit, debounced search
2. **Tag management**: Modal forms with HTMX, color picker widget
3. **File attachments**: Drag-and-drop upload with Alpine.js state
4. **Category tree**: Nested select with dynamic tag loading
5. **Theme switching**: Light/dark/auto mode with localStorage persistence
6. **Notifications**: JavaScript API matching Django messages framework

**Applicable to:**
- E-commerce product catalogs (filtering, search)
- CMS content management (modals, file uploads)
- SaaS dashboards (notifications, theme switching)
- Admin panels (CRUD operations with HTMX)
- Multi-tenant applications (server-side permission enforcement)

---

## References

**Official Documentation:**
- [HTMX Documentation](https://htmx.org/docs/)
- [Alpine.js Documentation](https://alpinejs.dev/)
- [Bulma CSS Documentation](https://bulma.io/documentation/)
- [Django Crispy Forms](https://django-crispy-forms.readthedocs.io/)

**Related Skills:**
- [Django Skill](../django/SKILL.md) - Backend patterns for views, forms, and multi-tenancy integration
- [Django I18N](../django/references/I18N.md) - Translation workflows, template `{% trans %}`, bulk-fill optimization for .po files
- [Django Multi-Tenant Skill](../django/references/MULTI_TENANT.md) - Schema isolation for multi-tenant frontend apps
- [Django Async WebSocket Skill](../django/references/ASYNC_WEBSOCKET.md) - Real-time features complementing HTMX

**Reference Files:**
- [HTMX Widgets](references/HTMX_WIDGETS.md) - Custom form widgets (autocomplete, file upload, etc.)
- [Advanced Components](references/ADVANCED_COMPONENTS.md) - Theme management, notifications, utilities
- [HTMX Patterns](references/HTMX_PATTERNS.md) - Detailed HTMX implementation patterns

**Key Patterns:**
- **Partial templates**: Different templates for HTMX vs full page requests
- **Widget initialization**: Re-initialize after HTMX swaps (`htmx:afterSwap`)
- **Event-driven architecture**: Custom events for cross-component communication
- **Progressive enhancement**: Server renders HTML, JavaScript enhances
- **CSS variables**: Theme colors/spacing via `:root` and `.dark` (often defined in SCSS `_variables.scss` and compiled to CSS)
- **Theme as SCSS (optional)**: Variables, mixins, component partials (`components/`), mobile overrides (`mobile/`); build with `make build-scss` or `make static` before collectstatic

**Performance Considerations:**
- HTMX reduces JavaScript payload (no SPA framework)
- Server-side rendering improves SEO and initial load
- Debouncing prevents excessive requests
- Lazy loading for modals and autocomplete results

**Security:**
- CSRF protection on all POST/PUT/DELETE requests
- Server-side permission enforcement (never trust client)
- Input validation on both client and server
- XSS protection via Django's template escaping

---

**Last Updated**: 2026-02-26  
**Validated In**: Teisutis (Django 5.2.9, HTMX 1.9, Alpine.js 3.x, Bulma 0.9; theme from SCSS via libsass, `make static`)  
**Template Standards**: Aligned with Teisutis Template Consistency Audit (docs/artefacts/by-agent/curator/TEMPLATE_CONSISTENCY_AUDIT.md)  
**Pattern Type**: Frontend Architecture  
**Complexity**: Intermediate to Advanced