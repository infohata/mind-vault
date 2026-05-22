# Diagnostic instrumentation hygiene — flag-gated traces and the JS arg-evaluation trap

A class of cost-leak that recurs whenever a frontend ships flag-gated diagnostic instrumentation (`window.PREVIEW_TRACE`, `window.TIPTAP_TRACE`, `window.DEBUG`, etc.) and developers reach for the obvious shape — a `_trace()` function that early-returns when the flag is off. The shape *looks* like "zero cost when off" but isn't, because JavaScript evaluates function arguments **before** the function body's flag check. Every caller-supplied payload — every `document.querySelectorAll(...)`, every `dataset.foo` read, every `closest('a')` walk — runs on every call regardless of the flag. Both Cursor Bugbot and GitHub Copilot flag this pattern reliably during code review; ship the lazy variant from the start to save a review cycle.

Load this reference when:

- Adding `console.log` / `console.warn` / structured-trace calls behind a runtime flag (`window.X_TRACE = true` from devtools).
- Authoring a helper wrapper like `function _trace() { if (!window.FLAG) return; … }` for the first time.
- Reviewing a PR that adds diagnostic logging and the diff includes call sites passing object literals built from DOM queries.

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

JS evaluates arguments left-to-right *before* control transfers to the function body. The object literal is constructed (running both `querySelectorAll` calls) every time the caller fires, even when `PREVIEW_TRACE` is `false`. The early-return only saves the `console.log` itself — typically the cheapest part.

Worst-case sites: per-click document handlers, per-frame swap hooks (drawer / SPA route swaps), per-popstate frame loops, bulk loops. Cost is invisible in dev and proportional to user activity in prod — the "zero runtime cost when not set" claim that lives next to the flag is wrong.

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
// CHEAP — string label only:
_trace('_restoreBody enter');

// CHEAP-WHEN-OFF — thunk runs only when PREVIEW_TRACE is on:
_traceFn('_restoreBody pre-beforeSwap', () => ({
    toolbars: document.querySelectorAll('[data-tiptap-toolbar]').length,
    hostToolbars: host.querySelectorAll('[data-tiptap-toolbar]').length,
    activeEditors: window.someWidget?.activeEditors.size,
}));
```

Keep both helpers. `_trace(label)` is fine for string-literal / already-computed-local payloads. Use `_traceFn(label, thunk)` only when the payload involves DOM queries, dataset/attribute walks, or non-trivial computation. The `try/catch` inside `_traceFn` is load-bearing: a thunk that throws (e.g. because the DOM shape changed across a swap) must not break the actual code path.

**When you don't need this:** payload is already-computed locals (`_trace('saved frame', frameId)`); the trace is in a one-shot bootstrap path; the flag is build-time-stripped (`process.env.NODE_ENV` with Webpack/Vite/esbuild dead-code elimination).

## 3. Handler-call-site shape — the highest-impact case

Per-event handlers wired to document or window deserve special discipline because they fire on **every** event of that class.

```js
function _documentClickHandler(evt) {
    const link = evt.target.closest && evt.target.closest('a[data-preview-link]');
    if (!link) {
        // GATE BEFORE the diagnostic walk — every miss costs zero
        // when the flag is off.
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
    // Cache values used by BOTH paths — never compute twice for instrumentation.
    const insideDrawer = !!link.closest('[data-preview-drawer]');
    if (window.PREVIEW_TRACE) {
        _trace('docClick HIT', { type: link.dataset.previewType, insideDrawer });
    }
    if (insideDrawer) return;   // ← reuses the cached value
    // … real handler logic …
}
```

Two rules:

1. **Gate the diagnostic block, not just the trace call.** The `if (window.PREVIEW_TRACE) { … }` wraps the *entire* diagnostic setup — fallback-anchor lookup, payload construction, trace call. `_traceFn` covers the trace-call portion; the gate covers lookups and branch-helper variables only used by the trace.
2. **Cache values used by both code paths.** Compute `link.closest('[data-preview-drawer]')` once; hand the boolean to both the trace payload and the real bail-check. Computing inside the trace payload (then re-computing for the bail-check) doubles the DOM walk per fired event.

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

The auto-appended payload here is **correctly gated** — it lives after the early-return. But the CALLER's payload is still eagerly evaluated:

```js
// _ttrace's auto-payload is gated. The caller's {…} is NOT.
_ttrace('cleanupInSwapTarget', {
    extraSelectorCount: clone.querySelectorAll('.foo').length,    // ← runs every call
});
```

Pair `_ttrace(label, …cheapArgs)` for cheap-payload callers with `_ttraceFn(label, thunk)` for expensive-payload callers — same lazy-variant pattern as §2.

## 5. Audit checklist — what to grep before opening a PR

```bash
# 1. Trace calls passing an object literal — check whether values include
#    querySelectorAll/closest/dataset/getAttribute. If so → thunk variant.
rg "_t?race\([^)]*\{" <js-dir> -n

# 2. Handlers wired to high-frequency events — check body for ungated trace work.
rg "addEventListener\('(click|scroll|mousemove|input|popstate|htmx:)" <js-dir> -n

# 3. Counts whose sole consumer is a trace payload → gate behind the flag.
rg "querySelectorAll\(.+\.length" <js-dir> -n
```

Convert call sites the new code adds; don't proactively sweep pre-existing cheap traces.

## References

- Sibling reference: [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) — Alpine 3 auto-init, HX-Trigger value wrapping, listener-installation-order traps. Same neighbourhood of "the shape *looks* right but the runtime contract bites you" defects.
