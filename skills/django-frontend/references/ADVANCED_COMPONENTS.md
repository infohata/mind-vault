# Advanced Components: Theme, Notifications & Utilities

Advanced frontend components that enhance the user experience with theming, notifications, and utility functions. These components integrate with Alpine.js state management and Django backend.

## Theme Management (Light/Dark/Auto)

**CSS Variables-based theming with Alpine.js state and system preference detection:**

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
    if (theme === 'auto' || theme === null) {
        const effectiveTheme = e.matches ? 'dark' : 'light';
        if (effectiveTheme === 'dark') {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
    }
});
```

**CSS Variables**: Theme colors and spacing are defined as CSS custom properties. In projects that use SCSS, these typically live in `_variables.scss` (e.g. `:root` and `.dark` blocks) and are compiled into `theme.css`; do not edit `theme.css` by hand when SCSS is the source. Example output:

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

## Cross-Origin Iframe Cookie Fallback Pattern

**The Problem**: When integrating a Django application into an external website via an `<iframe>` and communicating via `fetch()` (POST requests), returning a 303 Redirect with a `Set-Cookie` header (using `SameSite=Lax` or browser-specific tracking preventions) will drop the cookie if the domains or ports differ significantly. The parent frame drops the cookie, leaving the child iframe unauthenticated or out-of-sync with preferences (like theme or language) when it loads the final URL.

**The Solution**: Do not rely exclusively on the `POST` response's headers. Pass the necessary context forward via a URL token, then proactively inject the context into the HTML of the `GET` view and explicitly evaluate it in the browser.

1. **Pass data in token**: Wrap the data (`user_context`) into a signed JWT or session-backed token and append it to the iframe's redirect `GET` URL (`?token=xyz`).
2. **Hook the GET Request**: The backend view serving the GET request extracts this data and uses it to re-emit `Set-Cookie` headers directly onto the `TemplateResponse`.
3. **Double Coverage Script (Crucial for Theme)**: Because HTMX or CSS loads *before* Alpine initialization, pass the expected state (e.g. `embed_theme`) in the Django template context.
4. **Hard-Apply in `<head>`**: Create an inline JS snippet in `{% block extra_head %}` to forcibly write the preference to `localStorage`, `document.cookie` (for JS APIs), and manipulate the `document.documentElement` structure immediately. This bypasses HTTP cookie policies entirely since it executes natively within the iframe's permitted sandbox.

```django
{% if embed_theme %}
<script>
    (function applyEmbedTheme() {
        var t = "{{ embed_theme|escapejs }}";
        localStorage.setItem('theme', t);
        document.cookie = "teisutis_theme=" + t + "; path=/";
        var isDark = t === 'dark' || (t === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches);
        document.documentElement.classList.toggle('dark', isDark);
        if (t === 'light' || t === 'dark') {
            document.documentElement.setAttribute('data-theme', t);
        } else {
            document.documentElement.removeAttribute('data-theme');
        }
    })();
</script>
{% endif %}
```

## Notification System

**JavaScript API that mirrors Django messages framework:**

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

## Utility Functions

**Essential utility functions for HTMX + Alpine.js applications:**

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

**Debounce Utility:**

```javascript
function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}
```

**HTMX Integration Helpers:**

```javascript
/**
 * Initialize widgets after HTMX content swap
 */
document.addEventListener('htmx:afterSwap', function(event) {
    // Re-initialize autocomplete widgets
    document.querySelectorAll('.autocomplete-input').forEach(input => {
        // Re-bind events if needed
    });
    
    // Re-initialize modal triggers
    document.querySelectorAll('[data-modal-trigger]').forEach(trigger => {
        // Re-bind modal events
    });
});

/**
 * Handle HTMX errors globally
 */
document.addEventListener('htmx:responseError', function(event) {
    console.error('HTMX Error:', event.detail);
    showError('Request failed. Please try again.');
});

/**
 * Show loading state during HTMX requests
 */
document.addEventListener('htmx:beforeRequest', function(event) {
    const target = event.detail.target;
    if (target) {
        target.style.opacity = '0.7';
        target.style.pointerEvents = 'none';
    }
});

document.addEventListener('htmx:afterRequest', function(event) {
    const target = event.detail.target;
    if (target) {
        target.style.opacity = '';
        target.style.pointerEvents = '';
    }
});
```

## Additional Components

**Loading Spinner Component:**

```django
<div x-show="loading" class="loading-overlay">
    <div class="spinner"></div>
    <p x-text="loadingMessage || 'Loading...'"></p>
</div>
```

**Confirm Dialog Component:**

```javascript
function confirmAction(message, action) {
    if (window.confirm(message)) {
        if (typeof action === 'function') {
            action();
        } else if (typeof action === 'string') {
            // Assume HTMX trigger
            htmx.trigger(document.body, action);
        }
    }
}
```

**Toast Notifications (Alternative to Bulma notifications):**

```javascript
function showToast(message, type = 'info', duration = 3000) {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    
    const container = document.getElementById('toast-container') || createToastContainer();
    container.appendChild(toast);
    
    // Animate in
    setTimeout(() => toast.classList.add('show'), 10);
    
    // Auto remove
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

function createToastContainer() {
    const container = document.createElement('div');
    container.id = 'toast-container';
    container.className = 'toast-container';
    document.body.appendChild(container);
    return container;
}
```

---

**Integration Patterns:**
- Components use Alpine.js for reactive state
- HTMX handles server communication
- Django messages integrated with JavaScript notifications
- Theme system uses CSS variables for performance
- Utilities provide consistent UX across components

---

**Performance Notes:**
- Theme changes use CSS variables (no layout recalculations)
- Notifications auto-cleanup to prevent memory leaks
- Utility functions cached for repeated use
- Event listeners use event delegation where possible

---

**Last Updated**: 2026-01-28