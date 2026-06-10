# Nav / chrome consolidation — one canonical component, fed by context

Doctrine for collapsing N near-duplicate copies of page chrome (navbar, header,
identity menu, status badges) scattered across templates into a single canonical
component. The duplication tax is the motivating bug class: an affordance added
to one copy silently misses the others, and every copy drifts independently.
These four rules came out of one such consolidation pass and generalize to any
server-rendered multi-surface app.

## 1. A variant that renders a different bar IS a fork

When consolidating, the tempting halfway point is one component with a
`variant` / `mode` prop whose branches render structurally different markup:

```html
{# ❌ the fork survived, it just moved inside the component #}
{% if variant == "public" %}
  <nav class="navbar is-light">…public markup…</nav>
{% else %}
  <nav class="navbar">…full markup…</nav>
{% endif %}
```

Two markup branches are two navbars under one filename — an affordance added to
one branch still misses the other, which is the exact bug consolidation exists
to kill. Collapse to **one markup tree** and feed it data: which links to show,
which badge counts, which identity affordance. Conditionals gate *slots and
items* (`{% if show_admin_links %}`), never parallel structures. If a surface
genuinely needs different *structure* (not different content), it isn't a
variant of this component — leave it a separate component and say so.

## 2. Single-slot placement policy for cross-surface affordances

An affordance that must appear "somewhere on every page" (a notification badge,
a pending-count pill) needs a **placement policy encoded once in the shared
chrome**, not a per-surface decision:

> In the app-nav when the page has one; otherwise in the header. Exactly one
> instance per page.

Per-surface placement produces pages with zero copies (forgot) and pages with
two (nav *and* header — which also breaks Playwright strict-mode locators, see
[`HTMX_ALPINE_WAITS.md`](HTMX_ALPINE_WAITS.md) § 9). The policy lives as one
conditional in the shared component; surfaces opt into nothing.

## 3. Identity-slot mutual exclusion

The anonymous affordance (Sign-in button) and its authenticated counterpart
(user menu) are the same *slot* in two states — render them at the same
position from one shared, mutually-exclusive block:

```html
{% if user.is_authenticated %}
  {% include "chrome/_user_menu.html" %}
{% else %}
  {% include "chrome/_sign_in.html" %}
{% endif %}
```

When the two are authored independently (user menu in the shared navbar,
sign-in hand-placed per public page), they drift in position and styling, and
public surfaces miss the sign-in entirely. One shared slot means one edit moves
both states on every surface — the consolidation payoff in its purest form.

## 4. Generation-vs-display tell — audit the render target first

After (or during) a chrome consolidation, a "feature X stopped working" report
often means the *display slot* was lost, not the feature: the data is still
generated server-side, but no element in the consolidated chrome renders it
(e.g. page titles still computed, but the canonical header has no slot bound to
them). Before debugging the generation path, check whether the value reaches
the template context and simply has no render target — `grep` the chrome for
the context key. Restoring a slot is a one-line fix; "debugging" working
generation code wastes the session.
