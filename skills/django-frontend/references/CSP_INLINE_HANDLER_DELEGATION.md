# Converting inline `on*=` handlers → delegation to drop CSP `'unsafe-inline'`

## The goal

A strict Content-Security-Policy `script-src` that omits `'unsafe-inline'` blocks
**three** things at once:

- executable inline `<script>` blocks,
- native `on*=` HTML attributes (`onclick=`, `onerror=`, `onchange=`, …),
- `javascript:` URIs.

It does **NOT** block:

- `addEventListener` delegation (the replacement pattern below),
- Alpine `@click` / `x-on:` / `hx-on::` — those are **eval-based**, so they need
  `'unsafe-eval'`, not `'unsafe-inline'`. Keeping `'unsafe-eval'` (for Alpine's
  `new Function`) while dropping `'unsafe-inline'` is a coherent, common middle
  tier and still closes the inline-injection XSS class.

So the migration to drop `'unsafe-inline'` is: convert every native `on*=` and
`javascript:` URI to body-level delegation, leave Alpine/HTMX eval-handlers alone,
and keep `style-src 'unsafe-inline'` if your CSS relies on it (a separate axis).

## The replacement pattern — body-level delegation

Replace `<button onclick="confirmDelete('{{ id }}')">` with a **marker attribute**
consumed by one delegated listener bound on `document`:

```html
<button data-confirm-delete data-delete-id="{{ id }}" data-delete-name="{{ name }}">
```

```js
// Guard against double-binding across HTMX swaps / re-injection.
if (!window.__confirmDeleteBound) {
    window.__confirmDeleteBound = true;
    document.addEventListener('click', function (evt) {
        var el = evt.target.closest('[data-confirm-delete]');
        if (!el) return;
        confirmDelete(el.getAttribute('data-delete-id'),
                      el.getAttribute('data-delete-name'));
    });
}
```

Delegation on `document` survives HTMX `outerHTML` swaps automatically — the
listener is on a stable ancestor, and `closest()` re-resolves the target on every
click. This is why it's the right replacement in an HTMX app: no rebind-on-swap
bookkeeping (contrast [`LISTENER_REBIND_ON_SWAP.md`](LISTENER_REBIND_ON_SWAP.md),
which is the cost you pay for *non*-delegated per-element listeners).

## Three non-obvious traps

### 1. Drop `|escapejs` when the value moves from a JS-string context into an HTML attribute

The old handler put the value in a **JavaScript string literal**, so it correctly
used `|escapejs`:

```django
onclick="fn('{{ name|escapejs }}')"   {# JS-string context — escapejs is right #}
```

Moving the value into a `data-*` **HTML attribute** changes the context, and
`|escapejs` becomes **wrong**:

```django
{# ❌ escapejs emits \uXXXX sequences that render LITERALLY in an attribute #}
<button data-name="{{ name|escapejs }}">

{# ✅ drop escapejs — rely on Django's HTML autoescape for the attribute #}
<button data-name="{{ name }}">
```

`|escapejs` produces `"`-style escapes meant to be decoded by a JS parser. An
HTML attribute is **not** parsed by JS — the literal `"` text sits in the
attribute value and surfaces raw to the user. Django's default HTML autoescape
already does the correct thing for an attribute (`"` → `&quot;`, `<` → `&lt;`),
so the right move is to **remove** the filter, not swap it. Escape the value for
the context it actually lands in.

### 2. `textContent` does NOT decode HTML entities; `getAttribute` does

After autoescape, the attribute value in the HTML source is entity-encoded
(`Bob&#39;s &quot;file&quot;`). How you read it back matters:

- `el.getAttribute('data-name')` → the HTML parser **decodes entities** →
  `Bob's "file"` ✅
- `el.textContent = ...` / building a string and assigning to `textContent` →
  **no entity decoding** → a literal `&quot;` shows up in the rendered UI ❌

The trap bites when a JS fallback builds a confirmation message with a hardcoded
entity, e.g. `'Delete &quot;' + name + '&quot;?'` — `&quot;` renders raw because
`textContent` doesn't decode it. Use a plain `"` in JS string literals; let
`getAttribute` (not hand-written entities) carry any value that came from an
attribute.

### 3. Bind on `htmx:afterSettle`, not `htmx:afterSwap`, for `innerHTML`-injected content

A preview drawer / modal that injects a fetched body via `innerHTML` and then
dispatches an HTMX lifecycle event commonly dispatches **`htmx:afterSettle`**, not
`htmx:afterSwap` (afterSwap is HTMX's own post-swap event; a manual `innerHTML`
injector that wants widgets to initialize fires the *settle* event after the
content lands). A widget initializer (color picker, icon picker, etc.) that only
listens on `htmx:afterSwap` therefore stays dead inside the drawer. Bind on
**both** an immediate call (cold load) **and** `htmx:afterSettle` (drawer-injected),
guarded idempotently by a `data-initialized` flag so the three boot paths
(immediate, `DOMContentLoaded`, `afterSettle`) don't double-init. See
[`HTMX_WIDGET_LIFECYCLE.md`](HTMX_WIDGET_LIFECYCLE.md) for the idempotency contract.

## Migration discipline

- **Dead markup, delete — don't convert.** A sweep to drop `'unsafe-inline'`
  surfaces `on*=` handlers on markup that's no longer reachable (included nowhere,
  no live route). Delete it; git history preserves it. Converting dead handlers to
  delegation is maintaining dead code.
- **Source-assert regression guards.** Lock the win with `SimpleTestCase`s that read
  the shipped template/JS text and assert no executable inline `<script>` /
  `on*=` survives on the hardened surfaces — these fail the moment a new inline
  handler re-appears and would re-block the `'unsafe-inline'` drop. (Same shape as
  [`SCRIPT_TAG_JSON_ESCAPING.md`](SCRIPT_TAG_JSON_ESCAPING.md)'s `</script>` test.)
- **e2e is the load-bearing gate.** A browser probe that navigates the hardened
  surfaces (cold-load **and** via shell-nav) with a `console`/`pageerror` listener
  collecting any `Content Security Policy` script refusal, asserting the list stays
  empty, is the only thing that proves no handler slipped through. A curl smoke
  cannot — CSP refusals only fire in a real browser parsing the document.

## Verification

- **Unit (source-assert):** each hardened template carries no `on\w+=` attribute and
  no executable inline `<script>`; the delegated handler file carries the
  `data-*` marker + `closest()` walk.
- **e2e (Playwright):** zero script-CSP violations across the hardened surfaces,
  exercised both cold and via in-shell navigation; the converted affordances
  (delete confirm, preview open, etc.) still work.
- **CSP header:** assert the served `script-src` omits `'unsafe-inline'` (mirror the
  strict policy into the local/dev reverse-proxy config too, so e2e exercises the
  real header, not a permissive dev one).

## Related references

- [`LISTENER_REBIND_ON_SWAP.md`](LISTENER_REBIND_ON_SWAP.md) — the non-delegated
  alternative and why delegation (this pattern) avoids its rebind-on-swap cost.
- [`HTMX_WIDGET_LIFECYCLE.md`](HTMX_WIDGET_LIFECYCLE.md) — the idempotent
  (re-)init contract trap 3's `data-initialized` guard implements.
- [`SCRIPT_TAG_JSON_ESCAPING.md`](SCRIPT_TAG_JSON_ESCAPING.md) — the sibling
  escaping axis (server-rendered JSON in a `<script>`); both are about matching the
  escape to the context, and both lock the win with a source-assert test.
- [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) — `hx-on::*` / Alpine handlers
  are eval-based (`'unsafe-eval'`), NOT inline-attribute (`'unsafe-inline'`); they
  survive this migration untouched.
