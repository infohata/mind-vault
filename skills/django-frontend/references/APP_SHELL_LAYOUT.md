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
