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

## Anti-pattern — sibling `x-data` vars are NOT coordinator-store proxies

Recurring trap when a shell template declares both an `Alpine.store('drawerCoordinator')` AND parent-scope `x-data` variables that LOOK like they ought to control drawer visibility:

```html
<!-- shell.html — the parent x-data declared at the <main> level -->
<main class="shell-main"
      x-data="{ workspaceOpen: true, previewOpen: false }">
    …
    <c-drawer name="workspace" mode="collapsible" :open="True">
        …
    </c-drawer>
    …
</main>
```

The `workspaceOpen` / `previewOpen` variables read like drawer visibility state — they have the right names, they default to sensible values. They are NOT. The drawer cotton's `<c-drawer>` registers its OWN `shellDrawer({...})` Alpine factory with its own `isOpen` field, which it registers into `Alpine.store('drawerCoordinator')` via the `register(name, edge, instance)` API. The parent-scope `workspaceOpen` exists for OTHER reasons (sometimes a layout class toggle, sometimes vestigial from an earlier shell design, sometimes used by sibling UI that wants to know "is the workspace visible" without round-tripping through the coordinator).

The trap: developers writing in-surface affordances (a section nav link that should close the mobile workspace drawer on tap) reach for the obviously-named variable:

```html
<!-- Anti-pattern — sets a sibling Alpine var that does NOT control drawer visibility -->
<a @click="if (window.matchMedia('(max-width: 768px)').matches) workspaceOpen = false">
    Section link
</a>
```

`workspaceOpen` mutates to `false`. The drawer DOESN'T close — because the drawer's `isOpen` field (the real state) is unchanged. Symptom: code that LOOKS like it should work, doesn't. Debugging time: until someone traces the drawer cotton's actual state source.

### Fix — use the coordinator API directly

The drawer cotton registers itself with the coordinator on `init()`; the coordinator's `openByName(name)` / `closeByName(name)` methods drive the real visibility:

```html
<!-- Correct — calls into the coordinator that owns drawer state -->
<a @click="if (window.matchMedia('(max-width: 768px)').matches
           && window.Alpine && Alpine.store('drawerCoordinator'))
           Alpine.store('drawerCoordinator').closeByName('workspace')">
    Section link
</a>
```

Same for opening:

```javascript
// JS from inside the workspace partial's inline script:
document.addEventListener('entityChanged', function (evt) {
    if (!window.matchMedia('(max-width: 768px)').matches) return;
    if (!evt.detail || evt.detail.type !== 'profile') return;
    if (!window.Alpine || !Alpine.store) return;
    var coordinator = Alpine.store('drawerCoordinator');
    if (!coordinator || typeof coordinator.openByName !== 'function') return;
    coordinator.openByName('workspace');
});
```

### Diagnosis — "is this the parent-x-data trap?"

Symptoms:

- The code LOOKS reactive (Alpine `@click` setting an obviously-named variable), but the drawer's class list (`shell-drawer--open` / `shell-drawer--closed`) doesn't change.
- DevTools shows the parent `<main>` element's `x-data` scope reflects the new value, but the drawer's element classes don't update.
- The reactive binding on the drawer (`:class="{ 'shell-drawer--open': isOpen }"`) reads from `isOpen` — that's the *drawer's* `x-data`, not the parent's.

Diagnosis confirmation: `Alpine.$data(document.querySelector('aside[data-drawer-name="workspace"]'))` returns the drawer's scope; its `isOpen` is the real source. The parent `<main>`'s `workspaceOpen` is a separate variable, unconnected.

### Why this trap is recurring

Both names "make sense" — the parent-scope variable is named `workspaceOpen` precisely because it sounds like "is the workspace open". Developers who haven't read the drawer cotton's internals reach for the obvious name. The coordinator API (`Alpine.store('drawerCoordinator').openByName('workspace')`) is non-obvious — you have to know the coordinator exists, what name it expects, and which methods it exposes.

The catcher: a smoke test asserting the drawer's `shell-drawer--open` class lands after the @click. Visual M-walk works too — "click section link, drawer doesn't close" is the failure mode.

### When parent-scope `workspaceOpen` IS the right answer

Rarely — but not never. Some shell layouts use the parent-scope variable to drive a class on `<main>` itself (`:class="{ 'has-workspace-open': workspaceOpen }"`) for CSS-only layout tweaks that don't need to flow through the drawer's state machine. In those cases, the parent-scope variable is a layout signal, not a drawer-state proxy. Both can coexist — the trap is only the assumption that mutating one mutates the other.

### Generalizable to other coordinator-backed surfaces

The same anti-pattern surfaces with any `Alpine.store` coordinator that has sibling parent-scope variables. The discipline is: **the coordinator store is the single source of truth for the resource it coordinates**. Parent-scope variables that happen to share a name are layout / debug / cosmetic signals at best, and should never be mutated as if they were the resource's state.

## When NOT to promote to a store — the inbound-command CustomEvent bridge

A store is the right tool when state must be *shared* across components. But sometimes an element
*outside* a component's `x-data` subtree needs to invoke a method **scoped to that component** — not
share state, just trigger one action. Example: a fixed edge rail (rendered outside the snap container,
so it can't be a descendant of its `x-data`) needs to call the snap component's `goToPane(name)`.

You could promote `goToPane` to a store to reach it — but that **leaks a component-internal method
into global scope** for a one-way trigger. Prefer a **symmetric event bridge** instead, which keeps
the method scoped:

- **Outbound (state):** the component already emits a state event on `document` when its state changes
  (`paneChanged`). Subscribers self-route from it.
- **Inbound (command):** the component's `init()` adds a `document` listener for a command event and
  routes it to its own scoped method:

```js
// inside the snap component's init():
document.addEventListener('shell:reveal-pane', (e) => {
    const name = e?.detail?.name;
    if (name) this.goToPane(name);          // scoped method stays private
});

// the out-of-tree rail just dispatches the command:
document.dispatchEvent(new CustomEvent('shell:reveal-pane', { detail: { name: 'workspace' } }));
```

Command-in / state-out is a clean, symmetric pair. Reach for the bridge (not a store) when the need is
**trigger a scoped action from outside the tree**, and for a store when the need is **share state
across components**. Dispatch/listener mechanics (bind on `document` not `body`, events bubble, the
listener survives `outerHTML` swaps, `detail` unwrapping) are not repeated here — see
[`SHELL_NOTIFICATIONS.md`](SHELL_NOTIFICATIONS.md) and [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md)
gotchas 2 & 11. A consumer of this pattern in a mobile scroll-snap shell:
[`mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md`](../../mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md)
§2.
