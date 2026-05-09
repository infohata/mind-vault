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

## Reference

When this contract is added by a downstream IDEA on top of an upstream preview-drawer foundation IDEA, file the cross-IDEA backref per [`RULE_cross-idea-amendments`](../../../rules/RULE_cross-idea-amendments.md).

**Last Updated**: 2026-05-08
