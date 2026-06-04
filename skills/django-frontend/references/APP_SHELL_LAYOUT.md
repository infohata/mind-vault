# App-shell layout — fixed viewport + per-pane scroll containers

**When this fires**: building a single-page-feel app shell (Slack/Discord/Gmail-style: top nav + workspace pane + centre + preview pane) where the document never scrolls — every scroll happens inside one of the named panes. The django-frontend SKILL.md body's app-shell section holds the firing-conditions stub; this reference holds the layout primitives + load-bearing CSS rules + scroll-container helper + test contract.

## Layout primitives

```scss
// Scope the html-overflow override under a class so legacy non-shell pages
// (still on the document-scroll layout) are unaffected.
html.shell-html {
    height: 100vh;
    height: 100dvh;       // 100dvh adapts to mobile address-bar collapse
    overflow: hidden;     // defeats Bulma's default html { overflow-y: scroll }
}

.shell-body {
    display: flex;
    flex-direction: column;
    height: 100vh;
    height: 100dvh;
    overflow: hidden;     // body never scrolls either
}

.shell-main {
    display: flex;
    flex-direction: row;
    flex: 1 1 auto;
    align-items: stretch;
    min-height: 0;        // load-bearing — see "unstable child" below
}

.shell-center,
.shell-drawer__body {
    flex: 1 1 auto;
    min-height: 0;        // see "unstable child" below
    overflow-y: auto;     // pane is the scroll container
}
```

```django
{# Add the class hook on <html>; legacy base.html omits it #}
<html lang="..." class="h-full shell-html">
<body class="h-full shell-body">
    <c-nav-bar ... />
    <main class="shell-main">
        <c-drawer name="workspace" edge="left" ...>...</c-drawer>
        <section class="shell-center">{% block center %}{% endblock %}</section>
        <c-drawer name="preview" edge="right" ...>...</c-drawer>
    </main>
    {% include 'app_ui/_toast_container.html' %}  {# position:fixed, viewport-anchored #}
    <c-confirm-modal />                            {# position:fixed, viewport-anchored #}
</body>
```

**The "unstable child" rule (load-bearing)** — in a flex column or row, child elements default to `min-height: auto` (intrinsic content size). When you put `overflow-y: auto` on a flex child whose intrinsic size exceeds the parent, the child *grows the parent* instead of scrolling. Setting `min-height: 0` forces the child to honor the parent's height and scroll inside it. Apply at every flex chain link whose descendant has `overflow-y: auto`.

**Where elements live**:

- **Top nav, toasts, modals**: siblings of `.shell-main`, NOT inside any pane. `position: fixed` for toasts/modals stays viewport-anchored regardless of pane scrolling.
- **Sticky-within-pane** (drawer headers, table-row sticky headers, future "save bar" patterns): `position: sticky; top: 0` against the pane's scroll container — automatic once the pane has its own `overflow-y`.
- **Bottom-anchored elements** (chat composer, save bar): pane internals use a flex-column where the scroll-region is `flex: 1 1 auto; overflow-y: auto; min-height: 0` and the bottom anchor is `flex: 0 0 auto`. The composer never scrolls with the messages.
- **Scroll-anchor surfaces** (cursor-mode load-more, virtual-list patterns): the `[data-scroll-anchor]` element MUST be a real scroll container — declared `overflow-y: auto` AND content overflows. Under this layout that's automatic for any anchor child of `.shell-center` / `.shell-drawer__body`. Math is unchanged from window-scroll setups.
- **Edge-affordance lips** (edge rails, pane handles, reveal sliders on a scroll-snap shell): a fixed
  edge affordance must occupy a **reserved gutter**, never overlay edge-to-edge content (or it hijacks
  edge taps on the content beneath it). Reserve **permanently** on the always-present side (e.g. the
  centre pane's left, since the workspace pane always exists), and **gate** the conditional side (e.g.
  the right, only when the preview pane has content — the appearance-time reflow is masked by that
  pane's open-animation). Drive both insets off one `--shell-edge-gutter` token shared by the lip width
  and drawer padding. CSS mechanics: [`SCSS_RESPONSIVE_PATTERNS.md`](SCSS_RESPONSIVE_PATTERNS.md) §2
  (cascading custom property) + §3 (additive-padding collapse). The JS/architecture half — decoupling
  the rail from the snap engine, the iOS fixed-in-transformed-ancestor trap, the z-index ladder, and
  the adjacent-pane reveal model — lives in
  [`mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md`](../../mobile-ux-polish/references/EDGE_AFFORDANCE_RAILS.md).

## Shared scroll-container helper

When client code (preview-stack push/pop snapshot, scroll-anchor walk-up, virtual-list math) needs to find the closest scrolling ancestor, share one walk-up implementation:

```javascript
// scroll-utils.js — loaded blocking before any consumer.
(function () {
    'use strict';
    function findScrollContainer(el) {
        if (!el) return document.scrollingElement || document.documentElement;
        let node = el;
        while (node && node !== document.documentElement) {
            const style = window.getComputedStyle(node);
            const overflowY = style.overflowY;
            if ((overflowY === 'auto' || overflowY === 'scroll')
                && node.scrollHeight > node.clientHeight) {
                return node;
            }
            node = node.parentElement;
        }
        return document.scrollingElement || document.documentElement;
    }
    window.uiScrollUtils = window.uiScrollUtils || {};
    window.uiScrollUtils.findScrollContainer = findScrollContainer;
})();
```

The `scrollHeight > clientHeight` check matters: an ancestor declared `overflow-y: auto` but not currently overflowing returns scrollTop=0 silently, which is the "scroll restore is a no-op" symptom. Filter to elements that ACTUALLY scroll right now.

## Acknowledged regressions when migrating from document-scroll

- **Window-scroll readers go quiescent on shell pages**. Any module reading `window.scrollY` (e.g. mobile nav-hide-on-scroll-down feature, popover positioning that adds `window.scrollY` to absolute coordinates) sees `0` forever because the document doesn't scroll. Annotate in-source and route the trigger to the active pane's scroll or a gesture in a follow-up. Legacy non-shell pages keep working.
- **Modal scroll-position snapshots become no-ops**. The classic `scrollY = window.scrollY; modal.show(); ...; window.scrollTo(0, scrollY)` pattern saves 0, restores 0 — benign but worth annotating for debuggability.

## Shell-global context keys are reserved — namespace per-surface context

The shell base renders global chrome from a fixed set of context keys — a nav component like `<c-nav-bar :items="nav_items" />`, a workspace title, the current user, etc. A **surface fragment view** that builds its own context dict and reuses one of those global key names (e.g. its own `nav_items` for an in-surface section nav) **clobbers the shell-global value**. The global component then receives the surface's shape; the mismatch surfaces as a hard template crash — classically `{% url '' %}` / `NoReverseMatch` when the component iterates items that lack the expected `url` / `name` fields.

❌ TRAP — surface view reuses a shell-global key:
```python
def surface_shell_context(request, ...):
    return {"nav_items": [...], ...}   # clobbers <c-nav-bar :items="nav_items"> → {% url '' %} crash
```

✅ FIX — namespace every per-surface context key:
```python
    return {"surface_nav_items": [...], ...}   # shell-global nav_items stays intact
```

**Rule**: treat the shell base template's context keys as a reserved namespace; per-surface views prefix their own (`<surface>_nav_items`, `<surface>_filters`, …). The collision is invisible until the global component iterates the wrong shape, so grep the base/shell templates for `:prop="<key>"` and `{{ <key> }}` before naming a surface context key.

## Settings-hub nav WITH per-section filters: bare `hx-get` + OOB filter swap, not a full fragment re-render

A settings-hub surface (vertical section nav in the workspace, active section in the centre) switches sections with a bare `hx-get` → `.shell-center` (centre-only swap; workspace stays mounted). When the workspace **also carries per-section filters** (a different filter set per section — status on one, date-range on another), there's a temptation to switch the nav to a **full shell-fragment re-render** (workspace + centre) so the correct filter set appears on navigation.

Don't. A full re-render **re-mounts the workspace drawer**, replaying its entry animation on every section click — visibly janky. Instead:

- Keep section nav as a bare `hx-get` → `.shell-center` (centre-only).
- Have the fragment response **OOB-swap only the filter region** (`hx-swap-oob` on a `#…-filters` container) so per-section filters update in place while the drawer, nav, and any context/org switcher stay mounted and un-animated.

```html
<!-- fragment response: centre body + an OOB filter-region redraw -->
<div id="surface-section-body"> … </div>
<div id="surface-filters" hx-swap-oob="true"> … per-section filters … </div>
```

**Rule**: re-render the smallest region that changed. A workspace holding *static* nav can ride a full fragment swap; a workspace holding *stateful* chrome (filters, a context switcher, scroll position) must keep that chrome mounted and OOB-swap only what changes. An animation replay on navigation is the tell that you swapped too much.

## Test contract

Render-and-assert smokes the class hooks; manual eval / browser-driver tests verify behavior:

```python
def test_html_carries_shell_html_class_for_overflow_scope(self):
    response = self.client.get('/some/shell/surface/')
    self.assertIn('shell-html', response.content.decode('utf-8'))

def test_scroll_utils_loaded_before_consumer(self):
    """Order is load-bearing — scroll-utils must parse before consumers."""
    body = response.content.decode('utf-8')
    utils_idx = body.find('scroll-utils.js')
    consumer_idx = body.find('consumer-using-uiScrollUtils.js')
    self.assertLess(utils_idx, consumer_idx)
```

Render-and-assert can't probe computed CSS or measure scroll behaviour — that's a manual-eval gate (per-pane scrolls independently, sticky chrome stays anchored, no double-scrollbar at any viewport, etc.) or a browser-driver suite (Playwright / similar) once one is available.
