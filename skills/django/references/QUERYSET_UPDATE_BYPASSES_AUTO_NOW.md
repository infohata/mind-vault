# `QuerySet.update()` bypasses `auto_now` — set the timestamp explicitly

A model field declared `auto_now=True` (typically `updated_at`) is refreshed by Django **only inside
`Model.save()`**. Bulk paths that never call `save()` leave it stale:

- `QuerySet.update(...)`
- `QuerySet.bulk_update(...)`
- `QuerySet.bulk_create(...)` (no `auto_now_add` either)
- any update via an `F()` expression

```python
# ❌ updated_at NOT touched — the row keeps its old timestamp
Invitation.objects.filter(pk__in=ids).update(status='cancelled')

# ✅ set it explicitly when you bypass save()
from django.utils import timezone
Invitation.objects.filter(pk__in=ids).update(status='cancelled', updated_at=timezone.now())
```

## Why it bites silently

There is **no error** — the rows update, the status flips, the test for "status is cancelled" passes.
The staleness only surfaces when **something downstream reads `updated_at`**: a "recent activity"
feed, a "changed in the last N days" filter, a cache-invalidation key, an `ETag`/`Last-Modified`
header, an audit sort. Those features quietly show wrong data, and the bug is hard to trace back to a
`.update()` call that looked complete.

The lure is performance: a status transition over many rows is naturally a single `.update()` instead
of a save-loop. That's the right call for throughput — just remember the timestamp isn't free anymore.

## Rule

Whenever you reach for `.update()` / `bulk_update()` / `F()` on a model that has an `auto_now` field
**and** any reader depends on that field, set it by hand in the same call. If no reader depends on it,
the staleness is harmless — but the safe default is to set it, because a future reader won't know the
timestamp is a lie.

A model-manager `update()` override that injects `updated_at=timezone.now()` centralises this, but it
also hides the cost and can surprise callers who pass their own `updated_at`; prefer the explicit
call-site form unless bulk-status-transitions are pervasive.
