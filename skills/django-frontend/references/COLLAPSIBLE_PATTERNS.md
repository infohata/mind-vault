# Collapsible primitive patterns — native `<details>` + lazy-load buckets

Two related patterns for surfaces with disclosure widgets that may carry expensive content:

1. **Native `<details>` defragilization** — when an Alpine state-machine collapsible accumulates open/loaded/persist/transition coordination bugs, refactor to native `<details>` + `<summary>` and shrink JS to two event-driven concerns.
2. **Lazy-load bucket recipe** — for surfaces with multiple buckets (urgent / upcoming / past, etc.) where the user usually only interacts with one bucket: eager-render the priority bucket; lazy-fetch the rest on first observed-open, with counts upfront so users see what's hidden before expanding.

The two compose. The recipe in §2 is the canonical consumer pattern for the primitive in §1.

## Pattern 1 — Native `<details>` defragilization

When an Alpine-orchestrated `open` / `loaded` / `persist` / `x-show` / `x-cloak` / `x-transition` / `x-effect` / `$watch('open', …)` coordination accumulates subtle desync bugs (chevron-vs-body, htmx-defer races, x-if vs x-show trade-off, scope-chain bugs inside `x-init` IIFE wrappers), the cleanest fix is **drop Alpine** for that surface. The browser already implements bistable open/close via `<details>` / `<summary>`. Use it.

### When this fires

Symptom cluster — any one of:

- Chevron rotates but body stays hidden (or vice-versa) under specific timing conditions.
- "Loading…" placeholder still visible while the collapsible is closed.
- Filter-form HTMX swap rebinds the cotton; saved-open buckets close, or saved-closed buckets open.
- `x-init` expression-only constraint forces you to write an IIFE; Alpine's reactive `with($data)` scope breaks inside the IIFE's nested arrows.
- "Works the first time, breaks after the consumer re-registers" (see [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 5 for the underlying class).

### When NOT to use native `<details>`

- **Animated transitions more complex than a CSS height tween** (slide-in-from-side, accordion with measured heights). `<details>` doesn't animate the open→close transition natively. Needs a CSS keyframe workaround or a `display: grid` height-trick. For animation-heavy surfaces, the Alpine state machine may be worth the fragility tax.
- **Conditional rendering of the body** (different markup when open vs closed). `<details>` keeps the body in the DOM either way — CSS hides it via `details:not([open])`. If you need the body to be absent from the DOM when closed (memory pressure, expensive Alpine components inside), stay with Alpine `x-if`.

### Markup contract

```django
<details class="c-collapsible{% if severity %} c-collapsible--{{ severity }}{% endif %}"
         id="{{ id }}"
         data-c-collapsible
         {% if persist_key %}data-c-collapsible-persist-key="{{ persist_key }}"{% endif %}
         {% if lazy_fetch_url %}
         data-c-collapsible-lazy-fetch-url="{{ lazy_fetch_url }}"
         data-c-collapsible-body-content-id="{{ id }}-body-content"
         {% endif %}
         {% if expanded %}open{% endif %}>
    <summary class="c-collapsible__trigger">
        <span class="c-collapsible__chevron" aria-hidden="true">
            <i class="fas fa-chevron-right"></i>
        </span>
        <span class="c-collapsible__summary">{{ summary }}</span>
        <span class="sr-only c-collapsible__sr-label-closed">{% trans 'Show details' %}</span>
        <span class="sr-only c-collapsible__sr-label-open">{% trans 'Hide details' %}</span>
    </summary>
    <div class="c-collapsible__body" id="{{ id }}-body">
        <div class="c-collapsible__body-content" id="{{ id }}-body-content">
            {% if lazy_fetch_url %}
                <span class="c-collapsible__loading">{{ loading_label }}</span>
            {% else %}
                {{ slot }}
            {% endif %}
        </div>
    </div>
</details>
```

Data attributes only — no Alpine directives. The element is a passive carrier of behaviour configuration; JS reads attributes at bootstrap and on swap.

### CSS contract — chevron rotation via attribute selector

```scss
.c-collapsible__chevron {
    transition: transform 0.15s ease-out;
    transform: rotate(0);
}

.c-collapsible[open] > .c-collapsible__trigger > .c-collapsible__chevron {
    transform: rotate(90deg);
}

// Hide the browser's default disclosure triangle.
summary {
    list-style: none;
    cursor: pointer;
}
summary::-webkit-details-marker {
    display: none;
}

// Sr-only label swap — matches the chevron via the same selector.
.c-collapsible:not([open]) .c-collapsible__sr-label-open,
.c-collapsible[open] .c-collapsible__sr-label-closed {
    display: none;
}
```

Both the chevron rotation AND the screen-reader label swap read the same `[open]` attribute. They cannot disagree — the desync class is structurally impossible.

### JS contract — two concerns, one body-level listener each

The browser owns open state. JS owns:

1. **sessionStorage persistence** via the native `toggle` event (fires whenever `details.open` flips, regardless of how — click, keyboard, JS, `open` attribute mutation, `data-` driven init).
2. **First-open lazy fetch** via `htmx.ajax`, gated by a `data-loaded` idempotency flag on the `<details>` element.

```js
// collapsible.js
(function () {
    const PERSIST_PREFIX = 'c-collapsible:';

    function _restoreState(el) {
        const key = el.dataset.cCollapsiblePersistKey;
        if (!key) return;
        const stored = sessionStorage.getItem(PERSIST_PREFIX + key);
        if (stored === 'open') el.open = true;
        else if (stored === 'closed') el.open = false;
        // else: keep server-rendered initial state.
    }

    function _maybeLazyFetch(el) {
        if (!el.open) return;
        if (el.dataset.loaded === '1') return;
        const url = el.dataset.cCollapsibleLazyFetchUrl;
        const targetId = el.dataset.cCollapsibleBodyContentId;
        if (!url || !targetId) return;
        el.dataset.loaded = '1';
        htmx.ajax('GET', url, '#' + targetId);
    }

    function _handleToggle(event) {
        const el = event.target;
        if (!el.matches('details[data-c-collapsible]')) return;
        const key = el.dataset.cCollapsiblePersistKey;
        if (key) {
            sessionStorage.setItem(PERSIST_PREFIX + key, el.open ? 'open' : 'closed');
        }
        _maybeLazyFetch(el);
    }

    function _initAll(root) {
        const els = (root || document).querySelectorAll('details[data-c-collapsible]');
        els.forEach((el) => {
            _restoreState(el);
            _maybeLazyFetch(el);                  // for elements that init `open`
        });
    }

    document.body.addEventListener('toggle', _handleToggle, true);   // capture phase
    document.addEventListener('DOMContentLoaded', () => _initAll());
    document.body.addEventListener('htmx:afterSwap', (e) => _initAll(e.target));
    document.body.addEventListener('htmx:load', (e) => _initAll(e.target));
}());
```

Three load-bearing details:

- **`toggle` listener uses capture phase**. The toggle event does not bubble — it's a single-element event. Capture is the only way to catch it via a single document-level listener; alternative is per-element listeners which leak across HTMX swaps.
- **`_initAll` is idempotent**. Cold-start, htmx-afterSwap, and htmx:load all call it on the same elements without harm. `data-loaded="1"` prevents the lazy fetch from re-firing; `_restoreState` is a no-op when state already matches.
- **Both `htmx:afterSwap` and `htmx:load` fire `_initAll`**. Different HTMX versions and different swap modes dispatch one or the other (or both); listening to both is idempotent under the `data-loaded` guard but covers every cross-version path. See [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 3 for the rationale.

### Properties newly impossible (the defragilization payoff)

- **Chevron-vs-body desync** — both read the same `[open]` attribute; can't disagree.
- **"Loading visible while collapsed"** — browser hides body via `details:not([open])`, CSS-only. No Alpine race.
- **Stale Alpine reactive state after swap** — no Alpine state to be stale.
- **htmx-defer race for `x-effect`** — no `x-effect`; lazy fetch fires from the `toggle` listener after `htmx` is loaded (DOMContentLoaded gates initial fetch).
- **Multi-toggle race conditions** — the `toggle` event fires synchronously on each open/close; `data-loaded="1"` idempotency is bulletproof regardless of click rate.

### Properties preserved from the Alpine version

- sessionStorage persistence with cold-start restore.
- Lazy fetch on first open + caching across collapse/expand cycles (browser keeps content in DOM after the first fetch).
- Hash deeplink — `if (window.location.hash === '#' + details.id) details.open = true;` in cold-start works the same.
- Severity / variant modifiers (`--danger`, `--warning`, `--boxed`).

## Pattern 2 — Lazy-load bucket recipe

For surfaces with multiple buckets where the user usually only interacts with one bucket on each visit (urgent / upcoming / past events, unread / read / archived messages, today / this-week / this-month tasks), rendering all buckets eagerly is wasteful — every bucket pays for prefetches, virtual expansion, ORM evaluation, even when 90 % of the bucket bodies will never be looked at.

### The recipe

1. **Eager-render the priority bucket** (usually "urgent" / "today" / "unread"). Inline the body slot in the `<c-collapsible>`:

   ```django
   {% with urgent_html=render_event_bucket request filters 'urgent' %}
   <c-collapsible id="event-bucket-urgent"
                  :expanded="True"
                  summary="{{ counts.urgent }} {% trans 'overdue & today' %}">
       {{ urgent_html|safe }}
   </c-collapsible>
   {% endwith %}
   ```

2. **Lazy-fetch the rest** via the cotton's `:lazy_fetch_url` prop:

   ```django
   <c-collapsible id="event-bucket-upcoming"
                  :expanded="False"
                  summary="{{ counts.upcoming }} {% trans 'upcoming' %}"
                  lazy_fetch_url="{% url 'events:bucket' bucket='upcoming' %}?limit=10" />

   <c-collapsible id="event-bucket-past"
                  :expanded="False"
                  summary="{{ counts.past }} {% trans 'past' %}"
                  lazy_fetch_url="{% url 'events:bucket' bucket='past' %}?limit=10" />
   ```

   The cotton consumes the prop via the `data-c-collapsible-lazy-fetch-url` attribute (Pattern 1's contract). First observed-open triggers `htmx.ajax`. Idempotent — reopening reuses cached content.

3. **Counts upfront** so the user sees what's behind each collapsed bucket before deciding to expand:

   ```python
   counts = {
       'urgent': Event.objects.filter(filters_q & urgent_q).count(),
       'upcoming': Event.objects.filter(filters_q & upcoming_q).count(),
       'past': Event.objects.filter(filters_q & past_q).count(),
   }
   ```

   These are cheap `COUNT(*)` queries — three round-trips, no row hydration, no prefetch. The counts let the user decide "no, I don't need to see 437 past events" without paying for the body fetch.

4. **Explicit `?limit=N`** in every lazy-fetch URL. Without it, a tenant with 10 000 past events dumps them all on first expand. Constant `_DEFAULT_BUCKET_LIMIT = 10` per surface, with per-bucket load-more (`?offset=N&limit=M`) for users who want more.

### Render-fn signature — one function, three consumers

The bucket renderer is a plain Django callable used by three different request paths:

```python
def render_event_bucket(request, filters, bucket: str) -> str:
    """Render one bucket's HTML.

    Three consumers:
    1. The eager urgent embed in the parent list view (calls with bucket='urgent').
    2. The lazy-fetch endpoint on first observed-open (calls with bucket='upcoming' | 'past').
    3. The per-bucket load-more endpoint when the user paginates within a bucket.
    """
    limit = int(request.GET.get('limit', _DEFAULT_BUCKET_LIMIT))
    offset = int(request.GET.get('offset', 0))
    events = _query_bucket(filters, bucket).order_by(...)[offset:offset + limit]
    return render_to_string('events/_bucket_body.html', {
        'events': events,
        'bucket': bucket,
        'has_more': events.count() == limit,
    }, request=request)
```

One function, three callers — the kwargs-vs-sibling-fn decision is settled by the request shape (`bucket` is a string param, fits naturally; `request` carries `?limit=` / `?offset=`). New buckets add one branch in `_query_bucket`; no new endpoints.

### Why this composes

Pattern 2 (lazy buckets) sits on top of Pattern 1 (native `<details>`) cleanly because:

- The lazy fetch fires from the `toggle` event, which fires uniformly whether the user clicked the summary, the chevron, used keyboard navigation, or the cotton initialised with `open` attribute set.
- The `data-loaded` idempotency flag means a user who collapses + re-expands doesn't re-fetch — content stays in DOM, CSS just toggles visibility.
- The cotton's `:expanded="True"` for the urgent bucket sets the `open` attribute server-side; lazy fetch fires once at DOMContentLoaded; the body is in place before the user can scroll to it.
- Filter-form HTMX swap re-renders the whole cotton; the bootstrap on `htmx:afterSwap` reapplies persisted state per-bucket from sessionStorage; users' "I prefer past expanded" preference survives across filter changes.

### Reusable for any multi-bucket surface

- Dashboards with urgent / next / scheduled widgets.
- Inboxes with unread / read / archived.
- Task lists with today / this-week / this-month / done.
- Notification panels with system / app / user.
- AI chat history with recent / this-week / older.

The cotton + render-fn-sibling combo is generic across any surface where rendering all buckets eagerly is wasteful and bucket-level counts are cheap.

## Reference

- Pattern 1's `toggle`-based lazy fetch supersedes the `x-effect`-driven lazy-fetch pattern in [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 5 — that section's `x-effect="if (open && !loaded) { … }"` was the workaround when Alpine owned the open state. With native `<details>`, the `toggle` event is the right hook.
- Pattern 2's render-fn signature follows the same render-fn convention used elsewhere in this skill for cotton-consuming view functions — `(request, filters, …extra)` keeps the signature stable across surfaces.

**Last Updated**: 2026-05-14
