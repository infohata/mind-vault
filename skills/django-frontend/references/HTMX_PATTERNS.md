# HTMX Patterns: Advanced Implementation Techniques

Detailed HTMX implementation patterns for complex interactions, error handling, and performance optimization in Django applications.

## Form Validation & Error Handling

**Server-side validation with HTMX error display:**

```python
# views.py
class ArticleCreateView(CreateView):
    model = Article
    form_class = ArticleForm
    template_name = 'kb/article_form.html'
    
    def form_invalid(self, form):
        """Return form with errors for HTMX requests."""
        if self.request.headers.get('HX-Request'):
            return render(self.request, 'kb/partials/_article_form.html', {
                'form': form,
                'article': None
            })
        return super().form_invalid(form)
    
    def form_valid(self, form):
        article = form.save()
        if self.request.headers.get('HX-Request'):
            # Return success response for HTMX
            return render(self.request, 'kb/partials/_article_success.html', {
                'article': article
            })
        return super().form_valid(form)
```

**Form template with HTMX error handling:**

```django
<!-- _article_form.html -->
<form hx-post="{% url 'kb:article_create' %}"
      hx-target="this"
      hx-swap="outerHTML"
      enctype="multipart/form-data">
    {% csrf_token %}
    
    <div class="field">
        <label class="label">Title</label>
        <div class="control">
            {{ form.title }}
        </div>
        {% if form.title.errors %}
        <p class="help is-danger">{{ form.title.errors.0 }}</p>
        {% endif %}
    </div>
    
    <div class="field">
        <label class="label">Content</label>
        <div class="control">
            {{ form.content }}
        </div>
        {% if form.content.errors %}
        <p class="help is-danger">{{ form.content.errors.0 }}</p>
        {% endif %}
    </div>
    
    <div class="field">
        <div class="control">
            <button type="submit" class="button is-primary">Create Article</button>
        </div>
    </div>
</form>
```

**Success response template:**

```django
<!-- _article_success.html -->
<div class="notification is-success">
    <button class="delete"></button>
    Article "{{ article.title }}" created successfully!
    <br>
    <a href="{% url 'kb:article_detail' article.pk %}">View Article</a>
</div>

<script>
// Close modal and refresh list
document.dispatchEvent(new CustomEvent('itemCreated'));
if (window.htmx) {
    htmx.ajax('GET', '{% url 'kb:article_list' %}', {
        target: '#article-list',
        swap: 'innerHTML'
    });
}
</script>
```

## Progressive Enhancement Patterns

**HTMX-only interactions with fallback:**

```django
<!-- Enhanced button with HTMX -->
<button hx-get="{% url 'api:like_article' article.id %}"
        hx-target="this"
        hx-swap="outerHTML"
        class="like-button {% if user_has_liked %}liked{% endif %}">
    <span class="icon">
        <i class="fas fa-heart"></i>
    </span>
    <span class="count">{{ article.likes_count }}</span>
</button>

<!-- Fallback form (hidden by CSS when JS enabled) -->
<form method="post" action="{% url 'articles:like' article.id %}" class="fallback-like">
    {% csrf_token %}
    <button type="submit" class="button is-small">
        {% if user_has_liked %}Unlike{% else %}Like{% endif %}
    </button>
</form>

<style>
/* Hide fallback when HTMX is available */
.htmx-request .fallback-like { display: none; }
/* Show fallback when HTMX not available */
.no-htmx .like-button { display: none; }
</style>

<script>
// Detect HTMX availability
document.addEventListener('DOMContentLoaded', function() {
    if (typeof htmx === 'undefined') {
        document.documentElement.classList.add('no-htmx');
    } else {
        document.documentElement.classList.add('htmx-request');
    }
});
</script>
```

## Loading States & Indicators

**Duplicate Submit Prevention (`data-sync-submit` Pattern):**

Project-wide standard to block duplicate POST requests on sensitive forms (full-page or HTMX modals) via race conditions/double clicks. Hooked to the centralized `sync_form_submit.js` delegation script.

```django
<form hx-post="{% url 'billing:checkout' %}"
      hx-target="this"
      hx-swap="outerHTML"
      data-sync-submit>
    {% csrf_token %}
    
    <!-- Form fields -->
    
    <div class="field mt-4">
        <div class="control buttons">
            <button type="submit" class="button is-primary sync-submit-button">
                <span class="__idle">Pay Now</span>
                <span class="__in-flight-label">Processing...</span>
            </button>
            <!-- Any cancel button inside the form must be protected from triggering the lock -->
            <button type="button" class="button is-ghost" data-sync-submit-cancel>Cancel</button>
        </div>
    </div>
</form>
```

**Key Mechanics**:
- `data-sync-submit` on `<form>`: JS intercepts submit, disables button, swaps label, prevents further events.
- `.sync-submit-button`: Scoped element containing `.__idle` and `.__in-flight-label` nested spans for animations via `_forms.scss`.
- `data-sync-submit-cancel`: Allows user cancellation without triggering the submit lock wrapper behavior.
- Automatic Error Recovery: If an HTMX validation fails (`htmx:responseError` or `htmx:sendError`), the central JS delegation logic automatically **un-locks** the button to allow retries. No custom JS per form needed.

**Automatic loading indicators:**

```django
<!-- Button with loading state -->
<button hx-post="{% url 'kb:article_publish' article.id %}"
        hx-indicator="#publish-indicator"
        class="button is-primary">
    <span>Publish Article</span>
    <span id="publish-indicator" class="htmx-indicator">
        <span class="icon">
            <i class="fas fa-spinner fa-spin"></i>
        </span>
        Publishing...
    </span>
</button>

<!-- CSS for indicators -->
<style>
.htmx-indicator { display: none; }
.htmx-request .htmx-indicator { display: inline; }
.htmx-request.htmx-indicator { display: inline; }
</style>
```

**Custom loading overlay:**

```django
<div hx-get="{% url 'kb:articles' %}"
     hx-trigger="revealed"
     hx-target="#articles-container"
     hx-swap="innerHTML">
    
    <!-- Loading template -->
    <div class="loading-template">
        <div class="skeleton-loader">
            <div class="skeleton skeleton-text"></div>
            <div class="skeleton skeleton-text short"></div>
            <div class="skeleton skeleton-button"></div>
        </div>
    </div>
</div>

<style>
.skeleton {
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    animation: skeleton-loading 1.5s infinite;
}

.skeleton-text { height: 1rem; margin-bottom: 0.5rem; }
.skeleton-button { height: 2rem; width: 100px; border-radius: 4px; }

@keyframes skeleton-loading {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
}
</style>
```

## Infinite Scroll & Pagination

**HTMX infinite scroll:**

```django
<!-- Articles list with infinite scroll -->
<div id="articles-container">
    {% include 'kb/partials/_article_list.html' %}
    
    <!-- Next page trigger -->
    {% if page_obj.has_next %}
    <div hx-get="?page={{ page_obj.next_page_number }}"
         hx-trigger="revealed"
         hx-target="#articles-container"
         hx-swap="beforeend"
         hx-select="#articles-container > *"
         class="loading-trigger">
        <div class="has-text-centered py-4">
            <span class="icon">
                <i class="fas fa-spinner fa-spin"></i>
            </span>
            Loading more articles...
        </div>
    </div>
    {% endif %}
</div>
```

## Optimistic Updates

**Immediate UI updates with server confirmation:**

```javascript
function toggleFavorite(articleId) {
    const button = document.querySelector(`[data-article-id="${articleId}"]`);
    if (!button) return;
    
    // Optimistic update
    const wasFavorited = button.classList.contains('favorited');
    button.classList.toggle('favorited');
    
    // Update count
    const countEl = button.querySelector('.count');
    if (countEl) {
        const currentCount = parseInt(countEl.textContent);
        countEl.textContent = wasFavorited ? currentCount - 1 : currentCount + 1;
    }
    
    // Send to server
    htmx.ajax('POST', `/api/articles/${articleId}/favorite/`, {
        target: button,
        swap: 'outerHTML',
        values: { csrfmiddlewaretoken: getCsrfToken() }
    })
    .catch(error => {
        // Revert on failure
        button.classList.toggle('favorited');
        if (countEl) {
            countEl.textContent = currentCount;
        }
        showError('Failed to update favorite status');
    });
}
```

## Event-Driven Architecture

**Custom events for component communication:**

```javascript
// Article created event
document.addEventListener('articleCreated', function(event) {
    const article = event.detail.article;
    
    // Refresh article list
    if (window.htmx) {
        htmx.ajax('GET', '/articles/', {
            target: '#article-list',
            swap: 'innerHTML'
        });
    }
    
    // Close modal
    closeModal();
    
    // Show success message
    showSuccess(`Article "${article.title}" created successfully!`);
});

// Trigger from HTMX response
document.addEventListener('htmx:afterSwap', function(event) {
    if (event.detail.successful && event.detail.target.id === 'article-form') {
        // Extract article data from response if needed
        document.dispatchEvent(new CustomEvent('articleCreated', {
            detail: { article: { title: 'New Article' } }
        }));
    }
});
```

## Error Recovery Patterns

**Retry failed requests:**

```javascript
document.addEventListener('htmx:responseError', function(event) {
    const xhr = event.detail.xhr;
    const target = event.detail.target;
    
    // Only retry on 5xx errors
    if (xhr.status >= 500) {
        const retryCount = parseInt(target.dataset.retryCount || '0');
        if (retryCount < 3) {
            target.dataset.retryCount = retryCount + 1;
            
            // Exponential backoff
            const delay = Math.pow(2, retryCount) * 1000;
            setTimeout(() => {
                htmx.trigger(target, 'retry');
            }, delay);
            
            showWarning(`Request failed, retrying in ${delay/1000}s...`);
            return;
        }
    }
    
    showError('Request failed after retries');
});
```

## Performance Optimization

**Request deduplication:**

```javascript
const pendingRequests = new Map();

document.addEventListener('htmx:beforeRequest', function(event) {
    const url = event.detail.requestConfig.path;
    const method = event.detail.requestConfig.verb;
    const key = `${method}:${url}`;
    
    if (pendingRequests.has(key)) {
        // Cancel duplicate request
        event.preventDefault();
        return false;
    }
    
    pendingRequests.set(key, event.detail.requestConfig);
});

document.addEventListener('htmx:afterRequest', function(event) {
    const url = event.detail.requestConfig.path;
    const method = event.detail.requestConfig.verb;
    const key = `${method}:${url}`;
    
    pendingRequests.delete(key);
});
```

---

**Advanced Integration:**
- Combine with Django caching for HTMX responses
- Use HTMX headers for conditional processing
- Implement proper error boundaries
- Monitor HTMX performance with custom events

## Form focus preservation via list-scoped swap

When an HTMX swap target wraps a form input, every keystroke that triggers a hx-fetch swaps the form node — focus drops, IME state lost, caret position lost. `hx-preserve` on the input is fragile; the surrounding form's trigger re-bind around the wholesale swap drops focus regardless.

**Fix**: scope the swap to a sibling element (the result list) that does NOT include the form. Use `hx-target` + `hx-select` to extract the relevant slice from the same fragment endpoint response.

```html
<form hx-get="{% url '...' %}"
      hx-target="#result-list"          <!-- swap target: just the list -->
      hx-select="#result-list"          <!-- which part of response to swap -->
      hx-swap="outerHTML"
      hx-trigger="keyup changed delay:200ms from:input[name='q']">
    <input type="text" name="q" placeholder="..." />
</form>

<ul id="result-list">
    {% for item in items %}…{% endfor %}
</ul>
```

The form/input is never touched across requests; focus + caret + IME state are preserved by structure, not by preservation tricks.

## HX-Trigger: multi-event payload REQUIRES JSON-object form

The HTMX docs are quiet about this — string-shaped multi-event triggers silently mangle when the response passes through any middleware that parses+re-serialises the header:

```python
# ❌ Wrong — middleware sanitisers fail to parse "name1, name2" as two events;
# the WHOLE string becomes a single event name. HTMX dispatches one event
# named 'eventSaved, eventListRefresh'. Per-event listeners never fire.
response['HX-Trigger'] = 'eventSaved, eventListRefresh'

# ✅ Right — JSON object preserves multi-event semantics across middleware passes
import json
response['HX-Trigger'] = json.dumps({
    'eventSaved': True,
    'eventListRefresh': True,
})
```

The diagnostic: open Network → Response Headers, copy the literal `HX-Trigger` string, paste into a `json.loads()` REPL call. If it errors, it's being mangled into a single-event name downstream. The fix is always the JSON-object form.

Single-event triggers (`'articleSaved'`) keep working unchanged — the parser handles the unquoted bare-string case cleanly. The trap is multi-event only.

## Custom event dispatch — fire on the swapped element, not on `document`

Events bubble UP through the DOM, not down. A `document.dispatchEvent(new CustomEvent('refresh'))` does NOT reach listeners bound to `document.body` — body is a descendant of document, the event never propagates down to it.

When dispatching synthetic events to notify widget rebind chains (`htmx:afterSettle`, `htmx:load`, project-specific `entityChanged`-style events), fire on the **swapped element**:

```js
// ❌ Wrong — document.body and descendant listeners miss this entirely
document.dispatchEvent(new CustomEvent('entityChanged', { detail }));

// ✅ Right — fire on the swapped target; bubbles up through body → document.
// Listeners on either body OR document catch the bubble.
swappedEl.dispatchEvent(new CustomEvent('entityChanged', {
    bubbles: true,
    detail,
}));
```

Mirrors HTMX's own dispatch behaviour. See [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 11 for the full bubble-direction explainer.

## Modal scoping — three-gate check on `htmx:beforeSwap` for form-success modal close

A modal that listens for `entityChanged` (or any project-wide success event) to auto-close on form success has a subtle scoping problem: the event fires on every form-save anywhere in the app, not just saves from inside the modal's own form. Naive `body.addEventListener('entityChanged', closeModal)` closes the modal on any sibling action.

The narrow fix isn't "scope the event to the modal" — it's to gate the listener on three independent signals via `htmx:beforeSwap`:

```js
// modal.js — body-level listener with three gates
bodyEl.addEventListener('htmx:beforeSwap', (evt) => {
    // Gate 1: only consider 2xx responses (failures shouldn't close)
    const xhr = evt.detail && evt.detail.xhr;
    if (!xhr) return;
    if (xhr.status < 200 || xhr.status >= 300) return;

    // Gate 2: only consider responses that carry the canonical success signal.
    // Django's form_invalid returns 200 + a re-rendered form-with-errors — status
    // alone is insufficient. The HX-Trigger header is the distinguisher.
    const trigger = xhr.getResponseHeader('HX-Trigger') || '';
    if (trigger.indexOf('"entityChanged"') === -1) return;

    // Gate 3: prevent the form HTML from being swapped INTO the modal body —
    // the modal closes; the swap is unnecessary and would re-render the form.
    evt.detail.shouldSwap = false;

    closeModal();
});
```

The 3-gate composition matters:

1. **Bind on `htmx:beforeSwap`, not `htmx:afterRequest`**: `afterRequest` fires after the form is detached from the DOM during the swap → the event source disappears → listeners that try to walk back to the form get null.
2. **`xhr.status` 2xx is necessary but not sufficient**: Django's default `form_invalid()` returns status 200 + form-with-errors. Without override, status-only gating closes the modal on validation failure. See [`../../django/references/DJANGO_FORM_INVALID_STATUS.md`](../../django/references/DJANGO_FORM_INVALID_STATUS.md) for the override pattern that makes status-only gating safe.
3. **Response `HX-Trigger` header contains the canonical success signal**: the server emits `entityChanged` only on form_valid; absent on form_invalid. The header check is the actual distinguisher.

## Single-event vs multi-event toast dispatch — pick ONE source per flow

When a flow emits `messages.success(request, ...)` AND a JS `HX-Trigger` listener that also calls `uiNotify`, the user sees the toast twice. The fix is at the design level: pick ONE source per flow — see [`SHELL_NOTIFICATIONS.md`](SHELL_NOTIFICATIONS.md) § *Pick ONE source per flow* for the canonical 4-flow table (server `messages.*` / `hx-swap="none"` / server-flash + client post-action with `refreshOnly: true` / pure client-side) and the JS + Python `refreshOnly` code shapes.

## Cotton-wrapped partials + `hx-swap="innerHTML"` produce nested duplicate IDs

When a partial template is migrated to a cotton primitive that emits its own outer `<div id="X">`, AND the page-level template still wraps the include with `<div id="X">{% include partial %}</div>`, AND a filter form does `hx-target="#X" hx-swap="innerHTML"`:

- **Pre-migration**: partial had no outer id. The page wrapper was the single `#X`. `innerHTML` swap was clean.
- **Post-migration**: cotton emits `#X` inside the page's `#X`. The filter response's `#X` div lands INSIDE the existing `#X`, producing nested duplicate IDs after every swap. Each subsequent swap nests another level.

```html
<!-- Before filter swap (already wrong from migration) -->
<div id="article-list">          ← page-level wrapper
  <div id="article-list">        ← cotton-emitted wrapper
    <div id="article-list-items">…</div>
  </div>
</div>

<!-- After one innerHTML swap targeting #article-list (matches page wrapper) -->
<div id="article-list">
  <div id="article-list">        ← swap response's outer
    <div id="article-list">      ← nested again
      …
    </div>
  </div>
</div>
```

**Fix — both worth applying together**:

1. **Drop the page-level wrapper.** The cotton-emitted wrapper is canonical; the page template just includes the partial directly.
2. **Switch the filter form from `innerHTML` to `outerHTML`.** The partial's outer wrapper REPLACES (not nests-into) the prior render. The shell-migrated workspaces already use this shape; legacy non-shell filter forms shipped with `innerHTML` that fit a partial-with-no-outer-id shape.

Either fix alone closes the visible bug; both together close the class. The discipline generalises: **once a partial emits its own outer wrapper, all swap targets pointed at that wrapper switch to `outerHTML`**.

---

**Last Updated**: 2026-05-20