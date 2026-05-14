# Session-keyed filter persistence — per-entity vs cross-entity contract

When designing session-keyed filter persistence for multi-entity workspaces (article list, event list, FAQ list, etc.), split filter keys into **two** sessions and use a form sentinel to distinguish real submits from cross-link nav. Without the split, navigation between entities silently clobbers session state.

## When to use

- A multi-entity workspace where the user moves between "articles", "events", "FAQs", "dashboards", etc.
- Filters need to persist across page navigation (server-side session, not URL).
- Some filters logically describe the user's current focus (scope, property, category) and should ride along between entity views.
- Other filters are entity-specific (tags, free-text search) and shouldn't bleed across.

## When NOT to use

- Single-entity surface — just keep one session bucket.
- Pure-URL filter state (no session) — the cross-link-nav clobber problem doesn't arise.
- Tags-bound-to-scope projects where the entity boundary IS the scope boundary — collapse to one session.

## The split

```python
# project/utils/filter_keys.py
CROSS_ENTITY_FILTER_KEYS: tuple[str, ...] = ('scope', 'property', 'category')
# tags is intentionally NOT cross-entity; q (search) too if applicable.

CROSS_FILTER_SESSION_KEY = 'cross_filters_{org_id}'
PER_ENTITY_FILTER_SESSION_KEY = '{namespace}_{entity}_filters_{org_id}'
# e.g. 'kb_article_filters_42', 'kb_event_filters_42', 'kb_faq_filters_42'
```

- **`cross_filters_<org_id>`** — filters describing the user's working focus (scope, property, category). Survive entity navigation (article → event → article keeps the scope). Tenant-scoped by `org_id` per `RULE_tenant-scoped-fk-validation`.
- **`<namespace>_<entity>_filters_<org_id>`** — entity-specific filters (tags, q). Do NOT survive cross-entity navigation; navigating to a different entity and back clears them.

## Why the split (mental model)

The user's mental model differs by filter type:

- **Scope/property** describe the user's role / focus area. "I'm working on Marketing scope" persists across entity views.
- **Category** describes a logical grouping that's typically scoped (Marketing has its own category tree). Persists for the same reason.
- **Tags** are scope-FK-bound — `Tag` rows reference a `Scope` FK, so an article's tag IDs only mean something within that scope. Crossing entity boundaries OR scope boundaries invalidates them.
- **Text search** (`q`) is a transient input. Carrying "give me everything matching 'Q4'" from articles to events is rarely the user's intent.

## Server-side mechanics

```python
# project/utils/filters.py
def get_effective_filters(request, *, namespace: str, filter_keys: tuple[str, ...]):
    """Merge GET params into the right session bucket; return effective dict.

    Cross-entity keys go to the shared session bucket; entity-specific keys
    go to the namespace-scoped bucket.
    """
    org_id = request.user.org_id
    cross_key = f'cross_filters_{org_id}'
    entity_key = f'{namespace}_{request.resolver_match.url_name}_filters_{org_id}'

    cross_existing = request.session.get(cross_key, {})
    entity_existing = request.session.get(entity_key, {})

    is_real_submit = '_filter_form' in request.GET
    # Capture the OLD scope value BEFORE the merge loop. The loop below
    # mutates cross_existing[key] = value in place, so reading 'scope' from
    # cross_existing AFTER the loop would always equal request.GET['scope']
    # and the change would be invisible. The tags-clear fan-out depends on
    # this comparison happening across the loop, not after it.
    old_scope = cross_existing.get('scope', '')

    for key in filter_keys:
        if key not in request.GET:
            continue
        value = request.GET[key]
        if key in CROSS_ENTITY_FILTER_KEYS:
            cross_existing[key] = value
        else:
            entity_existing[key] = value

    # Scope-change → tags-clear (this entity + fan-out across siblings).
    new_scope = cross_existing.get('scope', '')
    if is_real_submit and old_scope != new_scope:
        if 'tags' in entity_existing:
            del entity_existing['tags']
        _clear_tags_from_other_entity_sessions(
            request.session, org_id, skip=entity_key,
        )

    request.session[cross_key] = cross_existing
    request.session[entity_key] = entity_existing
    return {**cross_existing, **entity_existing}
```

## Form sentinel — "this is a real submit, not a cross-link nav"

Filter forms render `<input type="hidden" name="_filter_form" value="1">`. Server's `get_effective_filters` checks `'_filter_form' in request.GET` to distinguish:

- **Real form submit** → trust empty values (e.g. unchecked tags); allow tags-clearing on scope change.
- **Cross-link nav** (e.g. `?scope=5` from another page) → don't clear unrelated session keys.

Without the sentinel, navigating across pages with even one filter param would silently clobber session state for filters not present in the URL.

## Clear-filters affordance

A "Clear" link should strip session state but not the broader URL state:

```python
# Shell view fragment
if 'clear' in request.GET:
    _resolve_filters(request)  # consume clear (mutates session)
    preserved = []
    for key in ('open', 'push'):
        if key in request.GET:
            preserved.append((key, request.GET[key]))
    clean_url = reverse(request.resolver_match.url_name)
    if preserved:
        from urllib.parse import urlencode
        clean_url = clean_url + '?' + urlencode(preserved)
    return HttpResponseRedirect(clean_url)
```

Why redirect: leaving `?clear=1` in the URL means a browser refresh re-clears, which contradicts user expectation. The 302 strips the consumable param while preserving stable-state params (`?open=`, `?push=` — the preview-drawer state per `PREVIEW_DRAWER_URL_STACK.md`).

## UI feedback contract for client-side

When filter state changes via HTMX (form submit refreshes the centre list, not the form), the form itself stays unchanged. If the form has count badges ("Tags (N selected)") or visual `is-selected` classes, they go stale after change. Two paths:

1. **Server-roundtrip refresh** — extend `hx-target` to swap the form too. Cost: form scroll position + collapsible open state lost. Usually wrong.
2. **Local DOM update** — small JS handler binds `change` events on form inputs and updates count + class locally. Idempotent re-bind on `htmx:afterSettle` so workspace re-renders rebind cleanly. Use a `data-*-bound` marker to prevent duplicate listeners.

Path 2 is the right answer. i18n templates emitted as `data-tags-i18n-zero` / `data-tags-i18n-plural` on the form root carry localised pluralisable strings; JS substitutes a `{n}` placeholder at click time.

## Checkbox-toggle filters need an explicit allowlist

HTML omits unchecked checkboxes from form-data submissions. A `<input type="checkbox" name="needs_approval" value="1">` that's unchecked produces **no** `needs_approval` key in `request.GET` — indistinguishable from "this request came from a page that doesn't use that filter at all".

Without disambiguation, a checkbox filter has a one-way ratchet bug:

- User checks the box, submits the form → `needs_approval=1` in GET → session stores it.
- User unchecks the box, submits the form → no `needs_approval` in GET → `get_effective_filters` falls through the "key not in request.GET → skip" branch → session keeps the stale `True`.
- The filter stays applied forever; unchecking is silently ignored.

The fix is a project-wide **`CHECKBOX_TOGGLE_KEYS`** allowlist enumerating the keys whose absence-on-real-submit means "user just unchecked it":

```python
# project/utils/filter_keys.py
CHECKBOX_TOGGLE_KEYS: tuple[str, ...] = (
    'assigned_to_me',
    'my',
    'unassigned',
    'needs_approval',
    # Future toggles: add here. Each entity's filter_keys tuple still
    # gates whether this entity actually uses the key, so listing one
    # here that no entity currently uses is harmless.
)
```

The toggle-clear loop runs **inside** the real-submit branch (gated by the `_filter_form=1` sentinel from the earlier section) so cross-link nav doesn't trigger it:

```python
def get_effective_filters(request, *, namespace, filter_keys):
    # ... existing cross/entity merge above ...
    is_real_submit = '_filter_form' in request.GET
    if is_real_submit:
        for toggle_key in CHECKBOX_TOGGLE_KEYS:
            if (toggle_key in filter_keys                # entity opts in
                    and toggle_key not in request.GET    # HTML omitted = unchecked
                    and toggle_key in entity_existing):  # session has stale True
                del entity_existing[toggle_key]
    # ... session writeback ...
```

**The bug pattern this prevents**: adding a key to a per-entity `filter_keys` tuple without adding it to `CHECKBOX_TOGGLE_KEYS`. Enabling the toggle persists; unchecking it doesn't. The fix is one tuple append.

### Test pattern — realistic uncheck shape

A naive uncheck test (`?_filter_form=1` with no other params) gets a false-pass because `get_effective_filters` typically gates the toggle-clear loop on `has_filter_params` — at least one filter key must appear in GET. Real form serialisation submits **every** form field including empty ones (`scope=&property=&category=&q=`), so the realistic test shape includes the empty siblings:

```python
def test_unchecking_toggle_clears_session(self):
    # 1. Enable + submit — toggle persists.
    self.client.get('/events/?_filter_form=1&scope=&property=&category=&q=&needs_approval=1')
    self.assertEqual(self.session_filters()['needs_approval'], '1')

    # 2. Uncheck + submit (mirrors real form serialisation: empty siblings,
    #    `needs_approval` key absent because HTML omitted the unchecked box).
    self.client.get('/events/?_filter_form=1&scope=&property=&category=&q=')
    self.assertNotIn('needs_approval', self.session_filters())
```

The empty siblings matter: `has_filter_params` becomes True (because `scope` is in GET, even though its value is empty), the toggle-clear loop runs, the toggle drops from session.

## Chip-row + per-filter-clear endpoint pattern

When a filter is set by **navigation** (clicking a counter, a deep-link from another surface, an AI-tool result) rather than by the filter form itself, the form-input model breaks down — there's no checkbox to uncheck. The user only sees the narrowed list and has no obvious way to clear the navigation-driven filter without clearing **everything**.

Legacy fallback: "Clear all" link, full-page reload to `?clear=1`. Loses scroll position, drawer state, every unrelated filter. Hostile.

The fix is a two-part affordance:

### 1. A read-only chip rendered above the centre list

Renders inside the same swap region as the list (so HTMX swaps update both atomically). Conditional on the navigation-driven filter being set:

```django
{% if filters.linked_to_article %}
<div class="chip-row">
    <span class="tag is-info">
        <span>{% blocktrans with title=linked_article.title %}Linked to: <strong>{{ title }}</strong>{% endblocktrans %}</span>
        <button class="delete"
                hx-post="{% url 'events:filter_clear' %}?key=linked_to_article"
                hx-target="#event-list-region"
                hx-swap="outerHTML"
                hx-push-url="true"
                aria-label="{% trans 'Clear filter' %}"></button>
    </span>
</div>
{% endif %}
```

The chip is **read-only** display + a single `[✕]` clear control. No form, no input. Pure HTMX.

### 2. An allowlisted per-filter clear endpoint

```python
# project/views/filter_clear.py
_EVENT_FILTER_KEYS: tuple[str, ...] = (
    'scope', 'property', 'category', 'tags', 'q',
    'linked_to_article', 'needs_approval',
)

@require_POST   # GET → 405 (prevents accidental cleanup via browser address bar)
def event_filter_clear(request):
    key = request.GET.get('key', '')
    if key not in _EVENT_FILTER_KEYS:
        return HttpResponseBadRequest('unknown filter key')   # allowlist defence
    org_id = request.user.org_id
    bucket = request.session.get(f'kb_event_filters_{org_id}', {})
    bucket.pop(key, None)
    request.session[f'kb_event_filters_{org_id}'] = bucket

    response = render_event_list_region(request)               # re-render
    response['HX-Push-Url'] = '/events/'                       # parent surface URL — NOT request.path (clear-endpoint path); strips any chip-driving QS
    return response
```

Three load-bearing details:

- **POST-only**. GETs against this endpoint are rejected with 405. Otherwise a stray browser-history GET or a misclick on a copy-paste link would clear session state silently.
- **Allowlist gate**. `?key=...` is validated against the entity's `_<SURFACE>_FILTER_KEYS` tuple before any session mutation. Defence-in-depth — never `del request.session[arbitrary_key]`.
- **`HX-Push-Url` to the surface URL, NOT `request.path`**. The chip click came from a URL that may carry `?linked_to_article=7` as part of the navigation; clearing the filter must also clean the address bar. `request.path` here is `/events/filter/clear/` — the *clear endpoint's* own path — which is what would land in the browser address bar if you push that. Push the *parent surface* URL (`/events/`) instead so refresh + bookmark land at the filtered-by-nothing surface. If the surface has a named route, prefer `reverse('events:list')` over a literal.

### Why this generalises

Any future navigation-driven per-entity filter inherits the UX for free:

1. Add the key to the entity's `_<SURFACE>_FILTER_KEYS` tuple.
2. Add a chip-row block to the surface template (one `{% if filters.<key> %}` clause).
3. Done. The clear endpoint generalises across all keys via the allowlist.

Examples that benefit: `assigned_to_team`, `created_by`, dashboard-widget deep-links (`from_widget=urgent_events`), AI-tool deep-links (`from_ai_suggestion=42`). The cost per new filter is one tuple entry + one template block.

### Test pattern

```python
class EventChipRowFilterClearTests(TenantTestCaseBase):
    def test_chip_renders_when_filter_set(self):
        response = self.client.get(f'/events/?linked_to_article={self.article.pk}')
        self.assertContains(response, 'Linked to:')

    def test_chip_absent_when_filter_unset(self):
        response = self.client.get('/events/')
        self.assertNotContains(response, 'chip-row')

    def test_clear_endpoint_removes_session_key(self):
        # Seed session via filter form.
        self.client.get(f'/events/?_filter_form=1&linked_to_article={self.article.pk}')
        response = self.client.post(f'/events/filter/clear/?key=linked_to_article')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['HX-Push-Url'], '/events/')
        self.assertNotIn('linked_to_article', self.session_filters())

    def test_allowlist_rejects_unknown_keys(self):
        response = self.client.post('/events/filter/clear/?key=arbitrary_key')
        self.assertEqual(response.status_code, 400)

    def test_get_rejected(self):
        response = self.client.get('/events/filter/clear/?key=linked_to_article')
        self.assertEqual(response.status_code, 405)
```

## Reference

Pairs with [`RULE_tenant-scoped-fk-validation`](../../django/references/TENANT_SCOPED_FK_VALIDATION.md) for the org-scoped session keys.

**Last Updated**: 2026-05-14
