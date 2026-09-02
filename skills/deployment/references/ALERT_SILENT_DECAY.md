# Alerts that stop working, silently

An alert that breaks loudly is a nuisance. An alert that stops being *able* to detect its subject
keeps evaluating, keeps reporting nothing, and its silence is indistinguishable from good news. That
is the failure class this reference is about, and every pattern here was found the same way: not by
the alert firing, but by someone checking whether it still could.

The four failures below are independent, and a monitoring stack can carry all of them at once.

## When to use

Read before changing an alert rule that consumes a metric someone else emits, before retargeting a
rule to a differently-named series, before widening a suppression window, and any time an alert is
described as "noisy". Three of the four cases below present as noise or as quiet, and the correct
response is the opposite of the obvious one in each.

---

## 1. A metric can change MEANING without changing its name

The dangerous change is not a rename. A rename breaks the rule loudly: `time() - <absent series>`
yields no vector, the alert goes permanently silent, and — if a coverage guard exists — something
says so. **A meaning change breaks nothing and is far worse**, because the rule keeps producing a
result and the result is wrong.

**Worked example.** A backup emitted `last_change_at_seconds`, meaning *the payload's contents
actually differed*. A consuming repo alerted on it to catch a stager that had frozen: backups
succeeding forever while capturing a snapshot that never changes. The producing team then split
their change gate into two tiers — state changes upload immediately, log-only changes defer — and
`last_change_at_seconds` came to mean *something was uploaded*, including an upload carrying nothing
but a longer log file. On a busy subject the gauge is now permanently fresh, so the rule can never
fire again. Nothing errored. The consuming repo's alert simply stopped being able to see the thing
it existed for, and reported that as silence.

### The protocol

**Producer side.** A meaning change to an exported metric is a **MINOR at minimum**, never a patch,
and the release note must say *"a rule written against the old semantics reads the new world wrongly
rather than not at all"* in those terms. Better: **emit a new name for the new meaning and leave the
old name carrying the old one.** That converts a silent semantic break into an additive change. In
the worked example the producer did exactly this — `last_state_change_at_seconds` kept the original
meaning — which is the only reason the consumer could be repaired rather than rebuilt.

**Consumer side.** When a producer's release notes mention a metric you alert on, the question is
not "did the name change" but **"does my rule still distinguish the thing it was written to
distinguish?"** Grep your rule files for the metric name on every producer upgrade. A rule file that
documents *what each series means* — not just what it thresholds — is what makes that grep useful.

⚠️ **Version-pin the semantics in a comment next to the expression.** The rule's threshold is
usually well-commented and its *input's meaning* usually is not, which is backwards: a threshold is
a judgment you can re-derive, and a meaning is a contract with another team.

---

## 2. A conditionally-emitted series needs a coverage guard — scoped to TOTAL absence

**The retarget in case 1 is a trap, and the trap is more general than metrics.**

The replacement series was written *only by a run that actually found a state change*. So it does not
exist on a subject until that subject's first real change — which, for something that moves on a
scale of weeks, can be a long time. A rename on its own therefore yields `time() - <absent series>`,
no vector, and **a rule that silently covers fewer subjects than it appears to.**

This is the same shape as a lifecycle rule matching zero objects, a linter whose glob matches no
files, and a test suite whose only assertions are negative. In every case the artifact exists, runs,
and reports success, and its success is uninformative. **A rule needs a denominator.**

### Scope the guard to total absence, not per subject

The obvious guard — per-subject existence, in the shape of "this subject is scraped but exposes no
such series" — is wrong here, and getting this wrong is how the guard itself gets muted:

```promql
# WRONG for a conditionally-emitted series: fires on every healthy subject
# that simply has not had its first qualifying event yet.
up{job="..."} == 1 unless on(job, subject) svc_last_state_change_at_seconds
```

One subject legitimately having no event yet is **normal**, and on a quiet estate that alert sits
firing for weeks against a correct system. Zero coverage across the *whole job* is a different
claim — it cannot be explained by one quiet subject, and it is exactly the state in which the rule
above is worthless:

```promql
(count(svc_last_state_change_at_seconds{job="..."}) or vector(0)) == 0
  and (count(up{job="..."} == 1) or vector(0)) > 0
```

Three parts, each load-bearing:

- **`or vector(0)` on the left.** Without it, `count()` over an absent series returns an *empty
  vector*, the comparison yields nothing, and **the guard against silence is itself silent** — the
  same joke twice. This is the single most likely way to write this rule wrong.
- **The `up` clause on the right.** Keeps it quiet when nothing is scraped at all; that is the
  host-down alert's business, and firing here just adds noise to an outage that is already loud.
- **A `for:` long enough to ride out a rollout**, since a freshly deployed or rebuilt estate
  legitimately has zero coverage until its first qualifying event.

### Pin the scoping with a test that fails on the wrong version

The partial-coverage case is the one a future maintainer will "improve" into a per-subject check.
Write the test that fails when they do:

```yaml
# one subject HAS the series, another does not -> the guard must stay SILENT
```

Mutation-verify it. Reverting the retarget, renaming the guard, making it per-subject, dropping the
`or vector(0)`, and dropping the `up` clause should each turn the suite red.

---

## 3. Suppression windows are pinned to a schedule someone else owns

A mute window is written against a maintenance job's observed timing. **The job's owner is under no
obligation to tell you when it moves, and nothing fails when it does.** The window simply stops
covering it, the alert starts arriving again, and it reads as *"this alert is noisy"* — which ends
with someone switching it off.

Suppression config therefore **degrades silently and in the noisy direction**. That is the opposite
of most config drift, which fails closed, and it is why suppression needs periodic re-measurement in
a way that thresholds do not.

**Worked example.** Windows written against a nightly job covered it correctly for weeks. Measured
again over 30 days at one-minute resolution: **30 of 64 firing episodes escaped them** — about one
notification a day. Two causes, both drift rather than mistakes. A burst had appeared at an hour
with no window at all. And another burst had *grown past* the end of the window nominally covering
it, so 15 of its 19 nights escaped a window that looked correct by inspection.

### The practice

- **Every window carries its measurement date and the observed bounds it was derived from.** A bare
  `01:00–01:30` tells a future reader nothing about whether it is still true.
- **Set each end to the latest observed end plus margin — a bound, never a pin.**
- **Treat a rising escape count as evidence the schedule changed**, not as a reason to widen further
  on reflex. Widening on reflex is how a suppression window grows until it covers the incident.
- **Replay before and after.** The same measurement window, old config vs new, is the behavioral
  test — and it is the only thing that distinguishes "I widened it correctly" from "I widened it".

### ⛔ Never suppress an outlier because it is inconvenient

In the worked example one episode escaped a window that was left deliberately un-widened: a subject
**twenty-one minutes** behind, an order of magnitude outside the routine band, and the only
serious event in the whole 30-day sample. Widening that window to reach a clean escape count would
have suppressed **the single real signal in the month**.

**Suppress the reproducible; never the exceptional.** When an escape analysis leaves a handful of
survivors, the correct outcome is usually that those survivors *are the alert working*. Check what
they are before tuning them away — a metric that goes to zero escapes is a warning sign, not a
target.

---

## 4. Rule state is not delivery — measure at the notifier

A rule engine's own alert-state series (`ALERTS` in Prometheus, and its equivalents elsewhere)
records **what the rule engine decided**. It says nothing about what a human received. Between the
two sit routing, grouping, inhibition, throttling, and suppression windows — any of which can drop a
firing alert entirely, and one of which is usually the thing you are debugging.

Reading rule state to answer "was anyone woken up?" is reading a proxy and calling it the thing.

```promql
# what the rule engine decided
ALERTS{alertname="...", alertstate="firing"}

# what was actually SENT  <- the question you meant
increase(alertmanager_notifications_total{integration="..."}[24h])
increase(alertmanager_notifications_failed_total{integration="..."}[24h])
```

**Worked example.** Three alerts fired overnight. Exactly one reached a human: two of the three sat
inside suppression windows and the third did not. Only the notifier counter distinguishes those
cases, and the gap it revealed had existed unnoticed since the windows were written — because every
prior investigation had looked at rule state, where all three look identical.

⚠️ **Beware the sliding-window artifact** when you range-query a counter: `increase(...[10m])` at a
5-minute step reports the same notification in consecutive buckets. Take the total over the whole
window for the count, and use the range only to locate *when*.

⚠️ **`send_resolved` doubles the count.** One incident that fires and clears is two notifications.
Two messages does not mean two problems.

---

## The thread running through all four

Each of these is an instrument that kept reporting after it stopped being able to measure. The
generalisation worth carrying into any monitoring change:

> **Ask what the check emits when it CANNOT do its job.** If the answer is "the same thing it emits
> when everything is fine", the check has no diagnostic value and something else must supply the
> denominator.

## Related

- [`MONITORING.md`](MONITORING.md) — setting monitoring up in the first place
- [`../../shell/references/EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md`](../../shell/references/EVIDENCE_SCRIPTS_AND_FALSE_CLEANS.md) — the same "green means nothing" class in verification scripts
