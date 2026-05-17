# Action vocabularies — atomic decisions, never procedures

**When this fires**: any router / dispatcher / state-machine that returns `{action: '<verb>', …}` to a downstream consumer. Every action verb must be an **atomic decision** (`open`, `push`, `close`, `replace`) — never a **compound procedure** (`syncToTokens`, `applyAll`, `reconcile`, `migrateAndOpen`). Compound-procedure verbs mix abstraction levels — they belong inline at the call site that orchestrates them, not in the vocabulary the router emits.

## The hard rule

For each verb in the vocabulary, ask:

> Does this action describe ONE atomic primitive operation on the target state? Or does it describe a SEQUENCE of operations that the dispatcher must execute together as a procedure?

If it's a sequence, it doesn't belong in the action vocabulary. Move it inline at the one call site that needs it.

## What counts as atomic

Atomic actions are 1:1 with **primitive state mutations** on the dispatcher's target:

- `open(frame)` → replace stack with `[frame]`.
- `push(frame)` → append `frame` to stack.
- `pop()` → remove top of stack.
- `close()` → empty stack.
- `replace(frame)` → replace top of stack with `frame`.
- `openWith(prefix, frame)` → set stack to `[…prefix, frame]` (still one primitive — atomic batch set).

Each maps to one method on the target state. The dispatcher's job is purely the switch:

```javascript
function _dispatchIntent(store, intent) {
    switch (intent.action) {
        case 'open':     store.open(intent.frame); return;
        case 'push':     store.push(intent.frame); return;
        case 'openWith': store.openWith(intent.prefix, intent.frame); return;
        case 'pop':      store.pop(); return;
        case 'close':    store.close(); return;
    }
}
```

## What does NOT count — and why

- `syncToTokens(urlState)` → "parse the URL tokens, diff against current stack, do whatever pop / push sequence equalises them". A procedure: calls `pop` and `push` itself, in a loop, with logic. Belongs inline in the URL-reconciliation function, not in the vocabulary.
- `applyAll(intents)` → "iterate intents and dispatch each". The dispatcher's job; making it an action means the dispatcher dispatches to itself recursively — unbounded compose-with-self cases no reviewer can reason about.
- `reconcile(targetState)` → procedure pretending to be an atomic decision.
- `migrateAndOpen(oldFrame, newFrame)` → two atomic primitives bundled. Either `migrate()` + `open()` at the call site, OR the migration belongs inside `open()` (and there's no `migrateAndOpen` action at all).
- `openOrReplace(frame)` → conditional dispatch. The CALLER decides which primitive to use; the action vocabulary doesn't get to defer the choice.

The smell: any action whose dispatcher switch-case body isn't a single method call. If the case has `if` / `for` / `try` / multiple primitive calls inside it, the action is a procedure.

## When this applies

- Any router / event handler / click handler that emits a discriminated union and hands it to a dispatcher.
- Any URL parser / popstate handler that emits "actions" for reconciliation.
- Any state machine where the transition table's RHS describes "what action to take".
- Any keyboard / gesture handler that maps inputs to outputs through a discriminated union.

Does not apply to internal helper functions that compose primitives — those don't appear in the action vocabulary; they're called from procedures (popstate handlers, URL reconciliation loops) inline. And it doesn't apply to high-level user-intent verbs documented for users ("save the document", "publish the article") that the application orchestrates as N atomic operations — those describe the user's mental model; the router's action vocabulary is the implementation surface beneath them.

## Why this matters

### Two-of-three callers is the natural cut

A router emits an action vocabulary because MULTIPLE call sites need the SAME discriminated union of decisions. When one call site uses a vocabulary entry but the others can't (because the entry describes a procedure specific to one caller's context), the entry doesn't belong in the vocabulary — it belongs inline in that one caller.

Worked example: click-handler routing in a preview-drawer surface. Two click handlers (outside-drawer + inside-drawer) both decide: `open`, `push`, `openWith`. So the action vocabulary is shared. A THIRD caller — popstate — needs to "reconcile current stack against URL tokens". The temptation is to add `syncToTokens` to the vocabulary; the discipline is to keep it inline in popstate. Popstate isn't a peer of the click handlers; it's a procedure that COMPOSES primitives. Adding it to the vocabulary inflates every other consumer (the click handlers now must handle `case 'syncToTokens'` that they never produce) and pollutes the dispatcher's surface.

### The dispatcher's switch becomes a reasoning checkpoint

A pure-decision action vocabulary keeps `_dispatchIntent` one-line-per-case. Reviewers see the full surface in 10 lines. As soon as a procedure-shaped action lands, one case grows into 30 lines and the switch is no longer a checkpoint — it's the actual logic. The router's purpose dissolves.

### Procedures-as-actions defeat undo / replay

"Replay the last N actions in reverse to undo" or "record the action stream for debug replay" depends on atomic actions. A procedure-action encodes ONE OUTCOME of ONE EXECUTION — re-running `syncToTokens(urlState)` against a different starting state produces a different result, breaking replay.

## Detection

When code-reviewing or designing a router that produces actions:

1. List every action's name.
2. For each action, write the dispatcher's switch case body.
3. Count primitives invoked. If `> 1` AND involves control flow (`if` / `for`), flag as procedure-shaped.
4. Identify which caller(s) produce that action. If only ONE, the action probably belongs inline in that caller, not in the shared vocabulary.

The "shared by ≥ 2 callers" check is the structural test for vocabulary entry — atomic-decision content is necessary but not sufficient. Both gates must pass.

## Anti-patterns

- ❌ "Adding the procedure as a new action makes the call site shorter." Yes, at the cost of inflating the dispatcher and corrupting every other consumer.
- ❌ "I'll mark it as 'experimental' — promise not to use it from other callers." The single-caller test is structural; flagged-experimental actions are a memory-only constraint nobody enforces six months later.
- ❌ "The action enum is internal — only this module sees it." Internal enums have the same readability + replay-ability + abstraction-level concerns; "internal" is not an escape hatch.
- ❌ Compound action names that describe sequences (`openThenPush`, `closeAndOpen`, `parseAndApply`) — procedures by name.

## Related

- [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md) — concrete worked example of a router-with-dispatcher pattern (click-handler `_routeIntent` + `_dispatchIntent` extraction) where this rule was first surfaced.
- [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md) — renaming an action vocabulary entry is the same discipline; rename + drop sequence applies.
- [`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) — the contract-change sweep applies to action vocabulary changes too: grep every dispatcher case + every producer site.
