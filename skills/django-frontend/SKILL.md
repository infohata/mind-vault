# SKILL: Django Frontend Patterns with HTMX, Alpine.js, and Bulma

## Overview

Production-ready frontend architecture for Django applications using **HTMX** for server-driven interactivity, **Alpine.js** for client-side state management, and **Bulma CSS** for responsive design. This pattern emphasizes progressive enhancement, minimal JavaScript, and server-side rendering with dynamic partial updates.

**Stack:**
- **HTMX** (1.9+): Server-driven AJAX, partial page updates
- **Alpine.js** (3.x): Lightweight reactive components
- **Bulma CSS** (0.9+): CSS-only framework (no JavaScript dependencies)
- **Django Crispy Forms**: Server-side form rendering
- **FontAwesome**: Icon system

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
    
    <!-- CSS: Bulma + Custom Theme -->
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

function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}
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
        headers: { 'HX-Request': 'true' }
    })
    .then(response => response.text())
    .then(html => {
        modalBody.innerHTML = html;
        // Re-initialize any widgets in loaded content
        if (window.initColorPickers) window.initColorPickers();
        if (window.initIconPickers) window.initIconPickers();
    })
    .catch(error => {
        console.error('Failed to load modal content:', error);
        modalBody.innerHTML = 'Error loading form. Please try again.';
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

---

### 4. Custom Form Widgets

#### Autocomplete Widget

**Django widget:**

```python
# widgets.py
from django import forms

class AutocompleteWidget(forms.Select):
    template_name = 'widgets/autocomplete.html'
    
    def __init__(self, url, min_chars=2, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.url = url
        self.min_chars = min_chars
    
    def get_context(self, name, value, attrs):
        context = super().get_context(name, value, attrs)
        context['widget']['url'] = self.url
        context['widget']['min_chars'] = self.min_chars
        return context
```

**Widget template** (`widgets/autocomplete.html`):

```django
<div class="autocomplete-container">
    <input type="text" 
           class="input autocomplete-input" 
           placeholder="Type to search..."
           hx-get="{{ widget.url }}"
           hx-trigger="keyup changed delay:300ms"
           hx-target="[data-autocomplete-results='{{ widget.attrs.id }}']"
           data-min-chars="{{ widget.min_chars }}">
    
    <input type="hidden" name="{{ widget.name }}" value="{{ widget.value|default:'' }}">
    
    <div class="autocomplete-results" 
         data-autocomplete-results="{{ widget.attrs.id }}" 
         style="display: none;">
        <!-- Results loaded here via HTMX -->
    </div>
</div>
```

**Autocomplete JavaScript** (`autocomplete.js`):

```javascript
/**
 * Select an autocomplete item
 */
function selectAutocompleteItem(element, value, text) {
    const container = element.closest('.autocomplete-container');
    if (!container) return;
    
    // Update visible input
    const displayInput = container.querySelector('.autocomplete-input');
    if (displayInput) displayInput.value = text;
    
    // Update hidden input
    const hiddenInput = container.querySelector('input[type="hidden"]');
    if (hiddenInput) hiddenInput.value = value;
    
    // Hide results
    const results = container.querySelector('.autocomplete-results');
    if (results) results.style.display = 'none';
}

// Handle HTMX requests - add query parameter
document.addEventListener('htmx:configRequest', function(event) {
    const input = event.detail.elt;
    if (input && input.classList.contains('autocomplete-input')) {
        const minChars = parseInt(input.dataset.minChars || '2');
        const currentValue = input.value || '';
        
        // Cancel if too short
        if (currentValue.length < minChars) {
            event.preventDefault();
            return false;
        }
        
        // Add query parameter
        event.detail.parameters = { q: currentValue };
    }
});

// Show/hide results after HTMX swap
document.addEventListener('htmx:afterSwap', function(event) {
    const target = event.detail.target;
    if (target && target.hasAttribute('data-autocomplete-results')) {
        const items = target.querySelectorAll('.autocomplete-item');
        target.style.display = items.length > 0 ? 'block' : 'none';
    }
});

// Keyboard navigation (Arrow Up/Down, Enter, Escape)
document.addEventListener('keydown', function(event) {
    const input = event.target;
    if (!input || !input.classList.contains('autocomplete-input')) return;
    
    const container = input.closest('.autocomplete-container');
    if (!container) return;
    
    const results = container.querySelector('.autocomplete-results');
    if (!results || results.style.display === 'none') return;
    
    const items = Array.from(results.querySelectorAll('.autocomplete-item:not(.disabled)'));
    if (items.length === 0) return;
    
    let currentIndex = items.findIndex(item => item.classList.contains('is-active'));
    
    if (event.key === 'ArrowDown') {
        event.preventDefault();
        items.forEach(item => item.classList.remove('is-active'));
        currentIndex = (currentIndex + 1) % items.length;
        items[currentIndex].classList.add('is-active');
        items[currentIndex].scrollIntoView({ block: 'nearest' });
    } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        items.forEach(item => item.classList.remove('is-active'));
        currentIndex = currentIndex <= 0 ? items.length - 1 : currentIndex - 1;
        items[currentIndex].classList.add('is-active');
        items[currentIndex].scrollIntoView({ block: 'nearest' });
    } else if (event.key === 'Enter') {
        event.preventDefault();
        const activeItem = items.find(item => item.classList.contains('is-active'));
        if (activeItem) {
            const value = activeItem.dataset.value;
            const text = activeItem.dataset.text || activeItem.textContent.trim();
            selectAutocompleteItem(activeItem, value, text);
        }
    } else if (event.key === 'Escape') {
        event.preventDefault();
        results.style.display = 'none';
    }
});
```

---

### 5. Theme Management (Light/Dark/Auto)

**Theme JavaScript** (`theme.js`):

```javascript
function themeStore() {
    return {
        theme: localStorage.getItem('theme') || 'auto',
        
        init() {
            this.applyTheme();
        },
        
        applyTheme() {
            const effectiveTheme = this.getEffectiveTheme();
            if (effectiveTheme === 'dark') {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
        },
        
        getEffectiveTheme() {
            if (this.theme === 'light') return 'light';
            if (this.theme === 'dark') return 'dark';
            // Auto mode: follow system preference
            return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
        },
        
        setTheme(newTheme) {
            this.theme = newTheme;
            localStorage.setItem('theme', this.theme);
            this.applyTheme();
        },
        
        toggleTheme() {
            // Cycle through: light -> dark -> auto
            if (this.theme === 'light') {
                this.setTheme('dark');
            } else if (this.theme === 'dark') {
                this.setTheme('auto');
            } else {
                this.setTheme('light');
            }
        }
    };
}

// Listen for system theme changes when in auto mode
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
    const theme = localStorage.getItem('theme');
    if (theme === 'auto') {
        const effectiveTheme = e.matches ? 'dark' : 'light';
        if (effectiveTheme === 'dark') {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
    }
});
```

**CSS Variables** (`theme.css`):

```css
:root {
    /* Light theme colors */
    --bg-primary: #F9FAFB;
    --bg-secondary: #FFFFFF;
    --text-primary: #111827;
    --text-secondary: #6B7280;
    --border-light: #E5E7EB;
    --color-primary: #14B8A6;
    --color-primary-hover: #0F9488;
}

/* Dark theme overrides */
.dark {
    --bg-primary: #111827;
    --bg-secondary: #1F2937;
    --text-primary: #F9FAFB;
    --text-secondary: #9CA3AF;
    --border-light: #374151;
    --color-primary: #14B8A6;
    --color-primary-hover: #0F9488;
}

/* Apply variables to elements */
body {
    background-color: var(--bg-primary);
    color: var(--text-primary);
}

.card {
    background-color: var(--bg-secondary);
    border-color: var(--border-light);
}
```

**Theme toggle button:**

```django
<button @click="toggleTheme()" class="button is-ghost">
    <span x-show="theme === 'light'">🌙</span>
    <span x-show="theme === 'dark'">☀️</span>
    <span x-show="theme === 'auto'">🌓</span>
</button>
```

---

### 6. Notification System

**JavaScript API** (`notifications.js`):

```javascript
/**
 * Show a notification message
 */
function showNotification(message, type = 'primary', options = {}) {
    const { autoDismiss = 5000, scrollToTop = true } = options;
    
    const typeClass = {
        'success': 'is-success',
        'error': 'is-danger',
        'warning': 'is-warning',
        'info': 'is-info',
        'primary': 'is-primary'
    }[type] || 'is-primary';
    
    // Get or create messages container
    let container = document.getElementById('messages-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'messages-container';
        const main = document.querySelector('main');
        if (main) {
            main.parentNode.insertBefore(container, main);
        } else {
            document.body.insertBefore(container, document.body.firstChild);
        }
    }
    
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification ${typeClass}`;
    
    // Add delete button
    const deleteButton = document.createElement('button');
    deleteButton.className = 'delete';
    deleteButton.onclick = function() {
        notification.remove();
        if (container.children.length === 0) container.remove();
    };
    
    notification.appendChild(deleteButton);
    notification.appendChild(document.createTextNode(message));
    container.appendChild(notification);
    
    // Auto-dismiss (except errors)
    if (autoDismiss > 0 && type !== 'error') {
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
                if (container.children.length === 0) container.remove();
            }
        }, autoDismiss);
    }
    
    // Scroll to top
    if (scrollToTop) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }
    
    return notification;
}

// Convenience functions
function showSuccess(message, options = {}) {
    return showNotification(message, 'success', options);
}

function showError(message, options = {}) {
    return showNotification(message, 'error', options);
}

function showWarning(message, options = {}) {
    return showNotification(message, 'warning', options);
}

function showInfo(message, options = {}) {
    return showNotification(message, 'info', options);
}

// Make globally available
window.showNotification = showNotification;
window.showSuccess = showSuccess;
window.showError = showError;
window.showWarning = showWarning;
window.showInfo = showInfo;
```

**Usage:**

```javascript
// From JavaScript
showSuccess('Article created successfully!');
showError('Failed to save changes');

// From HTMX response
document.addEventListener('htmx:afterSwap', function(event) {
    if (event.detail.successful) {
        showSuccess('Content updated');
    }
});
```

---

### 7. File Upload with Drag & Drop

**Alpine.js component** (`attachments.js`):

```javascript
function attachmentUpload() {
    return {
        dragging: false,
        uploading: false,
        uploadProgress: 0,
        selectedFiles: [],
        errorMessage: '',
        
        handleFileSelect(event) {
            const files = Array.from(event.target.files || []);
            if (files.length === 0) return;
            
            const validationResult = this.validateFiles(files);
            if (!validationResult.valid) {
                this.errorMessage = validationResult.error;
                event.target.value = '';
                return;
            }
            
            this.selectedFiles.push(...files);
            this.errorMessage = '';
            event.target.value = '';
        },
        
        handleDrop(event) {
            this.dragging = false;
            const files = Array.from(event.dataTransfer.files || []);
            if (files.length === 0) return;
            
            const validationResult = this.validateFiles(files);
            if (!validationResult.valid) {
                this.errorMessage = validationResult.error;
                return;
            }
            
            this.selectedFiles.push(...files);
            this.errorMessage = '';
        },
        
        validateFiles(files) {
            const maxSize = 10 * 1024 * 1024; // 10MB
            const allowedTypes = ['image/jpeg', 'image/png', 'application/pdf'];
            
            for (const file of files) {
                if (file.size > maxSize) {
                    return {
                        valid: false,
                        error: `File "${file.name}" exceeds 10MB limit.`
                    };
                }
                
                if (!allowedTypes.includes(file.type)) {
                    return {
                        valid: false,
                        error: `File "${file.name}" has unsupported type.`
                    };
                }
            }
            
            return { valid: true };
        },
        
        removeFile(index) {
            this.selectedFiles.splice(index, 1);
        },
        
        async handleSubmit(event) {
            event.preventDefault();
            
            if (this.selectedFiles.length === 0) {
                this.errorMessage = 'Please select at least one file.';
                return;
            }
            
            this.uploading = true;
            this.uploadProgress = 0;
            
            const form = event.target;
            const formData = new FormData(form);
            
            for (let i = 0; i < this.selectedFiles.length; i++) {
                const file = this.selectedFiles[i];
                const fileFormData = new FormData();
                
                // Copy hidden fields
                for (const [key, value] of formData.entries()) {
                    if (key !== 'file') {
                        fileFormData.append(key, value);
                    }
                }
                
                fileFormData.append('file', file);
                
                this.uploadProgress = Math.round(((i + 1) / this.selectedFiles.length) * 100);
                
                try {
                    const response = await fetch(form.action, {
                        method: 'POST',
                        body: fileFormData,
                        headers: {
                            'X-CSRFToken': formData.get('csrfmiddlewaretoken'),
                            'HX-Request': 'true'
                        }
                    });
                    
                    if (!response.ok) {
                        throw new Error('Upload failed');
                    }
                } catch (error) {
                    this.uploading = false;
                    this.errorMessage = `Error uploading ${file.name}: ${error.message}`;
                    return;
                }
            }
            
            // All files uploaded successfully
            this.uploading = false;
            this.uploadProgress = 0;
            this.selectedFiles = [];
            
            // Refresh attachments section
            if (window.htmx) {
                htmx.ajax('GET', window.location.href + '?section=attachments', {
                    target: '#attachments-section',
                    swap: 'outerHTML'
                });
            }
        },
        
        formatFileSize(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
        }
    };
}
```

**Template usage:**

```django
<div x-data="attachmentUpload()" class="attachment-upload-zone">
    <form @submit="handleSubmit" id="attachment-upload-form">
        {% csrf_token %}
        
        <!-- Drag & Drop Zone -->
        <div class="file-drop-zone" 
             @dragover.prevent="dragging = true"
             @dragleave.prevent="dragging = false"
             @drop.prevent="handleDrop"
             :class="{ 'is-active': dragging }">
            <p>Drag files here or click to select</p>
            <input type="file" 
                   multiple 
                   @change="handleFileSelect" 
                   style="display: none;" 
                   id="file-input">
            <button type="button" 
                    class="button is-primary" 
                    @click="$el.previousElementSibling.click()">
                Select Files
            </button>
        </div>
        
        <!-- Selected Files List -->
        <div x-show="selectedFiles.length > 0" class="selected-files">
            <template x-for="(file, index) in selectedFiles" :key="index">
                <div class="file-item">
                    <span x-text="file.name"></span>
                    <span x-text="formatFileSize(file.size)"></span>
                    <button type="button" 
                            @click="removeFile(index)" 
                            class="delete"></button>
                </div>
            </template>
        </div>
        
        <!-- Error Message -->
        <div x-show="errorMessage" class="notification is-danger">
            <button class="delete" @click="errorMessage = ''"></button>
            <span x-text="errorMessage"></span>
        </div>
        
        <!-- Upload Progress -->
        <div x-show="uploading" class="progress-container">
            <progress class="progress is-primary" 
                      :value="uploadProgress" 
                      max="100"></progress>
            <span x-text="`${uploadProgress}%`"></span>
        </div>
        
        <!-- Submit Button -->
        <button type="submit" 
                class="button is-primary" 
                :disabled="uploading || selectedFiles.length === 0">
            <span x-show="!uploading">Upload Files</span>
            <span x-show="uploading">Uploading...</span>
        </button>
    </form>
</div>
```

---

### 8. Utility Functions

**CSRF Token Helper** (`utils.js`):

```javascript
/**
 * Get CSRF token from various sources
 */
function getCsrfToken() {
    // Try meta tag first
    const metaTag = document.querySelector('meta[name="csrf-token"]');
    if (metaTag) return metaTag.getAttribute('content');
    
    // Try Django's standard CSRF input
    const csrfInput = document.querySelector('[name="csrfmiddlewaretoken"]');
    if (csrfInput) return csrfInput.value;
    
    // Fallback: get from cookie
    const name = 'csrftoken';
    let cookieValue = null;
    if (document.cookie && document.cookie !== '') {
        const cookies = document.cookie.split(';');
        for (let i = 0; i < cookies.length; i++) {
            const cookie = cookies[i].trim();
            if (cookie.substring(0, name.length + 1) === (name + '=')) {
                cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
                break;
            }
        }
    }
    return cookieValue || '';
}

// Make globally available
window.getCsrfToken = getCsrfToken;
```

---

## Why It's Generic

**Applicable across Django projects:**

1. **Framework-agnostic patterns**: HTMX + Alpine.js work with any backend
2. **Django conventions**: Leverages Django's template system, forms, messages
3. **Progressive enhancement**: Works without JavaScript, enhanced with it
4. **Accessibility**: Semantic HTML, ARIA attributes, keyboard navigation
5. **Responsive design**: Bulma's mobile-first approach
6. **Theme flexibility**: CSS variables allow easy customization
7. **Minimal dependencies**: No build step, no npm, no bundler required

**Not project-specific:**
- No business logic in JavaScript
- Reusable widget patterns (autocomplete, color picker, file upload)
- Generic modal/notification systems
- Standard Django view patterns

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
- [Django Multi-Tenant Skill](../django/references/MULTI_TENANT.md) - Schema isolation for multi-tenant frontend apps
- [Django Async WebSocket Skill](../django/references/ASYNC_WEBSOCKET.md) - Real-time features complementing HTMX

**Key Patterns:**
- **Partial templates**: Different templates for HTMX vs full page requests
- **Widget initialization**: Re-initialize after HTMX swaps (`htmx:afterSwap`)
- **Event-driven architecture**: Custom events for cross-component communication
- **Progressive enhancement**: Server renders HTML, JavaScript enhances
- **CSS variables**: Theme customization without Sass/Less

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

**Last Updated**: 2026-01-28  
**Validated In**: Teisutis (Django 5.2.9, HTMX 1.9, Alpine.js 3.x, Bulma 0.9)  
**Pattern Type**: Frontend Architecture  
**Complexity**: Intermediate to Advanced