# Evidence scripts and false cleans

An **evidence script** is read-only and its entire product is a claim about the world:
"nobody hit the fault", "no tenant is affected", "the rate is unchanged". It changes
nothing, so it feels low-risk. It is not. A maintenance script that fails loudly wastes
an afternoon; an evidence script that fails *quietly* produces a green light, and someone
acts on it.

The contract in [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) covers
`--verify` proving an **effect** rather than "it ran". This reference covers the sibling
failure: a check that produced a number without ever having looked at anything.

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

## What caught these, every time: two checks that can disagree

None of the above was found by inspection. Each was found because **two parts of the same
report contradicted each other** — one section proved a code path had executed while
another claimed the corresponding traffic did not exist. Both could not be true, and the
section resting on ground truth won.

**Build reports whose sections can contradict each other.** A single check has nothing to be
caught by; it can only be believed. Cross-check a derived claim against an independent
signal that would move for the same reason, and put both in the output.

Related: [`MAINTENANCE_SCRIPT_CONTRACT.md`](MAINTENANCE_SCRIPT_CONTRACT.md) ·
[`SAFE_CONFIG_EDITS.md`](SAFE_CONFIG_EDITS.md) ·
[`../../deployment/references/DARK_DEPLOY_KILL_SWITCH.md`](../../deployment/references/DARK_DEPLOY_KILL_SWITCH.md)
for the rollout-side twin (shadow silence is ambiguous for the same reason).
