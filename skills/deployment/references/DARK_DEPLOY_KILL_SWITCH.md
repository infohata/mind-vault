# Dark deploys and kill switches

Shipping a behaviour change to a system where a wrong write is expensive — a third-party database,
a billing ledger, anything whose rows you do not own. The ladder is **dark → shadow → live**, and
each rung answers a different question.

| Rung | Config | What runs | What it proves |
| --- | --- | --- | --- |
| **dark** | switch absent / `off` | new code loaded, **old rule decides** | the files parse and nothing fatals under real traffic |
| **shadow** | `shadow` | **both** rules computed, disagreements logged, **old answer returned** | where the two rules would differ |
| **live** | `on` | new rule decides, every decision logged | the change itself |

An unset **or unrecognised** switch value must fall back to the old behaviour, so a typo in config
cannot enable the new path. That is a one-line property with a large payoff: config edits are exactly
where a fat finger lands.

## The OFF position must be faithful PER CALL SITE

The trap that makes this reference worth reading.

When several call sites are collapsed behind one new helper, it is natural to give the helper one
`legacy` path — "the old behaviour" — and route every site through it. **Verify that the sites
actually agreed on what the old behaviour was.** They often do not, because they were written years
apart by different people.

A real instance: three call sites were unified behind a matching helper. Two matched records on a
single field; the third matched on that field **plus two others**. One shared `legacy` path meant the
third site would silently start matching on the single field alone — **looser** than before, in the
direction that fuses distinct records.

What makes it dangerous is how it presents:

- the switch says `off`
- the release notes say "no behaviour change"
- the tests pass, because they were written against the *helper's* idea of legacy
- the dark deploy is quiet, because the paths are low-volume

Nothing surfaces until data is already wrong. The fix is to make the legacy selector an **explicit
per-site argument**, not a single assumed default:

```php
resolve_record($db, $scope, $input, $mode, $logger, /* legacy */ 'strict_multi_field');
```

**Rule: before collapsing N call sites behind one flag, diff their existing behaviour pairwise. The
flag's OFF position has to reproduce each one, not the most common one.**

## Rollback stops future writes; it cannot unwind past ones

State this explicitly to whoever approves the rollout, because "we can roll back in seconds" is heard
as "this is reversible". For a config-switch rollback:

- **Reversible:** which rule decides from now on. Seconds, no deploy.
- **NOT reversible:** rows already written under the new rule. A record attached to the wrong parent
  stays attached after the flip back.

Consequences worth designing for:

1. **Log every decision in the live rung, not just the surprising ones.** Shadow logs disagreements,
   which is enough to *decide*; live needs the full trail, because it is the only way to answer
   "what got attached to what" after the fact. At low volumes this is a handful of lines a day.
2. **The blast radius is a rate, not a total.** Low write volume is a genuine safety property: a
   wrong rule discovered within a day costs a day's writes. Say the number out loud when sizing risk.

## Do not leave two hosts running different policies against one datastore

If several hosts write to the same schema, flipping one is not a "gradual rollout" — it is two
policies against one dataset. Records then differ by which host happened to serve the request, and
the resulting mess is attributable to nothing.

- **Dark and shadow are safe to enable everywhere at once** — neither changes what is written, and
  broad enablement maximises the sample.
- **The live rung is per-tenant / per-dataset, but all hosts serving that dataset flip together.**

## Shadow's blind spot: silence is ambiguous

Shadow that logs **only disagreements** cannot distinguish:

1. the path never ran,
2. it ran and both rules agreed (good news, invisible),
3. logging is broken.

At low volumes (1) is overwhelmingly likely, so an empty shadow log is **not** evidence the new rule
is safe — a conclusion that is very easy to reach on a quiet weekend. Either log agreements too, or
measure executions independently (request counts for the endpoints that reach the path) and report
"ran N times, disagreed M" rather than "no problems found".

Related: [`MONITORING.md`](MONITORING.md) ·
[`../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md`](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md)
for the deploy/rollback script contract itself.
