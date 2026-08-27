# Live pilot verification — measure the rendered thing, touch only what you own

Load when a change is verified by driving a deployed UI through the browser extension (a
staging "pilot" with real users on it). Four rules, each paid for once.

## 1. Never tap a side-effecting action on data you do not own — confirm the code path first

A "remind" tap on a payment request looked like a preview: on an *expired* or *template-less*
request the client opens a compose dialog, and every earlier tap had done exactly that. On a
live, templated request the same menu item hit the dedicated send endpoint and queued a real
email to a real guest. The tap itself is not the mistake; assuming the branch is.

- Before any tap that *can* send, post, charge or delete: read the row's state from the
  controller (template ids, expiry, ownership) and know which branch the tap takes.
- Smoke on a throwaway record you created for the purpose (own reservation, own contact —
  a non-deliverable placeholder address if the tool refuses to type the operator's own).
- A no-op tap is not evidence of nothing happening: check the object's send/history log.
  Synthetic taps on floated menus are flaky (2 of 4 silently did nothing); retry once, then
  verify the state, never assume.

## 2. Verify a styling fix on the rendered element, not on the CSS being present

"The rule is in the shipped bundle" is two claims short of "the element is styled." The rule
still has to **match** the element, and then still has to **win** against every other rule
that matches it. Both of those are facts about the DOM, not about the stylesheet — so grepping
the built CSS proves nothing, and a fix can be provably shipped and provably inert.

Read the live element, in this order:

- `el.className` / `el.attributes` — does it even carry the hook the selector targets? A
  component can take its class from a different config key than the one you set, in which
  case the rule matches nothing and specificity never enters into it.
- `el.matches(selector)` for the rule you wrote — match, or no match. Answers the above
  directly instead of by inference.
- `getComputedStyle(el)` — the value that actually won, which tells you whether you are
  fighting a losing selector or an unmatched one.

Then fix the cause the DOM shows, not the one the stylesheet suggests. The two dominant
causes are a **competing rule with higher specificity** (an element in two states at once —
"today" *and* "selected" — where the rule you did not write wins) and a **hook that was never
applied**. A framework-specific instance of both at once:
[MODERN_COMPONENT_FOOTGUNS](../../extjs-frontend/references/MODERN_COMPONENT_FOOTGUNS.md)
§20 (`floatedPicker` / selected-cell).

## 3. Inject → measure → iterate to zero → port

For parity work (a custom row that must read like a grid row), prototype on the live page:
append a `<style id="proto">`, measure text/button boxes with
`Range.getBoundingClientRect()` against the reference element's own boxes, adjust until every
delta is 0, and only then port the numbers to source. Column boxes and cell interiors are
two different units of parity — padding, `text-align`, weight, button anchoring — and mirroring
only the first survives three "pixel-exact" rounds.

## 4. Capture what the controller actually passes

When a component ignores an argument, wrap the factory in the page for one call:
`var o = Ext.widget; Ext.widget = function (x, cfg) { captured = cfg; return {show(){}}; };
ctl.method(); Ext.widget = o;` (the ExtJS factory here — substitute whatever call your
framework uses to build the component). One probe separates "the caller passes the wrong
thing" from "the component drops the right thing" — indistinguishable from the rendered
result, opposite fixes. A base class that silently discards a config is the second case:
[MODERN_COMPONENT_FOOTGUNS](../../extjs-frontend/references/MODERN_COMPONENT_FOOTGUNS.md)
§18 (`applyRecord` nulls a non-Model record).
