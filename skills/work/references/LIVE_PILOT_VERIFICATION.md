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

The "today" cell of a date picker stayed white after a theme-variable fix that was provably
in the shipped CSS. The rendered cell carried a different class (`x-selected` won over
`x-today`) and the panel lacked the ui class the rule targeted (the field's picker took its ui
from a different config key). Read the live element: `className`, `getComputedStyle(...)`,
and which stylesheet rules `el.matches(selector)` — then fix the cause the DOM shows.

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
ctl.method(); Ext.widget = o;` — it separates "we pass the wrong thing" from "the class
drops the right thing" in one probe (here: the class dropped it — see the ExtJS footgun on
`applyRecord`).
