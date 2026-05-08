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

    for key in filter_keys:
        if key not in request.GET:
            continue
        value = request.GET[key]
        if key in CROSS_ENTITY_FILTER_KEYS:
            cross_existing[key] = value
        else:
            entity_existing[key] = value

    # Scope-change → tags-clear (this entity + fan-out across siblings).
    if is_real_submit and _scope_changed(cross_existing, request.GET):
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

## Reference

- Pattern surfaced in teisutis IDEA-146 (PR #433) M15 + clear-redirect; original `cross_filters_<org_id>` / `<namespace>_<entity>_filters_<org_id>` split came from teisutis IDEA-136. Pairs with [`RULE_tenant-scoped-fk-validation`](../../../rules/RULE_tenant-scoped-fk-validation.md) for the org-scoped session keys.

**Last Updated**: 2026-05-08
