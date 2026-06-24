# Client-side rendering of LLM / markdown output — sanitizer + link-reroute traps

Two non-obvious traps when a browser renders markdown that originated from an LLM
(AI chat answers, streamed + persisted history) through a `marked`-style pipeline.

## 1. The input tag-stripper must be tag-SHAPED, not "any `<…>`"

A common "sanitize HTML before markdown" step strips tags with a regex like:

```js
text.replace(/<[^>]*>/g, '')   // WRONG — eats prose, not just tags
```

`/<[^>]*>/g` matches **any** `<…>` span, so it silently destroys legitimate prose:

```
"a <- b -> c"          → "a  c"          (arrow eaten)
"a <-> b"              → "a  b"
"if a < b and c > d"   → "if a  d"       (comparison operators eaten)
"use <value> here"     → "use  here"
```

Tighten it to only strip **tag-shaped** spans — `<` followed by a letter, `/`, or
`!` (comments/declarations):

```js
text.replace(/<\/?[a-zA-Z!][^>]*>/g, '')
```

Now a bare `<` followed by a space / digit / symbol survives (the markdown renderer
then escapes the stray `<` to `&lt;`), while real tags and comments still strip.
**XSS is unaffected**: `<script>`, `<img onerror=…>` start with `<`+letter and are
still removed; `< img …>` (space after `<`) isn't a valid HTML tag per CommonMark so
the renderer escapes it as text anyway. (This is INPUT pre-sanitization; the real
XSS defense is still the renderer's own escaping / output sanitize.)

## 2. The model emits fully-resolved URLs, not your link pseudo-scheme

If the app uses an internal link **pseudo-scheme** (e.g. `article:5`, `faq:10`) that
a renderer rewrites to a real path at render time, do NOT assume the LLM emits that
scheme. In practice the model emits the **already-resolved URL** — relative
(`/articles/5/`) or **same-origin absolute** (`https://host/articles/5/`) — and
persisted chat history stores that raw markdown. A reroute that only matches the
pseudo-scheme misses every real-URL citation → they full-navigate instead of opening
in-app (drawer / SPA surface).

Make the link parser a **superset**: try the pseudo-scheme first, then **reverse-match
already-resolved URLs** against the same server-seeded path templates —

- relative path (`/articles/<id>/`) and same-origin absolute (strip origin, compare);
- **same-origin only** — external URLs must navigate normally (never rerouted);
- keep the original href as the graceful no-JS / middle-click fallback; the in-app
  handler derives its target from the matched `{type, id}`, not the href.

## 3. Persisted history is re-rendered client-side — one hook covers both

When assistant messages are stored as **raw markdown** and emitted `|safe`, the
**client** re-renders history through the same `marked` pipeline as the live stream.
So a fix in the client renderer (or its post-render hook) covers **live + history**
with no server-side change. Corollary: don't reach for a server-side markdownify fix
for a client-rendered surface — verify which side actually renders first (check
whether the template emits raw markdown vs pre-rendered HTML).
