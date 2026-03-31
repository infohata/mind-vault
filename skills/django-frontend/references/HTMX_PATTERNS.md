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

---

**Last Updated**: 2026-01-28