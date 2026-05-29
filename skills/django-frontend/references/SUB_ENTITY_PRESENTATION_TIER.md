# Sub-entity presentation tier — bounded inline drilldown vs unbounded sub-surface + teaser

When migrating an admin dashboard onto an app shell (workspace · centre · preview drawer), each
**sub-entity collection** owned by the dashboard entity needs a presentation decision. There are two
tiers, and the choice is driven by **one property: is the collection bounded or unbounded/historical?**

| | **Bounded** sub-entity | **Unbounded / historical** sub-entity |
| --- | --- | --- |
| Examples | scopes, properties, roles — a small finite set | invitations, members/users, billing/orders — grows without ceiling, accrues history |
| Dashboard surface | **inline drilldown** in the preview drawer (row → edit, "+ New" → stub, inline delete); **no standalone surface** | a **bounded teaser** (recent/actionable slice only) + a "Manage →" link |
| Full collection | the drawer *is* the full set | a **dedicated filterable centre sub-surface** at an additive URL (`/<parent>/<pk>/<children>/`) with a status/scope filter |
| Why | the whole set fits in a drawer; a separate page would be empty ceremony | a drawer can't hold unbounded history; the dashboard must stay bounded, so history moves off it |

## The teaser is a bounded slice, not "the first N"

A teaser for an unbounded collection must show a **naturally bounded, actionable** slice — not
`queryset[:5]`. The canonical cut: **the actionable state always** (e.g. pending), **recently-changed
terminal states within a short window** (e.g. accepted/cancelled in the last 7 days), and **omit the
noisy decayed states** (e.g. expired — token-decay spam is the worst teaser content). Apply a
per-identity priority so one entity doesn't appear twice (a pending row wins over a stale terminal row
for the same email). The point is the dashboard stays a fixed-height summary regardless of how much
history accrues; the full truth lives one click away on the sub-surface.

> The teaser's "recently-changed" window keys on a timestamp — so a bulk status transition done via
> `QuerySet.update()` must set that timestamp explicitly, or recently-changed rows silently fall out
> of the window. See [`../../django/references/QUERYSET_UPDATE_BYPASSES_AUTO_NOW.md`](../../django/references/QUERYSET_UPDATE_BYPASSES_AUTO_NOW.md).

## Sub-surface conventions

- **Additive URL, not a replaced one.** `/<parent>/<pk>/<children>/` is explicit and RESTful and
  doesn't disturb the bookmark-survival contract (which forbids *breaking* legacy URLs, not *adding*).
- **Keep the top-nav highlight on the parent.** A sub-surface is a drilldown of the parent entity, so
  `active_surface` stays the parent's — the workspace pane swaps to the filter, the centre to the
  list. Reached from the teaser via a `data-shell-nav-link` region-swap, not a full navigation.
- **Reuse the existing send/mutation service verbatim.** Only the view/chrome around it changes;
  the migration is a presentation change, not a domain-logic rewrite.
- **One uniform permission selector** across teaser, sub-surface, and every row action — gate the
  affordance and the endpoint off the same `user_can_admin_<x>` (see
  [`../../django/references/PERMISSION_GATE_PROBE.md`](../../django/references/PERMISSION_GATE_PROBE.md)).

## When this fires

The decision recurs for every dashboard-owned collection across a shell-migration sprint. Establish
the *first* unbounded sub-entity as the reference implementation; siblings (members, billing, orders)
inherit the same tier wholesale. If a "bounded" set later turns out to grow unboundedly, promote it to
the second tier — the drawer drilldown was the tell that it was assumed finite.
