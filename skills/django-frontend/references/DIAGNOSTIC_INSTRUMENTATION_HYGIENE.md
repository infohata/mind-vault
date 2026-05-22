# Diagnostic instrumentation hygiene — flag-gated traces and the JS arg-evaluation trap

A class of cost-leak that recurs whenever a frontend ships flag-gated diagnostic instrumentation (`window.PREVIEW_TRACE`, `window.TIPTAP_TRACE`, `window.DEBUG`, etc.) and developers reach for the obvious shape — a `_trace()` function that early-returns when the flag is off. The shape *looks* like "zero cost when off" but isn't, because JavaScript evaluates function arguments **before** the function body's flag check. Every caller-supplied payload — every `document.querySelectorAll(...)`, every `dataset.foo` read, every `closest('a')` walk — runs on every call regardless of the flag. Both Cursor Bugbot and GitHub Copilot flag this pattern reliably during code review; if you write the naive shape, you'll re-fix it during a review cycle. Apply the lazy variant from the start.

Load this reference when:

- Adding `console.log` / `console.warn` / structured-trace calls behind a runtime flag (`window.X_TRACE = true` from devtools).
- Authoring a helper wrapper like `function _trace() { if (!window.FLAG) return; … }` for the first time.
- Reviewing a PR that adds diagnostic logging and the diff includes call sites passing object literals built from DOM queries.
- Refactoring an existing diagnostic helper after a code-review bot flagged "this still runs work when the flag is off."

## 1. Why `if (FLAG) return;` inside the wrapper is too late

```js
// LOOKS gated. ISN'T.
function _trace() {
    if (!window.PREVIEW_TRACE) return;        // ← runs AFTER arg eval
    console.log('[previewSurface]', ...arguments);
}

// Caller — payload built unconditionally:
_trace('_restoreBody pre-beforeSwap', {
    toolbars: document.querySelectorAll('[data-tiptap-toolbar]').length,
    hostToolbars: host.querySelectorAll('[data-tiptap-toolbar]').length,
    activeEditors: window.someWidget?.activeEditors.size,
});
```

JS evaluates `_trace`'s arguments left-to-right *before* control transfers to the function body. So the object literal is constructed (which runs both `querySelectorAll` calls, which walk the entire document subtree) every time the caller fires, even when `PREVIEW_TRACE` is `false`. The early-return only saves the `console.log` itself — typically the cheapest part.

Worst-case sites:

- **Per-click handlers** — `document.addEventListener('click', fn)` runs on every click in the page. A `_trace('docClick MISS', {…closest('a')…})` payload at the top of the handler costs N DOM traversals per click.
- **Per-frame swap hooks** — drawer / SPA route swaps fire dozens of times per session, each carrying a "before swap" + "after settle" + "scroll restore" trace.
- **Per-popstate iteration** — back/forward navigation loops over a stack of frames; payload runs once per frame.
- **In bulk loops** — `for (i=0; i<N; i++) _trace('iter', {…stuff…});` is N querySelectorAlls.

The cost is invisible in dev (machines are fast, samples are tiny) and proportional to user activity in prod (page complexity grows; click rate grows; cycle counts compound). The "zero runtime cost when not set" claim that lives next to the flag is wrong.

## 2. The lazy variant — pay for what you trace

Pass a **thunk**, not a value. The wrapper invokes it only when the flag is on, so the payload's DOM queries and attribute reads cost nothing when off.

```js
function _trace(label, ...args) {
    if (!window.PREVIEW_TRACE) return;
    console.log('[previewSurface]', label, ...args);
}

function _traceFn(label, thunk) {
    if (!window.PREVIEW_TRACE) return;
    let payload;
    try { payload = thunk(); }
    catch (err) { payload = { traceError: String(err) }; }
    console.log('[previewSurface]', label, payload);
}
```

Caller:

```js
// CHEAP — string label only, no payload to build:
_trace('_restoreBody enter');

// CHEAP-WHEN-OFF — thunk runs only when PREVIEW_TRACE is on:
_traceFn('_restoreBody pre-beforeSwap', () => ({
    toolbars: document.querySelectorAll('[data-tiptap-toolbar]').length,
    hostToolbars: host.querySelectorAll('[data-tiptap-toolbar]').length,
    activeEditors: window.someWidget?.activeEditors.size,
}));
```

Keep both helpers around. `_trace(label)` (no payload, or all string-literal args) is fine — keep it for the common cheap-trace case. Use `_traceFn(label, thunk)` only when the payload involves DOM queries, dataset/attribute walks, or non-trivial computation. Two helpers, two intents.

The `try/catch` inside `_traceFn` is load-bearing: a thunk that throws during a trace (e.g. because the DOM shape it was reading has changed across a swap) must not break the actual code path. Surface the error in the trace; don't propagate.

## 3. Handler-call-site shape — the highest-impact case

Per-event handlers wired to document or window deserve special discipline because they fire on **every** event of that class.

```js
function _documentClickHandler(evt) {
    const link = evt.target.closest && evt.target.closest('a[data-preview-link]');
    if (!link) {
        // GATE BEFORE the diagnostic walk — every miss costs zero
        // when the flag is off. Without the gate, every page click
        // (including misses on non-preview links) pays for a
        // closest('a') + getAttribute + hasAttribute walk.
        if (window.PREVIEW_TRACE) {
            const fallbackAnchor = evt.target?.closest?.('a');
            if (fallbackAnchor) {
                _trace('docClick MISS', {
                    href: fallbackAnchor.getAttribute('href'),
                    hasDataPreviewLink: fallbackAnchor.hasAttribute('data-preview-link'),
                });
            }
        }
        return;
    }
    // Cache values used by BOTH the trace payload AND the real
    // code path — never compute twice for instrumentation.
    const insideDrawer = !!link.closest('[data-preview-drawer]');
    if (window.PREVIEW_TRACE) {
        _trace('docClick HIT', {
            type: link.dataset.previewType,
            href: link.getAttribute('href'),
            insideDrawer: insideDrawer,
        });
    }
    if (insideDrawer) return;   // ← reuses the cached value
    // … real handler logic …
}
```

Two rules at the handler-call-site:

1. **Gate the diagnostic block, not just the trace call.** The `if (window.PREVIEW_TRACE) { … }` wraps the *entire* diagnostic setup — fallback-anchor lookup, payload construction, the trace call. The `_traceFn` thunk variant covers the trace-call portion; the gate covers the lookups that feed the thunk and any branch-helper variables only used by the trace.
2. **Cache values used by both code paths.** If the real handler logic needs `link.closest('[data-preview-drawer]')`, compute it once, hand the boolean to both the trace payload and the real bail-check. Computing it inside the trace payload (then re-computing for the bail-check) doubles the DOM walk per fired event.

## 4. Helpers that synthesise their own counts

A common pattern: a `_trace()` wrapper appends a generic "current state" payload after every caller's label.

```js
function _ttrace() {
    if (!window.TIPTAP_TRACE) return;        // ← gates the AUTO-payload
    const args = [...arguments];
    args.push({
        toolbars: document.querySelectorAll('[data-tiptap-toolbar]').length,
        hosts: document.querySelectorAll('.tiptap-host').length,
        active: activeEditors.size,
    });
    console.log('[tiptap]', ...args);
}
```

The auto-appended `{toolbars, hosts, active}` payload here is **correctly gated** — it lives after the early-return, so it costs zero when the flag is off. But the CALLER's payload is still eagerly evaluated:

```js
// _ttrace's auto-payload is gated. The caller's {…} is NOT.
_ttrace('cleanupInSwapTarget', {
    targetTag: target.tagName,                                    // cheap
    targetCls: target.className,                                  // cheap
    destroyed: destroyed,                                         // cheap
    extraSelectorCount: clone.querySelectorAll('.foo').length,    // ← NOT cheap, runs every call
});
```

Pair `_ttrace(label, …cheapArgs)` for cheap-payload callers with `_ttraceFn(label, thunk)` for expensive-payload callers — same lazy-variant pattern as §2. The auto-appended state payload inside the helper is orthogonal; that part stays where it is, behind the early-return.

## 5. Audit checklist — what to grep before opening a PR

After adding diagnostic instrumentation, before pushing:

```bash
# 1. Find every trace call passing an object literal.
rg "_t?race\([^)]*\{" path/to/your.js -n

# 2. For each match, check if the object's values include any of:
#    - document.querySelectorAll / .querySelector
#    - .closest( / .matches(
#    - .dataset.X  / .getAttribute( / .hasAttribute(
#    - any function call that walks the DOM
#
#    If any caller has expensive values, convert to the thunk variant.

# 3. Find handlers wired to high-frequency events:
rg "addEventListener\('(click|scroll|mousemove|input|popstate|htmx:)" -n
#    For each, check the handler's body for ungated trace work.

# 4. Find counts that ALWAYS run (purely diagnostic):
rg "querySelectorAll\(.+\.length" path/ -n
#    Any count whose sole consumer is a trace payload → gate
#    behind the flag with `if (window.X_TRACE) { … }`.
```

Pre-existing convention in your codebase: if previous PRs already shipped diagnostic instrumentation using the eager-payload shape, the new lazy helper is a candidate for retrofit — but only if you have a verified hot path. Don't sweep a whole file proactively; convert the call sites the new code adds, leave pre-existing cheap traces alone.

## 6. When you don't need this

- The trace payload is **only string literals or already-computed locals** — no DOM queries, no attribute reads. `_trace('saved frame', frameId)` is fine; `frameId` is already in scope.
- The trace is in a **one-shot bootstrap** path that runs once per page load. The cost of a single DOM query during init is negligible; don't over-engineer.
- The flag is **environment-baked, not runtime-toggleable**. If `process.env.NODE_ENV === 'production'` strips the trace at build time, the runtime branch doesn't matter. (Webpack / Vite / esbuild all support dead-code elimination on constant conditionals.)
- The helper is **already a tagged template** or other syntax that defers evaluation (`_trace\`label ${expr}\`` doesn't help — tagged templates eagerly evaluate expressions too; this exception is for build-time-folded literal templates only).

## 7. Why both Bugbot and Copilot catch this

The pattern is mechanically detectable. Both code-review bots flag it consistently:

> "The new diagnostic `_trace()` calls build payloads using `document.querySelectorAll(...)`. Those selectors run even when `window.PREVIEW_TRACE` is false, because arguments are evaluated before `_trace()` can early-return."

— typical Copilot phrasing, PR #474 review 1, finding 3287809216.

> "The handler now runs extra `querySelectorAll` passes in the `_ttrace` argument object even when `window.TIPTAP_TRACE` is unset. That contradicts the 'zero runtime cost when not set' claim."

— typical Cursor Bugbot phrasing, PR #474 review 2, finding 3287847901.

If you ship the eager-payload shape, you will fix it during the review cycle. The lazy variant from the start saves a cycle, saves the bot's review budget, and keeps the cost-of-instrumentation claim accurate from the first commit.

## References

- Pattern surfaced and codified during PR #474 (Teisutis) review 1 (Copilot, 7 Info findings across `preview_surface.js`) + review 2 (Bugbot LOW + Copilot Info, 2 more across `tiptap-widget.js` + a stale-comment cleanup).
- Sibling reference: [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) — Alpine 3 auto-init, HX-Trigger value wrapping, listener-installation-order traps. Same neighbourhood of "the shape *looks* right but the runtime contract bites you" defects.

---

**Last Updated**: 2026-05-22
