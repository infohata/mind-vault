# Active-state tracking — `aria-current="true"` + CSS `:has()` instead of JS class toggling

**When this fires**: a list of links has a "currently selected" item that should style differently. The obvious shape — JS `classList.add('--selected')` / `classList.remove('--selected')` driven by `Alpine.effect` or click handler — creates two sources of truth (store state + DOM class) that JS has to keep in sync. The django-frontend SKILL.md body's active-state section holds the firing-conditions stub; this reference holds the anti-pattern + fix + when-to-skip.

## The anti-pattern

```javascript
// Anti-pattern — JS owns the active-state class
Alpine.effect(function () {
    const top = Alpine.store('previewSurface').top;
    document.querySelectorAll('a[data-preview-link]').forEach(link => {
        const matches = top
            && link.getAttribute('data-preview-type') === top.type
            && link.getAttribute('data-preview-identifier') === String(top.identifier);
        link.parentElement.classList.toggle('list-row--selected', matches);
    });
});
```

Two sources of truth — `top` in the store, `--selected` class on the row — kept in sync by JS. Bugs surface when the server template renders one source (e.g. server sets `--selected` on the cold-start row) and JS races to set the other; or when a row gets re-mounted by HTMX swap and the JS hasn't re-walked yet.

## The fix — `aria-current="true"` on the link is the single source of truth, CSS `:has()` styles the parent

```javascript
// JS toggles the HTML attribute on the link, not a class on the parent.
Alpine.effect(function () {
    const top = Alpine.store('previewSurface').top;
    document.querySelectorAll('a[data-preview-link]').forEach(link => {
        const matches = top
            && link.getAttribute('data-preview-type') === top.type
            && link.getAttribute('data-preview-identifier') === String(top.identifier);
        if (matches) link.setAttribute('aria-current', 'true');
        else link.removeAttribute('aria-current');
    });
});
```

```scss
// SCSS targets the row via :has() — the CSS owns the visual,
// the HTML owns the truth. No JS class toggling on the parent.
.list-row {
    &:has(a[data-preview-link][aria-current="true"]) {
        border-color: var(--color-primary);
        background-color: var(--bg-tertiary);
    }
}
```

Server template emits the attribute on cold-start hits — same attribute name, same value:

```django
<a href="..." data-preview-link
   data-preview-type="article" data-preview-identifier="{{ item.id }}"
   {% if item.id|stringformat:"s" == selected_identifier %}aria-current="true"{% endif %}>
   {{ item.title }}
</a>
```

## Why this wins

- **Single source of truth**: `aria-current="true"` is the active state, period. Server cold-start emits it; JS keeps it in sync; CSS styles off it. No racing two state shapes.
- **Free a11y**: `aria-current="true"` is the standard ARIA attribute screen readers announce as "current page / current item". You'd want it anyway.
- **CSS `:has()` is well-supported**: Chrome 105+, Safari 15.4+, Firefox 121+. The browsers a Django+HTMX+Alpine project targets all ship it.
- **HTMX-swap-friendly**: when HTMX swaps the row, the new DOM carries whatever `aria-current` the server emitted; JS doesn't need to re-walk the DOM after the swap to fix the visual — `:has()` re-evaluates per-paint.
- **Test contract is mechanical**: `assertIn('aria-current="true"', body)` for the matching row, `assertNotIn` for non-matches. No "is the class on the right element" indirection.

## When NOT to use this pattern

When the visual state is genuinely client-only (a hover effect, a temporary "just clicked" pulse) — those don't need round-tripping, so a plain CSS `:hover` / `:active` / Alpine `x-bind:class` is right. The `aria-current` pattern is for state that has SEMANTIC meaning the server might also know about (selected item, current page, current step in a wizard).
