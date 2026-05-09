# Cross-entity session-filter state — fan-out invalidation on shared-key change

**When this fires**: user-facing filter state spans multiple list/detail surfaces (articles ↔ events ↔ FAQs ↔ dashboard) and the project shapes session keys as `cross_filters_<org_id>` (cross-entity) + `kb_<entity>_filters_<org_id>` (per-entity). The django SKILL.md body's cross-entity-session-filter section holds the firing-conditions stub; this reference holds the trap walkthrough + helper implementation + two-gate safety + generalisation rule + test contract.

## The two-key shape

```python
CROSS_ENTITY_FILTER_KEYS: Tuple[str, ...] = ('scope', 'property', 'category')

def get_effective_filters(request, *, namespace: str, filter_keys: tuple) -> dict:
    """Read URL-or-session filters; bucket writes into cross vs per-entity."""
    org_id = getattr(get_current_tenant(), 'pk', 0)
    cross_key = f'cross_filters_{org_id}'
    entity_key = f'kb_{namespace}_filters_{org_id}'
    # ... bucket each filter_keys value into cross or entity by membership in
    # CROSS_ENTITY_FILTER_KEYS, then return the merge.
```

## The trap that recurs

When a cross-entity field changes value, **derived per-entity state that was foreign-keyed to it goes stale on EVERY sibling per-entity entry** — not just the current request's. Concrete worked example:

- Tags are FK-scoped to Scope (`Tag.scope_id → Scope.id`).
- User on `/articles/` picks `scope=A` and `tag=X`. `kb_articles_filters_<org>.tags = ['X']`, `cross_filters_<org>.scope = 'A'`.
- User cross-links to `/events/` (no GET params).
- User changes `scope=B` on `/events/`. The current request's entity is `events`; the obvious clear-tags fix only touches `kb_events_filters_<org>`. **`kb_articles_filters_<org>.tags = ['X']` is untouched** — but X is a scope-A tag and doesn't apply to scope B. Articles' tag-picker now renders for scope B (so X isn't in the picker → user can't de-select), but `apply_common_filters` still applies tag X from session → 0 results, no UI escape.

## The fix — iterate session keys with a stable namespace prefix

When the scope-change branch fires, clear the derived field from every matching entry, not just the current entity.

```python
def _clear_tags_from_other_entity_sessions(
    session: Any,
    org_id: int,
    skip: str,
) -> None:
    """Remove ``tags`` from every ``kb_*_filters_<org_id>`` entry except ``skip``."""
    suffix = f'_filters_{org_id}'
    prefix = 'kb_'
    for key in list(session.keys()):
        if key == skip:
            continue
        if not (isinstance(key, str) and key.startswith(prefix) and key.endswith(suffix)):
            continue
        entry = session.get(key) or {}
        if 'tags' not in entry:
            continue
        new_entry = {k: v for k, v in entry.items() if k != 'tags'}
        if new_entry:
            session[key] = new_entry
        else:
            del session[key]


# In get_effective_filters, after the cross/entity bucket-write loop:
old_scope_value = cross_existing.get('scope', '')   # captured before the loop
# ... loop fills cross_existing[scope] from get_params if scope changes ...
scope_changed = (
    'scope' in filter_keys
    and old_scope_value
    and cross_existing.get('scope', '') != old_scope_value
)
if scope_changed:
    if 'tags' in entity_existing:
        del entity_existing['tags']
        entity_changed = True
    _clear_tags_from_other_entity_sessions(
        request.session, org_id, skip=entity_key,
    )
```

## Two gates make this safe

- **`old_scope_value` truthy gate.** The very first scope+tags submit (where the user is intentionally setting both with `'' → 'A'`) would otherwise satisfy "old != new" and clobber the user's own freshly-submitted tags. Truthy gate excludes the empty-to-something case from "change".
- **`isinstance(key, str)` defence in the helper.** Django sessions normally carry string keys, but mocks and pickled exotic types can leak through; the defensive check keeps the iteration safe.

## Generalise the rule

**For any per-entity state derived from a cross-entity field, the cross-field's write site must fan out invalidation across every per-entity session entry that shares the org-scoped suffix**. Entity-local clearing alone is incomplete — at any moment the user has multiple sibling entries holding their own copy of the now-stale derived state.

## Test contract

The `test_scope_change_clears_tags_across_all_entity_sessions` shape is the canonical four-step worked example to copy when adapting the pattern to a new project (set up two surfaces, change scope on one, navigate to the other, assert the second surface's derived state is also cleared).
