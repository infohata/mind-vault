# Destructive cleanup must close every re-creation path

When you **drop / delete / clear** a resource that the application also **lazily ensures** or **bootstraps**, the drop silently undoes itself unless you audit *every* path that can recreate it. A "remove the stale thing" command that runs green and then finds the stale thing back on the next request is the signature of this bug.

## The shape

Many resources in a Django stack are created in more than one place:

- **Explicit lifecycle command** — a `drop_*` / `clear_*` / `purge_*` management command or endpoint you just wrote.
- **Lazy ensure-on-use** — the read/write path calls `ensure_<resource>()` (or `get_or_create`, `makedirs(exist_ok=True)`, an index `exists()`-then-`create()`) before using it, so the *first query after the drop recreates it* — empty.
- **Deploy / bootstrap ensure** — a startup hook, a `migrate`/`collectstatic`-adjacent step, or an `ensure_all_*` command run on every deploy/health-check that recreates the resource wholesale.

If your drop only removes the resource but leaves any of these recreation paths pointed at the *same name/key*, the resource reappears — often **empty**, which is worse than leaving it alone, because now reads succeed-but-return-nothing instead of failing loudly.

## Failure walkthrough (generic)

1. You ship `drop_legacy_thing` → it deletes resource `foo`.
2. The next user request hits the read path, which calls `ensure_thing("foo")` before querying → `foo` is recreated, empty.
3. The command "worked" (it deleted), the deploy bootstrap "worked" (it re-ensured), and the user sees an empty result with no error. Nothing in the logs says "your drop was undone."

The same trap applies to: ES/search indices, cache namespaces, DB tables created outside migrations, MinIO/S3 buckets or prefixes, on-disk scratch dirs, Redis keyspaces, materialized views.

## The discipline

Before (or alongside) any destructive op, grep for **every** creator of the thing you're removing:

```bash
# names/keys of the resource you're about to drop
grep -rn "ensure_\|get_or_create\|exists()\|makedirs\|create_index\|\.create(" <app>/ | grep -i <resource>
# deploy/bootstrap ensure paths
grep -rn "ensure_all\|bootstrap\|on_startup\|ready(" <app>/
```

Then pick one:

- **Re-point the ensure paths at the *new* target.** If the drop is part of a migration (old name → versioned name), make the lazy-ensure and the bootstrap ensure target the *active version's* write key, not the bare legacy name — so they stop recreating the thing you just dropped. (This is usually the right fix when the drop is a rename/version migration.)
- **Guard the recreation.** Make ensure-on-use a no-op when the resource is intentionally absent (a feature flag / version gate), so a deliberate drop stays dropped.
- **Drop + block in one transaction/window.** When the resource genuinely must stay gone, remove the recreation path in the *same* change, not a follow-up.

## Test contract

A drop is only proven when a **post-drop read** confirms it stayed dropped (or repopulated from the *correct* source):

- Unit/integration: drop → run the lazy-ensure path (a real read) → assert the resource is still absent, or is the new target with the right contents — **not** an empty recreation of the old one.
- Don't assert only "delete was called." Assert the state *after* the system's own recreation paths have had a chance to fire.

## When this fires

Any IDEA/PR whose diff removes a persistent resource: index migrations, cache/key cleanups, table drops outside the ORM, bucket/prefix purges, scratch-dir teardown. Pairs with [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md) (sequence the drop as its own step, re-test after) and with the idempotency mindset in [`IDEMPOTENT_SEED_COMMANDS.md`](IDEMPOTENT_SEED_COMMANDS.md) (the inverse: a creator that must be safe to re-run; here the question is which creators re-run *unwantedly*).
