# Preview-drawer URL stack contract

When a megastack-style preview drawer needs to round-trip its **full** state through the URL — not just the top frame — the additive `?open=<base>&push=<f1>,<f2>,…` encoding is the canonical answer. Every consumer of the drawer (article, attachment, future event/faq/dashboard surfaces) gets URL survival, browser back/forward, and share-link cold-start at depth N for free.

## When to use

- A right-pane preview drawer that pushes deeper frames (article → attachment → comment thread, or chat → linked-record → attachment).
- Browser back/forward should pop one frame, not close the whole drawer.
- Share-links and bookmarks at depth>1 must restore the full chain, not just the top.

## When NOT to use

- A simple modal that opens and closes (no chain). `?open=<type>:<id>` single-frame is fine.
- A surface where only the top frame is shareable by design.
- Single-page-app routers with their own URL state (the drawer state is part of the SPA's route, not Django's URL).

## The contract

```
?open=article.7                                   # depth=1
?open=article.7&push=attachment.23                # depth=2
?open=article.7&push=attachment.23,attachment.45  # depth=3
```

- `?open=` carries the BASE (depth=1) frame as `<type>.<id>`.
- `?push=` is comma-separated CSV of frames stacked on top, in order (closer-to-base first, top last).
- In-frame separator `.` is RFC 3986 unreserved → no percent-encoding.
- Frame separator `,` is RFC 3986 sub-delim → no percent-encoding.
- **Lenient-parse semantics**: any malformed `&push=` frame collapses the result to `[base]` (consistency over partial parse). Better to land at depth=1 than at a reordered/broken stack.

## The 7-phase migration (single-IDEA, 5-6 commits)

When migrating an existing single-frame `?open=<type>:<id>` surface to the multi-frame stack:

| Phase | Layer | What |
|---|---|---|
| 1 | Server URL contract | Add `parse_open_stack(request) → list[ParsedTarget] | None` + `build_url_with_stack(base, stack) → str`. Keep `parse_open_param` as a shim returning `stack[0]`. Add comprehensive lenient-parse tests. |
| 2 | Server frame body endpoints | Each `OpenType` needs a server-side fragment-render endpoint so cold-start fetches HTML for any frame, not just the top. Mirror any existing JS-side hand-assembled markup. |
| 3 | Server seed dispatcher | New shell module exposes `resolve_frame_seed(request, frame) → {type, identifier, title, url}`. Surface views emit JSON ARRAY seed (always, even single-frame). Per-type resolvers are one-branch each. |
| 4 | Client cold-start | JS reads array seed; calls `store.open(seeds[0])` then `store.push(seeds[1..N-1])` sequentially. Validates every frame; bails consistently if any malformed. Accept legacy object seed format (back-compat). |
| 5 | Client URL sync | `_buildOpenUrl(stackOrFrame)` accepts either; emits `?open=&push=`. `_syncUrl(stack)` reads `this.stack` directly. `open/push/pop/close` all call `_syncUrl(this.stack)`. History state object carries FULL stack metadata for popstate forward-nav recovery. |
| 6 | Client popstate diff | Replace single-level pop with longest-common-prefix diff: parse target stack from URL, find LCP with current stack, pop until LCP, push remaining target frames. "Back/forward into a fresh deep frame" symptom-class falls out for free. |
| 7 | Cross-IDEA backref | File `<src-archive>/YYYY-MM-DD-amended-by-idea-NNN.md` per `RULE_cross-idea-amendments`. Tracker close-out. |

## The "popstate without persisted state" failure mode

After phase 6 ships, browser back/forward at depth>1 can still render empty bodies if `history.state.stack[i]` is missing per-frame `url` metadata. Causes:

- Very first popstate after a fresh navigation (no prior pushState in this history entry).
- Browsers that purge per-entry state aggressively.
- Incognito mode or session-restore-after-crash.

**Fix**: server emits per-OpenType URL pattern map as JSON; JS reads at bootstrap and uses for fallback URL derivation when persisted state is missing. Pattern mirrors the per-type resolvers' URLs:

```python
# server-side preview_seed.py
URL_PATTERN_BY_TYPE: dict[str, str] = {
    OpenType.ARTICLE.value: '/articles/ui/detail/{id}/',
    OpenType.ATTACHMENT.value: '/attachments/ui/detail/{id}/',
    # … one entry per OpenType.
}
```

```html
<!-- shell.html -->
<script type="application/json"
        id="ui-preview-url-patterns">{{ preview_url_patterns_json|safe }}</script>
```

The `|safe` filter is **load-bearing** — without it, Django autoescape mangles `"` into `&quot;` and JSON.parse throws SyntaxError at the bootstrap fetch.

```js
// preview_surface.js bootstrap
const _urlPatternByType = JSON.parse(
    document.getElementById('ui-preview-url-patterns').textContent
);

function _deriveFrameUrl(type, id) {
    return (_urlPatternByType[type] || '').replace('{id}', id);
}
```

In the popstate handler:

```js
url: persisted?.url || _deriveFrameUrl(token.type, token.identifier)
```

## Title fallback discipline

When persisted state is missing, the chrome title falls back to `''` (empty), **not** the `type.id` URL-token literal. Reason: the cold-start fragment body typically carries a `data-preview-title-hint` data attribute that the surface's `_restoreBody` chain reads. Surfacing the URL-token (e.g. `'article.7'`) as the title is worse UX than empty (chrome stays clean while the body fetch hydrates).

## Tradeoffs accepted

- **URL length scales with depth** — defensive cap (`MAX_STACK_DEPTH=10`) bounds it. Sharing depth-10 links is itself degenerate.
- **Cold-start latency** — N parallel fetches for N-deep stack. Each frame's fragment endpoint is independent; no waterfall.
- **Forward-nav at depth>1 with no snapshot** — content flash bounded to the deepest non-snapshot frame, not the whole stack.

## Why this generalises

The contract lives entirely below the public API of the preview-surface store (`open / push / pop / close / update`). Surface implementations that already use the API don't migrate. New surfaces add **one** entry to:

- `OpenType` enum
- `URL_PATTERN_BY_TYPE` map
- `resolve_frame_seed` per-type branch (server-side title lookup)

That's it. Three additive lines per new surface; no protocol changes.

## Bookmark-survival invariant

The surface URL (`/articles/`) MUST stay name-stable across the migration — same URL, same name, new view body. Bookmarks against the legacy detail URL (`/articles/<pk>/`) get a 302 to `/articles/?open=article.<pk>` (same shell, drawer pre-opened). The redirect is callable-only; the legacy view body retires in a later cleanup IDEA. Without this invariant, every saved bookmark breaks at migration.

## State-mutation patterns once the contract is in place

The URL contract above defines the *shape* of the stack. These patterns concern the *mutation surface* — how callers read and write to `store.stack` without breaking the contract. Surfaced during the second wave of state-refresh work that landed atop the URL stack.

### `store.top` is a snapshot getter, NOT a mutable reference

Convention from the Alpine store: the `top` getter computes a plain object from `stack[stack.length - 1]` each call. It mirrors `{type, identifier, title}` plus whichever fields are exposed publicly — but it does **not** expose `url`, and writes to it land on a throwaway object that's gone the next reactive read.

```js
// ❌ Wrong — looks fine, silently no-ops; the snapshot is discarded
surface.top.title = 'New title';
surface.top.url = '/articles/ui/detail/7/';   // 'url' isn't on the snapshot anyway
surface.top.snapshot.bodyHTML = '';            // mutation lost on next read

// ✅ Right — mutate the backing store entry directly
const stack = surface.stack;
const idx = stack.length - 1;
stack[idx] = { ...stack[idx], title: 'New title', snapshot: { ...stack[idx].snapshot, bodyHTML: '' } };
```

The trap re-surfaces whenever a caller reads `top` to inspect state, then keeps the same reference assuming it's live. It isn't. Any write path needs `store.stack[idx]`. Pair this rule with a docstring on the getter and a test that does `surface.top.title = 'x'; expect(surface.top.title).not.toBe('x')`.

### Walker rebind contract — dispatch all three HTMX events on manual swaps

When a state-refresh walker (or any module replacing DOM via `innerHTML` / `outerHTML` outside HTMX's own swap path) hands a freshly-fetched fragment to the page, it must re-fire the HTMX rebind events. Different consumer modules subscribe to different events — some on `htmx:afterSwap` only, some on `htmx:afterSettle`, some on `htmx:load`. Dispatching all three on the swapped element is the only guarantee everyone rebinds:

```js
function _rebroadcastSwap(target) {
    for (const name of ['htmx:afterSwap', 'htmx:afterSettle', 'htmx:load']) {
        target.dispatchEvent(new CustomEvent(name, {
            bubbles: true,
            detail: { elt: target, target, successful: true, requestConfig: {} },
        }));
    }
}
```

Fire on the **swapped element**, not on `document` — events bubble UP. A listener on `document.body` will catch a dispatch on a descendant; a listener on `document.body` will **not** catch a dispatch on `document` (events don't propagate DOWN). Mirrors HTMX's own dispatch behaviour. See [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 3 for the bubble-direction rationale.

### Edit-frame guard — short-circuit refreshes when the user has in-flight unsaved input

A generic refresh walker that re-renders the drawer body on every entity-mutation event will clobber an in-flight edit form. Add a guard that inspects the top frame's type before refreshing:

```js
function isTopInEditFrame(surface) {
    const top = surface.top;
    return Boolean(top && typeof top.type === 'string' && top.type.endsWith('-edit'));
}

function refreshEl(el, surface) {
    if (isTopInEditFrame(surface)) return;     // user has unsaved form open
    // ...fetch + swap + rebroadcast
}
```

The convention: frame types ending in `-edit` (`article-edit`, `event-edit`, etc.) are edit surfaces. The guard skips them. Save flow is exempt because the save endpoint flips the top frame BACK to the detail type before the refresh walker fires — by the time the walker runs, `top.type === 'article'` again. The guard guards against tangential refreshes (a sibling entity mutation, a snooze action, etc.) during edit.

### Universal edit→detail invariant in the walker, not per-entity

When the project has an invariant "every X edit form returns to the X detail view on save", codify it once in the walker (or dispatcher), not per-entity. Two consumers already pay back the deduplication; three+ multiply it:

```js
function flipDrawerEditFrameOnSave(surface, payload) {
    // payload = { type: 'article' | 'event' | …, id: <pk>, action: 'saved' }
    if (payload.action !== 'saved') return;
    const idx = surface.stack.length - 1;
    const top = surface.stack[idx];
    if (!top || top.type !== `${payload.type}-edit`) return;
    surface.stack[idx] = {
        ...top,
        type: payload.type,
        url: `/${payload.type}s/ui/detail/${payload.id}/`,
    };
    // Trigger the walker to fetch + swap the detail body.
}
```

URL conventions live as a project-level pattern map (mirrors `URL_PATTERN_BY_TYPE` from the URL contract). Per-entity files own only entity-specific cosmetics (title hints, post-save toasts, etc.). New entities inherit the routing for free.

### Empty-snapshot fallback in pop / popstate handlers

Cold-loading via `?open=parent&push=child` renders only the TOP frame's body — parent frames' snapshots are empty. Browser back at depth>1 then restores an empty body. Guard in both `store.pop()` and the popstate handler:

```js
const newTop = surface.stack[surface.stack.length - 1];
if (newTop.snapshot && newTop.snapshot.bodyHTML) {
    _restoreBody(newTop.snapshot.bodyHTML);
} else {
    _loadFrameContent(newTop);    // lazy-fetch on first pop
}
```

Lazy fetch is the right call here — eager pre-fetch would explode traffic on every reload. Known downstream: a sibling `_abortInflight()` can cancel the lazy fetch mid-flight; tolerate the cancellation, the next pop retries.

### `data-preview-route="open"` attribute for back-navigation links

When a link inside the drawer means "navigate to a sibling/parent surface" rather than "stack a new frame on top", route via `open()` (REPLACES stack) instead of the default `push()` (stacks). The convention is an explicit attribute on the anchor:

```html
<a href="/articles/ui/detail/7/"
   data-preview-link
   data-preview-type="article"
   data-preview-identifier="7"
   data-preview-route="open">
    ← Back to article
</a>
```

The drawer's click router checks `data-preview-route`; absent attribute stays default-push for back-compat. Apply to: parent-backlinks, "switch entity" navigation between two siblings in the same frame, "navigate up the hierarchy" links. Future routing consolidation: a single `routeIntent({ frame, intent })` dispatcher absorbs all routing decisions — the attribute becomes one of N intents.

## Reference

When this contract is added by a downstream IDEA on top of an upstream preview-drawer foundation IDEA, file the cross-IDEA backref per [`RULE_cross-idea-amendments`](../../../rules/RULE_cross-idea-amendments.md).

**Last Updated**: 2026-05-14
