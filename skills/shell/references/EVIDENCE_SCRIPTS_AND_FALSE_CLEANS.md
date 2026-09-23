# Evidence scripts and false cleans

An **evidence script** is read-only and its entire product is a claim about the world:
"nobody hit the fault", "no tenant is affected", "the rate is unchanged". It changes
nothing, so it feels low-risk. It is not. A maintenance script that fails loudly wastes
an afternoon; an evidence script that fails *quietly* produces a green light, and someone
acts on it.

The contract in [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) covers
`--verify` proving an **effect** rather than "it ran". This reference covers the sibling
failures: a check that produced a number without ever having looked at anything, and the
one a step earlier still — an assertion that never executed, or that answered from the
branch written to handle trouble.

**Passing is the DEFAULT state of a broken check.** Every verdict of this kind is computed
as the *absence* of a failing signal, so anything that stops that signal being emitted
produces a positive result indistinguishable from a real one — and the code that stops it is
usually the code written to handle trouble, which reviews as careful. Absence, error,
unknown, unreachable and not-applicable have no natural representation in an exit status or
a comparison, so they get encoded as an ordinary value, and the value they land on is almost
always the benign one. The repair is one move in four forms: **make non-assertion
representable** — print the positive count beside every zero, require a positive value only
the designed flow can produce, give the unknown its own refusing branch, and treat an
assertion as evidence only once you have watched it go red against a mutant reproducing the
original defect's observable behavior, exit status and output included.

Two neighbours are *not* this failure and take a different fix. An assertion that ran and
returned a true answer about the wrong object is a proxy problem — the check interrogates
a stand-in for the thing the system consumes; re-point the check. A run whose universe could
not express the defect is a coverage problem
([`GREEN_RUN_UNIVERSE_TOO_SMALL.md`](GREEN_RUN_UNIVERSE_TOO_SMALL.md)); widen the population.
Here an in-scope assertion did not run, or ran and answered benignly — re-pointing and
widening both change nothing.

## The failure mode: a check that reports success without having run

These two outputs are byte-identical:

```
  faults found: 0        # scanned 130,000 lines, found nothing wrong
  faults found: 0        # scanned an empty file set, found nothing at all
```

Every layer of an evidence script can fail this way independently:

| Layer | How it silently produces nothing | What it looks like |
| --- | --- | --- |
| **Discovery** | glob matches no files; a `continue` drops one target of three | a clean report, one section shorter |
| **Filter** | the pattern no longer matches (route renamed, casing changed) | "no matching traffic" |
| **Parse** | log/output format changed; the field anchor misses | "0 errors" |
| **Aggregate** | the key is never populated, so the map stays empty | "no data for this period" |
| **Print** | the branch that would report it is unreachable | silence |

**A fix at one layer routinely leaves the identical shape at the layer above.** Observed
three times in a single review cycle on one set of scripts: the parse gained a
lines-seen/lines-parsed guard; the fix moved the ambiguity into the *timestamp* parse
below it; fixing that left it in *discovery* above it. Each fix was correct. Each left the
same silhouette next door.

**Rule: when you find one false clean, sweep the CLASS — discovery, filter, parse,
aggregate, print — not the instance.** At every layer ask: *if this silently did nothing,
would the output differ?* If the answer is no, that layer needs a denominator.

## Print the positive count beside the zero

A zero is not evidence on its own. It becomes evidence when it sits next to proof the
detector works:

```
✅ DO:
   lines seen / parsed : 130700 / 130700
   errors detected     : 1055
   errors of type X    : 0        <<< meaningful: the detector demonstrably fires

❌ DON'T:
   errors of type X    : 0        <<< indistinguishable from a broken detector
```

The detector found a thousand *other* errors, so "zero of type X" is a measurement. Without
that neighbouring count it is an assertion.

Practical form for a per-file scan — emit and check both numbers, and say so when they
disagree:

```bash
read -r lines parsed hits <<<"$(awk '
    { lines++ }
    /<the shape a valid record must have>/ { parsed++; if (/<the thing sought>/) hits++ }
    END { print lines+0, parsed+0, hits+0 }' "$f")"

note=""
[ "$lines" -gt 0 ] && [ "$parsed" -eq 0 ] && note="  <<< FORMAT NOT RECOGNISED — row MEANINGLESS"
printf '%-40s lines=%-8s parsed=%-8s hits=%-6s%s\n' "$(basename "$f")" "$lines" "$parsed" "$hits" "$note"
```

## Distinguish the reasons for an empty result

"Nothing found" collapses several very different states. Name them separately — the
wording is the deliverable:

```awk
END {
  if (seen == 0)        print "EMPTY: no input at all"
  else if (parsed == 0) print "FORMAT NOT RECOGNISED: N lines, NONE parsed — MEANINGLESS"
  else if (cand > 0)    print "N candidates matched but ALL failed the later parse — MEANINGLESS, not zero"
  else                  print "genuinely none: N lines, N parsed, 0 candidates"
}
```

The third branch is the one that gets forgotten: a counter incremented *before* a later
filter means the map can end up empty while candidates genuinely existed. Reporting that as
"none found" is the false clean wearing the exact words of a real finding.

## Announce partial coverage; a missing section reads as a complete report

When a script iterates targets, a target that drops out silently is invisible — **two
populated sections beside a missing third look like a finished report, not a truncated
one.** Guard the *whole loop*, not just the all-targets-failed case:

```bash
CONFIGURED=0; REPORTED=0; MISSING=""
for c in "$SITES"/<pattern>*; do
  [ -e "$c" ] || continue
  CONFIGURED=$((CONFIGURED + 1))
  if [ ! -r "$c" ]; then MISSING="$MISSING $(basename "$c"):unreadable"; continue; fi
  ...
  if [ "$found" -ne 1 ]; then MISSING="$MISSING $(basename "$c"):no-readable-target"; continue; fi
  REPORTED=$((REPORTED + 1))
  ...
done

if [ "$REPORTED" -lt "$CONFIGURED" ]; then
  echo "!! COVERAGE GAP: $CONFIGURED configured, only $REPORTED reported. Dropped:$MISSING"
else
  echo "coverage: all $CONFIGURED target(s) reported"
fi
```

Stating coverage **even when complete** is what makes its absence noticeable. The realistic
trigger is environment drift — a log-rotation naming change (`dateext` turning `.1`/`.1.gz`
into date suffixes) removes every rotated generation from a glob without touching anything
you would think to re-check.

## Derive the target from the CONFIG, never from a name or directory guess

The most expensive version of this failure is not a bad parse — it is **reading the wrong
files entirely and reporting a confident zero.**

A scan globbed the conventional log directory. The services in question each declared their
own log destination, and some wrote outside that directory altogether. The scan read files
containing none of the relevant traffic and reported a clean result — one step from a
production decision.

**The config is the contract; the directory is a hope.** Same family:

| Guessed from | Actually authoritative |
| --- | --- |
| conventional log directory | each service's own log directive in its config |
| the systemd **unit** name (`php8.3-fpm`) | the **binary** name (`php-fpm8.3`) — only the binary takes `-t` |
| "the installed runtime version" | the version the web server actually routes to (`fastcgi_pass` socket) |
| a package's default path | the path the running process was started with |

When parsing a config for paths, three edge cases repay the effort:

- **Commented-out directives** — anchor the match at line start (`^[[:space:]]*<directive>[[:space:]]`)
  so a `#`-prefixed line can never match.
- **Sentinel values** — a directive whose value is a keyword rather than a path (e.g. an
  `off` value) becomes a *relative* path in a later `[ -r "$p" ]` test and can match a
  same-named file in the CWD. Accept absolute paths only; skip the keywords.
- **Variables in the path** — a `$var`-bearing value cannot be resolved from the config
  text; skip it explicitly rather than letting it fail an existence test by accident.

## The data was right; the extraction was wrong

Three defects from one session, each invisible until one specific condition arrived. In
every case the bytes being checked were correct and the command reading them was not.

**A flag that made the comparison compare nothing.**

```sh
grep -H '^KEY=' ./*/config | sort -t= -k2 | uniq -c -f1
#   -> "170 <first line>"   read as "all 170 identical"
```

`uniq -f1` skips the first whitespace-delimited field. Those lines have exactly one field,
so `uniq` compared empty strings and collapsed every row whatever its value. The real
distribution was 161 / 6 / 3, and the 6 were malformed entries that the "all identical"
reading hid completely. A one-row summary of a many-row population is a claim; check it
against a count of distinct values computed another way (`cut -d= -f2- | sort | uniq -c`).

**A validator that threw away the diagnostic it exists to produce.**

```sh
# ❌ DON'T — the tool prints exactly why it rejects; this keeps one word
if validate_tool -d "$CONF" >/dev/null 2>&1; then say "OK"; else say "FAIL rejected"; fi
```

Debugging then started from zero, and the cause was eventually found by A/B-ing inputs
instead of reading the error that had been produced and discarded the whole time. The
replacement script, written specifically to stop swallowing diagnostics, then piped the
tool's output through `head -40`. On the real system those 40 lines filled with routine
per-item chatter and the error was below the cut. **Capping diagnostic output is only safe
if the diagnostic survives the cap**: collect the error lines first and print them
unconditionally, then cap only the routine trace (same instinct as filtering *named* benign
noise in [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) § Evidence logs).

```sh
# ✅ DO — on failure the operator gets ALL of it; only a success's routine trace is capped
rc=0; out=$(validate_tool -d "$CONF" 2>&1) || rc=$?   # errexit-safe capture
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" >&2                            # uncapped: the reason is in here somewhere
  say "FAIL rejected (rc=$rc)"
else
  printf '%s\n' "$out" | awk 'NR <= 40'; say "OK"   # awk reads it all: no SIGPIPE under pipefail
fi
```

Don't try to pick the error line out by keyword (`grep -i error`) as a substitute: a
diagnostic worded any other way is dropped, which is the same defect again.

**A filter matching more lines than its target — which only breaks on success.**

```sh
# ❌ DON'T — substring match
tool describe "$OBJ" | awk -F: '/Storage class/{gsub(/ /,"",$2); print $2}'
# ✅ DO — anchor on the field itself
tool describe "$OBJ" | awk -F: '/^[[:space:]]*Storage class:/{gsub(/ /,"",$2); print $2}'
```

The tool emits two lines containing that phrase: the field, and a `… update time:` field.
Split on `:`, the timestamp line contributed a fragment of the date, so the value became two
lines and every comparison against it failed. The second line **exists only after the
transition being waited for**, so the parser was correct for as long as the answer was "not
yet" and broke at the exact moment the awaited event happened. A check that can only fail on
success looks perfectly reliable for as long as it has nothing to report.

The general move: anchor on the field, never on a substring of it. When a check watches for
an event, capture the output as it looks **after** the event, not only before it, and test
the parser against both.

## Calibrate a threshold with the verdict's own expression

A threshold is only as good as the population it was measured over, and **the only expression
entitled to produce a baseline is the one the verdict is stated in** — same query, same regex,
same label set, over the real window, bucketed and de-duplicated the same way. A convenience
extraction (a quicker grep, a looser pattern, a hand-tallied sample) measures a *different*
population, and the number it returns is plausible in either direction with nothing to compare
it against.

The shape: a "no more than N distinct sources per interval" alert was sized with a quick
`grep -oE 'from [0-9.]+'`, which silently skipped the one line family where the address
precedes the username. Re-measured with the rule's own expression over a window twice as long,
in the rule's own buckets, de-duped per (bucket, source), the true maximum was roughly eight
times *smaller* than the hand-measured figure — so the shipped threshold could never fire.

**State the window, the bucket and the de-dup key beside the number, and record the calibration
in place, next to the rule.** A bare threshold in a rule file is an assertion; a threshold
carrying the expression that produced it is a measurement, and the next person can re-run it.

Companion trap, same root: **an aggregation introduced only to make a join legal silently
redefines what the series means.** A rule engine that errors on many-to-one matches invites a
collapse — freshest-per-key, `max()`-per-key — to force the join 1:1, and that collapse destroys
exactly the fact that two entities shared the key. Afterwards the alert names a cause that is an
artifact of the aggregation and prescribes a remedy that cannot possibly clear it; one such
false positive fired continuously for over a week telling operators to reload a component that
was already correct.

Neither substitution changes the metric's NAME or the alert's TEXT, so the label goes on
promising the old meaning — and the author can write down, in the same commit, a reassuring
argument for why the collapsed series will still surface the fact it just destroyed. When an
aggregation is forced on you: **emit the destroyed fact as its own metric under its own name**
(which leaves the join untouched), alert on that separately, and add an exclusion so the
original alert's text means what it says.

## An assertion that COULD NOT run scores as an assertion that passed

No aggregate verdict distinguishes **"asserted and true"** from **"never asserted"** — a
skipped check contributes a NON-FAILURE, and the summary prints PASS. Three shapes produce
the skip:

- **A capability guard whose false branch is a legitimate no-op** — `command -v X && …` with
  no `else`. The single probe proving a backup credential could push but not delete was gated
  this way; the else branch never set `fail=1`, so it SKIPped on every run underneath a
  printed `VERIFY PASS`. Fixed by removing the optional dependency so the probe always runs.
- **A tool present but unreachable** — a non-login remote shell without the `sbin` directories
  on PATH fails the probe on a host where the tool is active and the call itself runs
  privileged. Mechanics, and the "could not RESOLVE" wording: see the environment edges in the
  last section.
- **Non-final position in an `&&` list**, which POSIX exempts from errexit —
  [`STRICT_MODE_HAZARDS.md`](STRICT_MODE_HAZARDS.md) hazard 5.

The worst shape is the third one wearing the apply/verify contract:

```bash
# ❌ DON'T — verify is skipped EXACTLY when the apply failed; the same operator keeps the
#            failed apply from stopping the run, so execution continues through the
#            irreversible last step and the script exits 0
step.sh --apply && step.sh --verify

# ✅ DO — verify ALWAYS runs (including on the failure path, for diagnostics) and the run
#         aborts before anything irreversible
gated_step() {
  local apply="$1" verify="$2" rc=0     # separate variables, so no && can creep back in
  "$apply"  || rc=$?
  "$verify" || rc=$?
  [ "$rc" -eq 0 ] || { echo "ABORT: $apply / $verify did not both succeed" >&2; exit 1; }
}
```

Reproduce it in one line before arguing about it —
`bash -c 'set -e; echo A; false && echo verify; echo REACHED'` prints `REACHED` and exits 0.
Note the discrimination: `step.sh --apply --verify` as ONE invocation is safe under errexit.
**The hazard is the `&&` list position, not the pairing.**

It survives review because the skip message is entirely plausible ("tool not active — no rule
added", "linter not installed — skipped"), because the guard was written for portability,
which is a virtue, and because *the assertions most likely to be made optional are the ones
proving a security property*. It is also self-propagating: it reads as house style and gets
copied into new steps — one instance sat 57 days and was copied twice, its introducing commit
message claiming it "gated each step on its `--verify`".

**Where a skip is genuinely possible, three-state it — ASSERTED / COULD-NOT-RUN / FAILED —
and treat COULD-NOT-RUN as FAILED**: revert or abort, never pass. (A policy-flip script
lint-gated a config edit on an interpreter absent from the runner; the lint reported "skipped"
and the script read could-not-run as passed. Its own smoke test caught it before any live
run.) Better still, make the check *runnable* rather than optional: pin PATH or call by
absolute path, drop the optional dependency where you can, and where a precondition must be
asserted, die naming both the missing tool **and** the operation it would have performed.

Scope it, so the rule cannot flag correct code: errexit in non-top-level position is a defect
only where it was **load-bearing**. `set -e` inside a remote command string, `if ( cd X &&
checksum )` where the short-circuit *is* the control flow, and `if (` in awk are known-safe —
mute a finder that flags them. And do not fuse this with its opposite-polarity sibling,
errexit firing on a diagnostic whose non-zero exit is normal
([`STRICT_MODE_HAZARDS.md`](STRICT_MODE_HAZARDS.md) hazard 3): there too the check does not
run, but the run reports failure rather than success.

## A fail-open branch names an EXTERNAL cause for an internal defect

A fail-open (or fail-safe) branch returns a legal outcome whose message names something
outside the process — *unreachable*, *timeout*, *no data* — so a permanent internal defect on
that path reads as a transient network fault, and attention goes to the wrong layer.

**The sharpest tell is a success value the designed flow can never produce.** A catch-up
replication step refused to pull unless the source reported itself primary, while an earlier
gate only admitted the operation once every peer reported **non**-primary: the ok result was
unreachable *by construction*, so every run took the fail-open path and named the peer. What
settled it was reading the gate order, not the message.

The audit question is: **has this path's ok result ever been recorded, and COULD it be?**
Count outcomes by VALUE, not just failures, and treat a success value with zero occurrences as
a design defect to investigate. Honest provenance: that query is a derived prescription, not a
method with a track record — the cases behind this section came from reading the protocol
while planning, from external code review, and from cross-checking on the box.

Three further shapes of the theme, each seen once and each expensive:

- **Two independently fail-safe defaults composing into a fail-DANGEROUS one** — two
  timestamps each defaulting to `0`, compared with `-ge`, so "newer than the cutoff" held for
  everything. When you add a second fail-safe default, run the case where **both** fire.
- **A guard coded fail-open against its own documented fail-closed intent** — the docblock
  said fail-closed; the unresolvable-owner branch fell open.
- **One gap holding another shut** — closing a firewall gap turned a fail-closed 504 into a
  fail-open 200 that served blocked assets. When you close a gap, re-ask what else it was
  holding shut.

**The naive relaxation is worse than the bug.** Dropping the refusal and exiting 0 trades a
loud wrong signal for a silent false success that a downstream gate then accepts. A corrected
refusal must keep *skip*, *proceed* and *die* non-interchangeable, and be pinned by a
self-testing guard whose fixtures reject BOTH the pre-fix shape and the naive exit-0
softening. Where the true state is "degraded but still serving", expose it as an explicit
queryable health field rather than a gate — a gate fails closed exactly where it matters most.

## Where does the unknown land?

A guard written as a comparison quietly assigns unknown input to whichever side is benign:

| Shape | Where the unknown lands |
| --- | --- |
| an emptiness pre-test in front of the safety comparison — `[ -n "$x" ] && [ "$x" != "$expected" ]` | empty short-circuits to "nothing wrong" |
| a falsy failure value that something downstream turns into a plausible constant | `json_encode` returns `false` on non-UTF-8, `hash()` coerces it to `''`, and the empty-string digest passes an `[ -z ]` guard and gets recorded |
| a transport-failure sentinel meeting a negative assertion | a wrapper returning `000` on failure, tested as `[ "$c" != 404 ]` |
| an ambiguous external status | a 404 meaning "absent" **or** "your credential is not accepted" — never let it authorise SKIPPING a mutation |
| several fail-safe defaults firing together | the composed-defaults shape above |

**Unknown is a third state, and it needs somewhere to land before any comparison runs.** Four
remedies are valid — pick per site rather than reaching for the first: (a) give the unknown
its own branch, printing a distinct `CANNOT DETERMINE …` and refusing; (b) make the input
structurally incapable of being unknown at the point of comparison; (c) assert the POSITIVE
expected value rather than the absence of a bad one, so a failure sentinel cannot pass; (d)
replace a partial transform with a total one. Where a value is transformed before the check,
run the check against the **transformed** representation.

These read as defensive code — the author has visibly already thought about the empty case —
which is why the hole survives review. And **fixing the branch you were shown is not fixing
the class**: one ownership guard was repaired at its emptiness short-circuit, and the *same
function's* 404 branch went on assigning an ambiguous status to the benign state a week later.
Invented fixtures compound it: hand-written payloads encode the same guesses as the code, so a
green suite can only fail if the code disagrees with the author's belief, never if the belief
disagrees with the API. Map an external status enum exhaustively against ONE captured real
response, and read a `TODO: confirm the real values` beside a passing test as a declaration
that the suite is worthless for that contract. For a polling status a permissive
`default => still waiting` is *legitimate* for unknown intermediate states — the defect is an
unmapped SUCCESS value, which makes the happy path poll forever.

**Corollary: you cannot represent "unset" with a value.** Absence has to be judged where the
value is consumed, and every filler written at the layer that FILLS the slot converts a
detectable missing into a syntactically valid wrong one:

| Filler, added as a safety measure | What it actually does |
| --- | --- |
| a descriptive placeholder in an example env file — `HOST=<this instance's host>` | passes the consumer's emptiness guard, so an un-edited copy boots against the fallback — the exact failure the guard existed to prevent |
| a fail-loud sentinel default — `${HOST:-HOST_UNSET}` | is non-empty, so it never fails loud |
| a substitution default naming a real host — `${HOST:-default.internal}` | makes the variable always non-empty in-container, so a later mutual-exclusion check aborts every call |
| a required-marker — `${HOST:?}` — on a variable only one profile needs | whole-file interpolation runs before profile filtering, so the other profile dies |

A non-empty default also makes the consumer's unset branch **untestable by construction**: the
tests pass only because the test environment omits the variable, which is not how the deployed
shape runs. Listing the environment proves nothing either — the substitution layer declares
the name whether or not it has a value. Ship template slots **empty** (the value that trips
the guard) or with the command that computes the real one; give the consuming component sole
ownership of its default and let it refuse to start; and exercise it once in the deployed
shape with the variable genuinely unset.

Same family, one layer up: **before branching on an environment discriminator, check whether
the file it reads is tracked.** A tracked discriminator reads identically on every checkout,
so the fallback branch it selects is dead code and the protection it appears to give is
false — and left alone, a later document cites it as settled. Gate on state only the target
environment can produce.

## What caught these, every time: two checks that can disagree

None of the evidence-script false cleans above was found by inspection. Each was found because **two parts of the same
report contradicted each other** — one section proved a code path had executed while
another claimed the corresponding traffic did not exist. Both could not be true, and the
section resting on ground truth won.

**Build reports whose sections can contradict each other.** A single check has nothing to be
caught by; it can only be believed. Cross-check a derived claim against an independent
signal that would move for the same reason, and put both in the output.

Related: [`GREEN_RUN_UNIVERSE_TOO_SMALL.md`](GREEN_RUN_UNIVERSE_TOO_SMALL.md) for the
neighbour where the check ran honestly but could not have seen the defect ·
[`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) ·
[`SAFE_CONFIG_EDITS.md`](SAFE_CONFIG_EDITS.md).
