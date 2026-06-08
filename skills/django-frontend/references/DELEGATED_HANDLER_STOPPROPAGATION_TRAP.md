# A stopPropagation guard kills document-delegated handlers

**Scope**: a click handler added to a dropdown / menu / kebab wrapper to stop the
click bubbling to a sibling open-handler — when that same guard ALSO swallows a
**document-delegated** handler the element relies on (a confirm-trigger, a
preview-open, any `document.addEventListener('click', …)` that matches via
`event.target.closest(...)`).

## The shape

A kebab / dropdown wrapper toggles a menu and contains action buttons (Delete, …).
The Delete button's behaviour is wired through a **document-delegated** listener —
e.g. one `click` listener bound on `document` that acts on
`event.target.closest('[data-confirm-trigger]')`. Document delegation is the
standard way to make a handler survive HTMX swaps: the button DOM is replaced on
every swap, the `document` listener is not, so delegation is what keeps the
affordance alive.

Someone then adds `@click.stop` (Alpine) or `onclick="event.stopPropagation()"`
to the **wrapper** — usually to stop the menu-toggle click from bubbling up to a
parent open-handler. That guard runs during the bubble phase and **halts
propagation before the event reaches `document`** — so the document-delegated
Delete listener never fires. The click silently dead-ends: the menu opens, you
click Delete, nothing happens, no console error.

```html
<!-- ❌ the stop guard swallows the document-delegated confirm handler -->
<div class="dropdown" x-data @click.stop>   <!-- or onclick="event.stopPropagation()" -->
  <button class="dropdown-trigger">⋮</button>
  <div class="dropdown-menu">
    <button data-confirm-trigger data-confirm-url="…">Delete</button>  <!-- never reached -->
  </div>
</div>
```

## Two things are usually wrong at once

1. **The guard is often unnecessary AND harmful.** It's added to stop bubbling to
   a sibling open-handler — but if that open-handler is itself scoped with
   `closest('[data-preview-link]')` (or any marker the wrapper doesn't carry), it
   *already* ignores clicks on the dropdown. The marker scopes it; the
   `stopPropagation` adds nothing except breaking everything that delegates from
   `document`. Drop the guard.

2. **`is-hoverable` is the wrong open mechanism for a click affordance.** Bulma's
   `.dropdown.is-hoverable` opens on `:hover` only — no click feedback, and
   **dead on touch** (no hover state on mobile). A user tapping the kebab sees
   nothing happen. Drive it with an explicit **Alpine click-toggle**, not
   `is-hoverable`.

```html
<!-- ✅ click-toggle, no stop guard; document-delegated Delete reaches document -->
<div class="dropdown" x-data="{open:false}" :class="{'is-active':open}">
  <button class="dropdown-trigger" @click="open = !open">⋮</button>
  <div class="dropdown-menu" x-show="open" @click.outside="open=false">
    <button data-confirm-trigger data-confirm-url="…">Delete</button>  <!-- reaches document ✅ -->
  </div>
</div>
```

## The rule

Before adding `stopPropagation` / `@click.stop` to any container, ask **what
listens on `document` for clicks inside this subtree** — confirm-triggers,
preview-open, delegated nav, analytics. A stop guard is a blanket veto on all of
them. If you need to stop bubbling to *one specific* ancestor, prefer scoping that
ancestor's handler with a marker (`closest('[data-…]')`) over a propagation veto
that blinds every document-level delegate. And drive click affordances with a
click handler (Alpine toggle), never `:hover`-only CSS — hover doesn't exist on
touch.

The failure is invisible in render-and-assert tests (the DOM is correct) and in
curl smokes (no JS) — it only shows under a real-browser click, and especially on
touch. See [`VISUAL_ACUITY_TESTS_VIA_PLAYWRIGHT.md`](VISUAL_ACUITY_TESTS_VIA_PLAYWRIGHT.md)
for the click / touch-path test class.

Adjacent: [`LISTENER_REBIND_ON_SWAP.md`](LISTENER_REBIND_ON_SWAP.md) is the
*opposite* failure mode — a handler bound directly to a swapped element dies
because it was NOT document-delegated. Together they bracket the delegation
decision: delegate from `document` so the handler survives swaps (LISTENER_REBIND),
then don't let a `stopPropagation` guard upstream strangle that delegation (this
reference).
