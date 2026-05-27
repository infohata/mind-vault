# Lazy-load heavy per-surface JS on HTMX app-shell navigation

## The problem

An HTMX app-shell hot-swaps one region (e.g. `#shell-swap-target`) via
`htmx.ajax('GET', url, {target:'#shell-swap-target', swap:'outerHTML'})`. A surface's
`{% block extra_js %}` lives **outside** the swapped region, so its heavy
per-surface bundles — a diagram renderer (MBs), a rich-text editor (hundreds of
KB) — only load on a **cold full-page load**, never when the surface is reached
via cross-surface shell-nav. Symptom: the feature silently doesn't work after
nav (diagram renders as raw fenced source; editor stays a bare `<textarea>`)
until a hard refresh.

Eager-globalising these heavy bundles (loading them on every shell page) is the
wrong fix — it's MBs of payload on surfaces that never use them. They need
**load-on-nav**, not always-on. (Small, null-safe behaviour scripts are a
different call — those can be cheap enough to globalise; see the "what stays
eager" note below.)

## The pattern — "declare once, render twice" + load-on-nav

### 1. One server-side manifest (single source of truth)

A module maps `surface-slug → asset-keys` and `asset-key → ordered relative static paths`
(the vendor lib **before** its init script — load order matters,
the init script depends on the vendor global). A builder resolves the paths to
URLs via `static()`.

```python
from django.templatetags.static import static

ASSET_BUNDLES = {            # RAW relative paths — NOT static()-resolved here
    'diagram': ('vendor/diagram.min.js', 'app/js/diagram-init.js'),
    'editor':  ('vendor/editor-bundle.js', 'app/js/editor-widget.js'),
}
SURFACE_ASSETS = {'articles': ('diagram', 'editor'), 'events': ('diagram', 'editor')}

def build_surface_asset_manifest(slug):
    # static() resolution happens HERE, at REQUEST time — never at module
    # import. Under ManifestStaticFilesStorage the staticfiles manifest isn't
    # loaded at import, so import-time resolution bakes stale/empty hashes.
    return [{'key': k, 'srcs': [static(p) for p in ASSET_BUNDLES[k]]}
            for k in SURFACE_ASSETS.get(slug, ())]
```

### 2. Two render paths from the one manifest (so they can't drift)

- **Cold full-page load:** `extra_js` renders `<script defer>` tags from the
  manifest (the proven static path — keep it; lazy-loading the cold path too
  would make the most common load depend on JS injection for content to render).
- **Nav-time fragment:** the swapped region carries the same manifest as a
  `data-*` JSON attribute with the **`static()`-resolved** URLs:
  `<div id="shell-swap-target" data-surface-assets='[{"key":"diagram","srcs":[…]}]'>`.

The client **cannot** hardcode static paths — they're hashed in production
(`ManifestStaticFilesStorage`). The server resolves and hands them over; the JS
just injects whatever `srcs` it's told. Asset *key* + *ready/init symbol names*
are stable (not hashed) so those live in a small JS registry.

### 3. A load-on-nav module with its OWN afterSwap listener

Separate from the nav-state/URL listener — it fires on **any** swap of the
region, however triggered (click, popstate, programmatic):

```js
document.addEventListener('htmx:afterSwap', function (evt) {
    if (!evt.detail || !evt.detail.target) return;
    if (evt.detail.target.id !== 'shell-swap-target') return;
    // Read the manifest off the FRESH node — after an outerHTML swap,
    // evt.detail.target is the DETACHED old node, so its attribute is stale.
    var node = document.getElementById('shell-swap-target');
    var manifest = JSON.parse(node.getAttribute('data-surface-assets') || '[]');
    manifest.forEach(function (b) {
        var entry = REGISTRY[b.key];
        // Guard a manifest key the client registry doesn't know (typo / renamed /
        // removed): skip + warn rather than throw and break the rest of the swap.
        if (!entry) { console.warn('[load-on-nav] no registry entry for', b.key); return; }
        ensureBundle(b.key, b.srcs).then(function () {
            entry.init(document.getElementById('shell-swap-target'));
        });
    });
});
```

- **Sequential injection**, vendor before init (await each `<script>`'s `onload`).
- **In-flight Promise map** keyed by asset-key, so two rapid navs don't double-inject.
- **Always re-init the swapped subtree** even when injection was skipped — the
  *content* is new on every nav; injection is what's conditional.
- Subscribe on `document`, not `document.body` — this module loads blocking from
  `<head>` where `document.body` is null at execution time.

### 4. ready() must validate the LAST global of a multi-script bundle

The trap: a bundle is `[vendor.js, init.js]`. If `ready()` checks only the
**vendor** global (`!!window.Vendor`), a **partial load** (vendor ok, init
script 404'd / errored) marks the bundle "ready" forever — re-injection is
permanently blocked, yet `init()` no-ops because the init global is missing. The
bundle is stuck half-loaded until a page reload.

`ready()` must require the **init-script's** global too, so a partial load
returns false → re-injects (both srcs) on the next nav → recovers:

```js
diagram: { ready: () => !!window.Vendor && typeof window.initDiagramIn === 'function', … }
```

### 5. The injected binder must be `readyState`-safe + idempotent

Two [HTMX widget lifecycle](HTMX_WIDGET_LIFECYCLE.md) rules stop being optional and become
**mandatory** here, because the binder is injected *after* `DOMContentLoaded`:

- **`readyState`-safe boot** (lifecycle §5) — a `DOMContentLoaded`-only boot never fires on a late
  inject, so neither the initial init nor the binder's own `htmx:afterSwap` listener registration
  happens, and subsequent swaps break too.
- **Idempotent init** (lifecycle §2) — the late inject fires *two* inits from one `onload`: the
  binder's own `boot()` inits the whole body **and** the loader calls `init(region)`. Both must
  no-op safely (the diagram renderer consumes its source nodes on render; the editor guards on an
  already-mounted set).

Expose a container-scoped `window.initXIn(root)` (lifecycle §4 — honor `root`) that the loader calls
on the fresh region; document the double-init where the explicit call lives so a future reader
tracing it in devtools isn't confused.

## What stays eager (NOT load-on-nav)

Shell-**infrastructure** scripts — the reactive framework (Alpine), HTMX itself,
the drawer / nav / toast / modal coordinators, the loader module — bind global
behaviour before any interaction and must be present on every page. Only
surface-**specific**, heavy-or-narrow assets are load-on-nav candidates. Mixing
the two up (moving an infra script to load-on-nav) breaks global behaviour
everywhere; classifying requires a per-script audit.

## Related references

- **[`HTMX_WIDGET_LIFECYCLE.md`](HTMX_WIDGET_LIFECYCLE.md)** — the shared (re-)init / teardown /
  idempotency / `readyState`-safe-boot contract every HTMX-swapped widget follows. §3–5 above are
  the injection-specific layer on top of it; the binder rules in §5 are that contract's §2/§4/§5.
- **[`DATA_ATTR_NAV_CONVENTION.md`](DATA_ATTR_NAV_CONVENTION.md)** — the `data-surface-assets`
  attribute is the same family as the `data-*-nav-link` markers: declarative markers on the
  swapped DOM consumed by a document-level JS handler, co-located with the region they describe.
- **[`VENDORING_JS_BUNDLES.md`](VENDORING_JS_BUNDLES.md)** — how to produce/install the heavy
  bundles this loads (CDN download or disposable-Node build → `static/vendor/`). Its
  integration-glue contract (discover on `htmx:afterSwap`, idempotent mount, teardown on
  `htmx:beforeSwap`) is the **always-loaded** counterpart; reach for *this* pattern instead when
  the bundle is too heavy to load eagerly and its `<script>` (in `extra_js`, outside the swap
  region) never executes on shell-nav.
- **[`MANIFEST_STATIC_FILES_STORAGE.md`](../../django/references/MANIFEST_STATIC_FILES_STORAGE.md)**
  — the sibling `static()`-timing trap: this pattern warns against resolving at module *import*
  (manifest not loaded yet); that one warns that resolved URLs are cached at process *start*, so
  `collectstatic` needs an app-server restart to take effect.

## Verification

- **Cross-surface e2e is the load-bearing gate** (Playwright): cold-load a
  surface that declares **no** heavy assets, shell-nav to a heavy surface, assert
  the feature actually renders (SVG present / editor `.ProseMirror` mounted). The
  cold-load path's existing e2e doesn't cover the nav-injection path — write the
  nav case explicitly.
- **Render-path unit tests** lock the server side: the manifest builder returns
  the right bundles in load order + `static()`-resolved; the fragment carries the
  `data-*` attribute; the full page still emits the static `<script>` tags
  (no cold-load regression); a no-asset surface's fragment carries an empty
  manifest.
- **A JS-source structural test** locks the loader contract (own afterSwap
  listener, fresh-node read, in-flight dedupe, ready() validating the init global,
  the binders' readyState-safe boot) — slice each `ready()` body to prove it
  checks the init global, not just the vendor.
