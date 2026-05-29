# Bulk ORM operations bypass the model layer — `update()`, `bulk_create`, `bulk_update`

`QuerySet.update()`, `bulk_create()`, and `bulk_update()` issue SQL directly. They do **not** call `Model.save()`, so everything that hangs off `save()` is silently skipped:

- **`auto_now` / `auto_now_add`** — `DateTimeField(auto_now=True)` is implemented in `pre_save`, which `save()` runs and bulk ops don't. A `.update(status="cancelled")` leaves `updated_at` frozen at its prior value. No error — the row just lies about when it changed.
- **`pre_save` / `post_save` signals** — search reindex, cache invalidation, audit-log writes, denormalised-counter bumps. None fire.
- **`save()` overrides** — any custom logic in your model's `save()` (slug generation, derived fields, `full_clean()` calls) is skipped.
- **`full_clean()` / field validators** — bulk ops write whatever you pass; model-level validation never runs.

The trap is that the bulk op is *correct and faster* for the column you meant to set — the bug is the **adjacent** field/signal you forgot rides on `save()`. It surfaces weeks later as "the list sorts wrong" (stale `updated_at`), "search doesn't show the change" (no reindex signal), or "the activity feed missed it" (no audit write).

## The `auto_now` case — set the timestamp explicitly

```python
from django.utils import timezone

# ❌ updated_at stays frozen — auto_now lives in pre_save, which .update() skips
Invitation.objects.filter(org=org, status="pending").update(status="cancelled")

# ✅ set every auto_now field by hand when you bypass save()
Invitation.objects.filter(org=org, status="pending").update(
    status="cancelled",
    updated_at=timezone.now(),
)
```

Same for `bulk_update` — list the `auto_now` field in `fields=` AND assign it on each instance first; `bulk_update` won't populate it for you:

```python
now = timezone.now()
for obj in objs:
    obj.status = "cancelled"
    obj.updated_at = now            # bulk_update won't touch auto_now fields
Model.objects.bulk_update(objs, fields=["status", "updated_at"])
```

`bulk_create` honours `auto_now_add`/`auto_now` (it builds instances and the field defaults apply) but still skips signals and `save()` overrides — so the signal/override caveats below stand even there.

## When the skipped signal matters — three honest options

If a `post_save` side effect (reindex, cache bust, counter, audit) is load-bearing for the rows you're bulk-mutating, pick deliberately — don't just "hope it's fine":

1. **Keep the bulk op, fire the side effect manually** afterward — reindex the affected ids, bust the cache key, write one batched audit row. Best when the side effect batches cheaply.
2. **Fall back to a `save()` loop** when the set is small (<~50 rows) and the per-row signal is the whole point. The query-count cost is real but bounded; correctness wins.
3. **Send the signal yourself**: `post_save.send(sender=Model, instance=obj, created=False)` per row — rarely worth it vs. option 1, but available when a third-party receiver is the only consumer.

The decision is "is anything downstream listening to `save()` for these rows?" — answer it at write time, not at the post-incident bug.

## Reviewer / self-sweep heuristic

When a diff introduces a `.update(` / `bulk_create(` / `bulk_update(` on a model, grep that model for: `auto_now`, `auto_now_add`, a `def save(`, and `@receiver(post_save` / `pre_save`. Each hit is a question — "does this bulk op need to replicate what save() would have done?" An unanswered hit on an `auto_now` field is a near-certain stale-timestamp bug.

## When bypassing is exactly right

Bulk ops exist *because* skipping the per-row model layer is the point — a 10k-row status flip should not fire 10k reindex signals or 10k `save()` calls. The rule isn't "never bulk" — it's "know what you skipped, and replicate only the part that's load-bearing." A status column with no `auto_now` sibling, no signal receiver, and no `save()` override is the ideal bulk target: just `.update()` it.
