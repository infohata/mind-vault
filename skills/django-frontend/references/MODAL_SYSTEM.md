# Modal System

Companion reference to [`../SKILL.md`](../SKILL.md). HTMX-loaded modals with Bulma styling. API: `openModal`, `closeModal`, `confirmAction`.

## Generic modal partial

```django
{# core/partials/generic_form_modal.html #}
{% load i18n %}
<div id="{{ modal_id|default:'formModal' }}" class="modal">
    <div class="modal-background" onclick="closeModal('{{ modal_id|default:'formModal' }}')"></div>
    <div class="modal-card">
        <header class="modal-card-head">
            <p class="modal-card-title" id="{{ modal_id|default:'formModal' }}-title">Form</p>
            <button class="delete"
                    aria-label="close"
                    onclick="closeModal('{{ modal_id|default:'formModal' }}')"></button>
        </header>
        <section class="modal-card-body" id="{{ modal_id|default:'formModal' }}-body">
            <!-- Form content loaded here via HTMX -->
        </section>
    </div>
</div>
```

Include once in `base.html` so every page can open it:

```django
{% include "core/partials/generic_form_modal.html" %}
```

## `modal.js`

```javascript
// Assumes getCsrfToken() is exported from utils.js

/**
 * Open a modal and load its content from a URL via fetch.
 */
function openModal(url, title, modalId = "formModal") {
    const modalTitle = document.getElementById(`${modalId}-title`);
    const modalBody = document.getElementById(`${modalId}-body`);
    const modal = document.getElementById(modalId);

    if (!modalTitle || !modalBody || !modal) {
        console.error(`Modal elements not found for: ${modalId}`);
        return;
    }

    modalTitle.textContent = title;
    modalBody.innerHTML = "Loading...";
    modal.classList.add("is-active");

    fetch(url, {
        headers: {
            "HX-Request": "true",
            "X-CSRFToken": getCsrfToken(),
        },
    })
        .then((response) => {
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            return response.text();
        })
        .then((html) => {
            modalBody.innerHTML = html;
            // Re-initialise any widgets in the loaded content
            if (window.initColorPickers) window.initColorPickers();
            if (window.initIconPickers) window.initIconPickers();
            // If the loaded HTML has HTMX attributes, bind them
            if (typeof htmx !== "undefined") htmx.process(modalBody);
        })
        .catch((error) => {
            console.error("Failed to load modal content:", error);
            modalBody.innerHTML = `<div class="notification is-danger is-light">
                <p>Error loading form. Please try again.</p>
                <p class="is-size-7 mt-2">${error.message}</p>
            </div>`;
        });
}

/**
 * Close a specific modal, or all active modals if no id given.
 */
function closeModal(modalId) {
    if (modalId) {
        const modal = document.getElementById(modalId);
        if (modal) modal.classList.remove("is-active");
    } else {
        document.querySelectorAll(".modal.is-active").forEach((modal) => {
            modal.classList.remove("is-active");
        });
    }
}

// Escape key closes all active modals
document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
        document.querySelectorAll(".modal.is-active").forEach((modal) => {
            modal.classList.remove("is-active");
        });
    }
});

// Custom events from child forms close the modal after success
document.addEventListener("itemCreated", () => closeModal());
document.addEventListener("itemUpdated", () => closeModal());

// Expose globally
window.openModal = openModal;
window.closeModal = closeModal;
```

## Usage

Trigger button:

```django
<button onclick="openModal('{% url 'kb:tag_create' %}', 'Create Tag')"
        class="button is-primary">
    {% trans "New Tag" %}
</button>
```

After a successful form submission in the modal, dispatch a custom event to close it:

```javascript
// Inside the HTMX success handler of the form inside the modal
document.dispatchEvent(new CustomEvent("itemCreated"));
```

Or via HTMX response header `HX-Trigger: itemCreated`, which HTMX auto-dispatches.

## `confirmAction` — confirm-then-submit modal

For destructive or irreversible actions (mark as broken, revoke access, delete) use a shared confirmation modal instead of native `confirm()` or `alert()`. Consistent UX, i18n-friendly, keyboard-accessible.

```javascript
/**
 * Configure and show a confirmation modal that submits via HTMX on confirm.
 * @param {string} url        POST target
 * @param {object} options
 * @param {string} options.title
 * @param {string} options.message
 * @param {string} options.confirmText     default "Confirm"
 * @param {string} options.confirmClass    default "is-danger"
 * @param {function} options.onSuccess     called on HTMX:afterRequest success
 */
function confirmAction(url, options = {}) {
    const {
        title = "Confirm",
        message = "Are you sure?",
        confirmText = "Confirm",
        confirmClass = "is-danger",
        onSuccess = null,
    } = options;

    const modal = document.getElementById("confirmModal");
    const form = modal.querySelector("form");

    modal.querySelector(".modal-card-title").textContent = title;
    modal.querySelector(".modal-card-body").textContent = message;

    const confirmBtn = modal.querySelector(".confirm-btn");
    confirmBtn.textContent = confirmText;
    confirmBtn.className = `button ${confirmClass} confirm-btn`;

    form.setAttribute("hx-post", url);
    // Critical: after changing hx-post, rebind
    if (typeof htmx !== "undefined") htmx.process(form);

    if (onSuccess) {
        form.addEventListener("htmx:afterRequest", (ev) => {
            if (ev.detail.successful) onSuccess();
        }, { once: true });
    }

    modal.classList.add("is-active");
}
```

Usage:

```django
<button class="button is-danger"
        onclick="confirmAction('{% url 'kb:article_delete' article.pk %}', {
            title: '{% trans "Delete Article" %}',
            message: '{% trans "This cannot be undone." %}',
            confirmText: '{% trans "Delete" %}',
            onSuccess: () => window.location.reload()
        })">
    {% trans "Delete" %}
</button>
```

## Loading location

**`modal.js` belongs in `base.html`**, loaded once globally via `{% block extra_js %}` or a site-wide script tag. Loading it per-page in `{% block extra_head %}` produces `confirmAction is not defined` runtime errors on pages that include the modal partial but forget the script reference.

## Re-initialising widgets after HTMX swap

When HTMX swaps in content containing widgets (autocompletes, colour pickers, etc.), they need re-initialisation — Alpine and HTMX handle their own attributes, but third-party JS widgets do not. Listen for `htmx:afterSwap`:

```javascript
document.body.addEventListener("htmx:afterSwap", (ev) => {
    if (window.initColorPickers) window.initColorPickers();
    if (window.initIconPickers) window.initIconPickers();
});
```
