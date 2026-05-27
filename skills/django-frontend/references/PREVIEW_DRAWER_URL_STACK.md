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

Fire on the **swapped element**, not on `document` — events bubble UP. A listener on `document.body` will catch a dispatch on a descendant; a listener on `document.body` will **not** catch a dispatch on `document` (events don't propagate DOWN). Mirrors HTMX's own dispatch behaviour. See [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) § 3 for the bubble-direction rationale. The **binder side** of this contract — what widget binders must do to receive these events robustly, and the latent break when a dispatcher diverges from it — is [`HTMX_WIDGET_LIFECYCLE.md`](HTMX_WIDGET_LIFECYCLE.md) § 6.

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

### The per-entity hard-gate reuse trap — a type-gated listener can't be shared by `<script>` include

Per-entity cosmetics files (`<entity>_actions.js`: drawer-close-on-delete, drawer-title-on-save) almost always open with a type discriminator that bails for foreign payloads:

```js
function onEntityChanged(event) {
    var payload = event.detail || {};
    if (payload.type !== 'article') return;   // ← the hard gate
    if (payload.action === 'saved') onSaveCosmetics();
    else if (payload.action === 'deleted') onDelete(payload);
}
document.addEventListener('entityChanged', onEntityChanged, { capture: true });   // document, not document.body — see ALPINE_HTMX_GOTCHAS §11
```

The trap: standing up a new entity surface and wanting the same drawer-close-on-delete behaviour, **reusing the file via `<script src="…/article_actions.js">` does NOT work** — the gate `payload.type !== 'article'` returns early for every `faq` / `event` payload, so the listener silently no-ops. The new entity's delete emits `entityChanged{type:'faq', action:'deleted'}`, the listener bails, the drawer stays open on the just-deleted record. The save-title cosmetic dies the same way.

It's **silent** — no console error; the page mostly works (the declarative `data-refresh-on` list refresh still fires — that's walker-owned, not gated), so the bug hides until someone deletes a record *while its drawer is open*. A template comment like "reused from the article surface — graceful no-op where article selectors aren't in the DOM" is the tell-tale wrong model: it doesn't no-op on missing *selectors*, it hard-returns on the *type gate* before touching the DOM.

The fix matches the per-entity convention: **each surface gets its own `<entity>_actions.js`** — a copy with type token, detail-body class, and title-hint attribute swapped (`'faq'`, `.faq-detail-body`, `[data-faq-title-hint]`). The detail-body partial usually already exposes the right selectors (a tell the original author intended a dedicated file and took the reuse shortcut). Generalising to a type-keyed dispatch table is only worth it past ~3 entities; below that the per-entity copy is lower-risk and matches the walker-vs-per-entity split above.

Sweep heuristic (`RULE_self-sweep` defensive-code sweep): a new shell template adding `<script src="…/<otherentity>_actions.js">` is the smell. Grep the included file's first `if (payload.type !== …)` line; if the literal doesn't match the new surface's type, it's a dead include.

### Resolving the trap at scale — one convention-driven listener, loaded globally

Once you hit ~3 entities (article + event + faq), stop copying per-entity files and **collapse to a single generic listener** — and the lever that makes it clean is that the per-entity files differ *only* by a type token and selectors that already follow a **convention** (`.<type>-detail-body`, `[data-<type>-title-hint]`, frame types `<type>` / `<type>-edit`). Derive those from the `entityChanged` payload's `type` instead of hard-coding them:

```js
function onEntityChanged(event) {
    var payload = event.detail || {};
    var type = payload.type;                 // 'article' | 'event' | 'faq' | …
    if (!type) return;
    if (payload.action === 'saved')   onSaveCosmetics(type);
    else if (payload.action === 'deleted') onDelete(type, payload);
}
function onSaveCosmetics(type) {
    var body = document.querySelector('.' + type + '-detail-body');
    if (!body) return;                       // surface not following the convention → no-op
    var hint = body.querySelector('[data-' + type + '-title-hint]');
    // … mutate stack top title …
}
```

Payoff: a **new** surface that follows the convention gets drawer-close + title-on-save for free — **nothing to register**, no per-entity file to forget. (This is also what kills the hard-gate trap above: there's no type-gate to mismatch, and no per-entity `<script>` to mis-include.) `RULE_rename-before-drop`: add the generic listener + switch the loading, verify green, then drop the old per-entity files.

Two non-obvious requirements when you consolidate:

1. **Load it GLOBALLY (from the base shell template), NOT per-shell `{% block extra_js %}`.** Shell-nav hot-swaps replace only the swap-target region; a per-shell `extra_js` script never loads when the user arrives at that surface via *cross-surface* shell-nav. A globally-loaded listener survives nav. (The per-entity files were per-shell — which means the old approach was *also* silently broken after cross-surface nav, not just the reuse case. Heavy surface-specific assets that genuinely can't be global — mermaid, rich-text editors — need a separate load-on-nav loader; that's a distinct concern from this always-on listener.)
2. **Register on `document`, NOT `document.body`** — see [`ALPINE_HTMX_GOTCHAS.md`](ALPINE_HTMX_GOTCHAS.md) §11 for the always-exists / `body`-null-crash rationale. Drawer-specific deltas: it catches an `entityChanged` dispatched directly on `document`, and `{capture: true}` fires it in the capture phase ahead of the bubble-phase refresh-walker — match whatever target the walker uses (walker on `document` → listener on `document` too). **Self-sweep note:** when porting an old listener faithfully, re-check the *target* — copying `document.body` from the files being consolidated carried the latent crash forward until review caught it.

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

### `openWith(prefixFrames, topFrame)` — natural-parent stacking with LCP-dedupe

When a card has a **natural parent** (an event linked to an article, a recurrence instance with a master, a comment under a message), clicking that card from arbitrary contexts should:

- Push the parent if it's not already in the drawer stack.
- Reuse the parent if the same one is already in stack (don't open twice).
- Replace the parent if a *different* one is in stack (don't leave a stale frame).

`store.open()` resets the stack on every click. `store.push()` always adds depth. Neither handles "intent extends current stack" vs "intent diverges from current stack" gracefully.

`openWith(prefixFrames, topFrame)` composes the existing primitives in ~25 LoC using a longest-common-prefix dedupe algorithm:

```js
function openWith(prefixFrames, topFrame) {
    const stack = surface.stack;

    // Walk current stack vs intent from the base; frames match by type+identifier.
    let L = 0;
    const minLen = Math.min(stack.length, prefixFrames.length);
    while (L < minLen
           && stack[L].type === prefixFrames[L].type
           && stack[L].identifier === prefixFrames[L].identifier) {
        L++;
    }

    if (L === stack.length) {
        // Current stack IS a prefix of intent: open|push remaining tail + top.
        if (stack.length === 0) {
            // Empty stack → drawer is closed; first frame needs open(), not push().
            if (prefixFrames.length === 0) {
                surface.open(topFrame);
                return;
            }
            surface.open(prefixFrames[0]);
            for (let i = 1; i < prefixFrames.length; i++) surface.push(prefixFrames[i]);
        } else {
            for (let i = L; i < prefixFrames.length; i++) surface.push(prefixFrames[i]);
        }
        surface.push(topFrame);
        return;
    }

    // Divergence at index L: pop down to L, then open|push the divergent root,
    // then push the rest.
    while (surface.stack.length > L) surface.pop();
    if (L === 0) {
        if (prefixFrames.length === 0) {
            surface.open(topFrame);
            return;
        }
        surface.open(prefixFrames[0]);
        for (let i = 1; i < prefixFrames.length; i++) surface.push(prefixFrames[i]);
    } else {
        for (let i = L; i < prefixFrames.length; i++) surface.push(prefixFrames[i]);
    }
    surface.push(topFrame);
}
```

### Server-side: `data-preview-stack-prefix` attribute

The natural-parent chain is computed **server-side** (the server knows the relationships; the client shouldn't have to). Emit it as a data attribute on the card / link the user is about to click:

```python
# project/templatetags/preview_stack.py
@register.simple_tag
def event_stack_prefix(event):
    """Return the natural-parent chain for an event card.

    Format: comma-separated "<type>.<id>,..." in base-first order.
    Empty string → orphan event → legacy open/push paths apply.
    """
    parts = []
    if event.linked_article_id:
        parts.append(f'article.{event.linked_article_id}')
    if event.recurrence_master_id:
        parts.append(f'event.{event.recurrence_master_id}')
    return ','.join(parts)
```

```django
<a href="{{ event.detail_url }}"
   data-preview-link
   data-preview-type="event"
   data-preview-identifier="{{ event.pk }}"
   data-preview-stack-prefix="{% event_stack_prefix event %}">
    {{ event.title }}
</a>
```

The attribute is **absent** for orphans → drawer's click router falls through to the legacy `.open()` / `.push()` path → existing surfaces don't migrate.

### Client-side: route on attribute presence

Both the outside-drawer document click handler AND the inside-drawer click handler check for the attribute:

```js
function _routePreviewClick(el) {
    const prefixAttr = el.dataset.previewStackPrefix;
    const topFrame = {
        type: el.dataset.previewType,
        identifier: el.dataset.previewIdentifier,
        url: el.href,
    };
    if (!prefixAttr) {
        // Legacy path — back-compat for surfaces that haven't opted in.
        return surface.open(topFrame);
    }
    const prefixFrames = _parseStackPrefix(prefixAttr);
    surface.openWith(prefixFrames, topFrame);
}

function _parseStackPrefix(str) {
    if (!str) return [];
    const out = [];
    for (const piece of str.split(',')) {
        const [type, identifier] = piece.split('.');
        if (!type || !identifier) continue;   // lenient parse — drop malformed
        out.push({ type, identifier });
    }
    return out;
}
```

Lenient parse mirrors `parse_open_param`'s contract from the URL stack section above — a malformed piece drops silently rather than poisoning the whole stack.

### Prefix frame metadata — pairing titles with the prefix CSV

`_parseStackPrefix` as drafted above produces frames as `{type, identifier}` only — **no title field**. When the drawer's chrome (back-affordance label, title slot) binds to `frame.title`, prefix frames born from `data-preview-stack-prefix` render empty: the back-affordance shows `"← Article: "` (type label only) and clicking back to a prefix-loaded parent leaves the title slot blank.

Cold-start hydration paths don't have this gap because the server-emitted seed JSON includes titles per frame. But the **closed-drawer-then-click path** that triggers `openWith()` bypasses cold-start entirely — it has only the tokens from `data-preview-stack-prefix`. The divergence-branch (`lcpLen === 0`) path has the same gap; it just gets exercised less often.

Surfaced by manual smoke after the `openWith()` empty-stack guard (above) made flow E reachable from a closed drawer. The empty-stack push gap had previously been hiding the title gap — when the drawer didn't open at all, no one noticed the prefix frames were title-less.

Fix: server emits a **parallel JSON array** of titles alongside the prefix CSV; JS parser pairs them by index.

**Server side — template tag returns titles in the same order as the prefix CSV:**

```python
import json
from django import template

register = template.Library()

@register.simple_tag
def event_stack_prefix_titles(event):
    """Return JSON-encoded titles parallel to ``event_stack_prefix``.

    JSON over CSV because raw titles carry commas/quotes/colons that
    break naïve splitters; ``ensure_ascii=False`` keeps non-ASCII
    glyphs unescaped (e.g. Cyrillic, Lithuanian, Polish diacritics).
    """
    titles = []
    if event.linked_article_id:
        # Prefer the GFK-prefetched ``content_object`` when the view
        # already loaded it (typical list path). Falls back to a cheap
        # ``.only('title')`` lookup so the tag stays correct on detail
        # pages / partial renders that don't prefetch.
        article = getattr(event, 'linked_article', None)
        if article is None:
            article = Article.objects.filter(
                pk=event.linked_article_id,
            ).only('title').first()
        titles.append(getattr(article, 'title', '') if article else '')
    if event.recurrence_master_id:
        master = getattr(event, 'recurrence_master', None)
        if master is None:
            master = Event.objects.filter(
                pk=event.recurrence_master_id,
            ).only('title').first()
        titles.append(getattr(master, 'title', '') if master else '')
    if not titles:
        return ''
    return json.dumps(titles, ensure_ascii=False)
```

**Template — second attribute alongside the existing prefix CSV:**

```django
{% event_stack_prefix event as stack_prefix %}
{% event_stack_prefix_titles event as stack_prefix_titles %}
<a href="{{ event.detail_url }}"
   data-preview-link
   data-preview-type="event"
   data-preview-identifier="{{ event.pk }}"
   {% if stack_prefix %}data-preview-stack-prefix="{{ stack_prefix }}"{% endif %}
   {% if stack_prefix_titles %}data-preview-stack-prefix-titles="{{ stack_prefix_titles }}"{% endif %}>
    {{ event.title }}
</a>
```

**Client side — `_parseStackPrefix` accepts a second argument and pairs by index:**

```js
function _parseStackPrefix(str, titlesJson) {
    if (!str) return [];
    let titles = [];
    if (titlesJson) {
        try {
            const parsed = JSON.parse(titlesJson);
            if (Array.isArray(parsed)) titles = parsed;
        } catch (_) { /* malformed → empty titles, lenient */ }
    }
    const out = [];
    const pieces = str.split(',');
    for (let i = 0; i < pieces.length; i++) {
        const piece = pieces[i].trim();
        if (!piece) continue;
        const [type, identifier] = piece.split('.');
        if (!type || !identifier) continue;
        const title = (typeof titles[i] === 'string') ? titles[i] : '';
        out.push({ type, identifier, title });
    }
    return out;
}
```

Both click handlers (outside-drawer + inside-drawer) forward both attributes:

```js
const prefix = _parseStackPrefix(
    el.dataset.previewStackPrefix || '',
    el.dataset.previewStackPrefixTitles || ''
);
```

**Lenient contract — symmetric with the prefix CSV:**

- Empty `titlesJson` → all frames get `title: ''`. Frames still produced.
- Malformed JSON → caught, empty titles. Frames still produced.
- Shorter titles array than tokens → trailing frames get `title: ''`. Frames still produced.
- Longer titles array → extra titles ignored.

Never throw; never poison the whole stack. The chrome's worst-case is "type label only" — same as the pre-pairing baseline — not a JS error.

**Why JSON over `|`-delimited CSV or URL-encoded CSV:**

- Titles contain commas (English: `"Hello, world"`), colons (`"Topic: subtopic"`), quotes (`"O'Brien's report"`), and full-Unicode glyphs. A simple split would corrupt them.
- HTML attribute autoescape handles JSON's `"` characters via `&quot;` — no extra escaping layer needed.
- `ensure_ascii=False` keeps the wire size small and the source readable in DevTools.

**Production prefetch contract:**

The title tag's DB fallback (the `.only('title')` lookup when the related row isn't prefetched) is functional but costs one query per row. To stay at O(1) queries per list-page, list views opting into the stack-prefix convention should prefetch:

```python
queryset = Event.objects.visible_to(user).select_related(
    'recurrence_master',
).prefetch_related(
    'linked_article',  # or 'content_object' if using GenericForeignKey
)
```

The pattern degrades gracefully when prefetch is missing — chrome shows the title via the fallback query, list view eats N extra queries until the prefetch is added. Acceptable for lists ≤ 50 rows; revisit if perf surfaces.

### The seven flows the algorithm handles

| # | Starting state | Click | Final stack |
|---|---|---|---|
| A | (empty) | article | `[article.7]` |
| B | `[article.7]` | counter on article.7 page | `[article.7]` (no-op) |
| C | `[article.7]` | event-42 linked to article.7 | `[article.7, event.42]` |
| D | `[article.7]` (stale) | event-99 linked to article.55 | `[article.55, event.99]` (REPLACE article.7) |
| E | (empty) | recurrence-instance whose master is event.10 | `[event.10, event.42]` |
| F | `[article.7]` | recurrence-instance under master event.10 linked to article.7 | `[article.7, event.10, event.42]` |
| G | (empty) | orphan event (no `data-preview-stack-prefix`) | `[event.42]` (legacy path) |

Why these matter: D is the killer flow. Without dedupe, the user can end up with a stale parent frame "above" the new child — confusing and incoherent. The LCP comparison catches divergence at depth 0 and pops it.

### Why this generalises

Any entity with a natural-parent relationship gets free natural-parent stacking by:

1. Adding the prefix computation to its server-side templatetag / serializer.
2. Emitting `data-preview-stack-prefix` on the link.
3. Done. The JS routing generalises; new entity types don't require JS changes.

Use cases: GFK chains generally (comments under messages under threads), recurrence masters with instances, attachment chains (article → attachment → annotation), or any other parent-child preview surface.

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
