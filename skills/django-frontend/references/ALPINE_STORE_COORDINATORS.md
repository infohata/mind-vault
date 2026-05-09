# Alpine.store coordinators with delayed-registered consumers — `onRegister` callback pattern

**When this fires**: an `Alpine.store('foo')` coordinator needs to drive a per-instance consumer (a registered drawer instance, a registered modal instance, a per-component Alpine factory) where the consumer's registration is asynchronous-after-store-init. The django-frontend SKILL.md body's coordinator section holds the firing-conditions stub; this reference holds the anti-pattern explanation + fix + generalisation rules.

The coordinator's tension: the store exists at `alpine:init`, but each consumer instance registers itself when its `x-data` factory runs during the DOM walk that follows. Code on the store side that needs to "talk to" a registered consumer can't do so synchronously — the consumer might not have registered yet.

## The fragile pattern that surfaces this

Polling for the registration via `Alpine.effect`:

```javascript
// Anti-pattern — timing-fragile
Alpine.effect(function () {
    const store = Alpine.store('drawerCoordinator');
    const entry = store.currentByEdge.preview;
    if (!entry || !entry.instance) return;
    // Now monkey-patch the instance — runs whenever Alpine.effect re-evaluates,
    // which is anyone's guess. Survives until something else triggers a re-eval
    // and double-patches, or the instance is replaced and the patch leaks.
    const orig = entry.instance.close;
    entry.instance.close = function () { orig.apply(this); /* extra */ };
});
```

Problems: re-evaluation is implicit (Alpine.effect recomputes on any reactive dep change in the function body); monkey-patches stack across re-runs; teardown is unobservable; instance replacement leaks the patch. The bug surfaces as "feature works the first time, breaks after the consumer re-registers" — N hours of debugging timing.

## The fix — explicit register-or-queue API on the coordinator store

```javascript
// Coordinator store: maintain a callback queue per registration name.
Alpine.store('drawerCoordinator', {
    currentByEdge: {},
    _registerCallbacks: {},

    /**
     * Run `callback(entry)` either immediately if `name` is already
     * registered, OR enqueue and run on first registration. Idempotent
     * for the not-yet-registered case (multiple calls queue multiple
     * callbacks); each callback fires once when register() is called.
     */
    onRegister(name, callback) {
        const entry = this.currentByEdge[name];
        if (entry && entry.instance) {
            // Already registered — fire synchronously.
            callback(entry);
            return;
        }
        const list = this._registerCallbacks[name] || [];
        list.push(callback);
        this._registerCallbacks[name] = list;
    },

    /** Register a consumer instance — fires queued callbacks. */
    register(name, edge, instance) {
        this.currentByEdge[name] = { edge, instance };
        const queued = this._registerCallbacks[name];
        if (queued && queued.length) {
            this._registerCallbacks[name] = [];  // drain
            queued.forEach(cb => {
                try { cb(this.currentByEdge[name]); }
                catch (err) { console.error('[coordinator] onRegister callback failed:', err); }
            });
        }
    },
});
```

Consumer side:

```javascript
// Anywhere that needs to react to drawer instance availability:
const coord = Alpine.store('drawerCoordinator');
coord.onRegister('preview', function (entry) {
    // entry.instance is the registered consumer; do binding here ONCE.
    // No polling, no re-evaluation, no monkey-patch stacking.
    _bindOpenStateSync(entry.instance);
});
```

## Why this works

- **One-shot semantics**: callbacks fire exactly once when registration happens; no double-fire on re-evaluations.
- **Synchronous-or-deferred is transparent to caller**: the consumer code shape is the same whether registration already happened or hasn't yet. No `if registered { do() } else { ?? }` branches at the call site.
- **No reactive deps**: the API is plain function-call + queue, not Alpine.effect — so it doesn't depend on the coordinator's internals being reactive in the right way.
- **Failure-isolated**: a throwing callback doesn't break the others (the `try/catch` per callback). Logged but doesn't take down the registration.

Generalizable to any `Alpine.store(coordinator)` shape where async-registered consumers need callbacks: modal coordinators, drawer coordinators, preview-surface stores, any per-instance factory the store drives. Pair the `register(name, ...)` method with `onRegister(name, callback)` whenever the store has consumers it needs to talk to.
