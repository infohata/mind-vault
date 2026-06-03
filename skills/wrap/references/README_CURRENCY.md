# README currency audit — keep the whole README honest, not just the IDEA's identifiers

Step 6's per-identifier scan patches what *this* IDEA touched. Nothing makes any
single wrap responsible for the **whole** README, so it drifts across many IDEAs:
version framing, counts, feature tables, stale ⚠️ flags. This is the devlog
backfill-gap rule (Step 4 §2) applied to the README. Step 6b fires it on a
staleness threshold and patches mechanical drift in-wrap.

## When this fires

Step 6b runs **after** Step 6's per-identifier loop, gated three ways:

1. **Scope** — eligible under `--scope=docs` / `full`; **skipped under
   `--scope=idea-only`** (per-IDEA sprint-auto wraps; the batch wrap is the audit
   point — see *Sprint-auto asymmetry*).
2. **Staleness** — count merged PRs on the base branch since the last
   *whole-README audit* (the marker date, not the file mtime). Fire iff
   `count >= N` (default **N = 5**, overridable via the hint block).
3. **Degraded environments** — if `gh` is unavailable (no auth / non-GitHub
   remote), fall back to **calendar staleness**: fire if the marker is absent or
   its date is older than 30 days. Never crash the wrap on a missing `gh` token.

Staleness count (server-side date filter — no `--limit` cap to reason about):

```bash
MARKER_DATE=$(grep -oE 'wrap:readme-currency-audited [0-9]{4}-[0-9]{2}-[0-9]{2}' README.md | awk '{print $2}')
BASE=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || echo main)
if [ -z "$MARKER_DATE" ]; then
    FIRE=1                                   # no marker → stale
elif [ "$MARKER_DATE" \> "$(date +%F)" ]; then
    FIRE=1                                   # future-dated / clock-skewed → stale
elif COUNT=$(gh pr list --state merged --base "$BASE" \
        --search "merged:>$MARKER_DATE" --json number --jq 'length' 2>/dev/null); then
    [ "$COUNT" -ge "${N:-5}" ] && FIRE=1     # PR-count signal
else
    # gh unavailable → calendar fallback (zero network)
    [ "$(( ($(date +%s) - $(date -d "$MARKER_DATE" +%s)) / 86400 ))" -ge 30 ] && FIRE=1
fi
```

**Same-day idempotency guard:** a marker dated today ⇒ `merged:>today` matches 0
PRs ⇒ no fire. So the `docs`→`full` two-pass re-run never double-audits — the
`docs` pass writes today's marker, the `full` re-run sees count 0 and skips. No
per-pass special-casing.

## The marker

A single HTML comment (invisible in rendered markdown), conventionally at the
**foot** of the README:

```html
<!-- wrap:readme-currency-audited 2026-06-03 -->
```

- **Read** at Step 6b entry (recipe above).
- **Write/refresh** to today's date whenever the audit *runs* — even a clean
  audit that patched nothing still resets it (the README *was* reviewed whole).
  This makes the cadence self-regulating.
- **Atomic with its patches.** Write the marker in the **same commit/branch as
  the README edits the audit produced** — pre-merge: the feature branch;
  post-merge fallback: the `docs/idea-NNN-wrap` cleanup branch. Never write the
  marker on a different ref than the audit. Guarantees *marker present ⟺ audit ran
  on this ref*; an abandoned cleanup PR simply never lands the marker → the next
  wrap re-fires (safe).

## Audit probes

Each probe is **no-op-when-absent** (a project without that surface skips the
probe cleanly) and maps its findings onto Step 6's existing dispositions —
**patch-now-mechanical** vs **flag-as-follow-up**. No new disposition vocabulary.

| # | Probe | How | Disposition |
| --- | --- | --- | --- |
| 1 | **Version framing** | README version banner / "vN highlights" vs Step 4b's detected `VER_SOURCE` (top `## vMAJOR.MINOR` of CHANGELOG). | Stale string → **patch now**. No version framing in README → skip. |
| 2 | **Counts** | Each "Skills (NN)" / "Agents (NN)" / table-row count vs its filesystem source (`ls skills/*/SKILL.md \| wc -l`, etc.). | Off-by-any → **patch now**. Source not auto-detectable → see fail-loud rule below. |
| 3 | **Feature/capability tables** | Each shipped unit (skill, command, engine) has a table row; grep the table for every `ls`-discovered name. | Missing row for a shipped unit → **patch now** (one row). Whole new table needed → **follow-up**. |
| 4 | **Stale ⚠️ / status flags** | For each ⚠️ / "UNSTABLE" / "experimental" flag, verify its cause still holds (grep CHANGELOG / devlog for a resolving entry). | Cause demonstrably resolved → **patch now** (remove). Cause unverifiable → **leave it** (a flag is a claim; don't drop it without evidence — RULE_self-sweep #3). |
| 5 | **Quick-start / command surface** | Commands + slash-invocable skills in the quick-start vs the actual `commands/` + skill set. | Renamed/removed entry → **patch now**. New concept needing a tutorial → **follow-up**. |

**Probe 2 fails LOUD, never silent.** The `"Skills (NN)"`-style heading is a
mind-vault artifact; a downstream project counts apps / endpoints / models in
shapes that regex won't match. When **no hint block AND no count-shaped heading
matches**, do **not** report "counts OK" — emit, in the wrap hand-back:
*"README count sources not auto-detectable — declare them in the optional
`wrap:readme-currency` hint block to enable count-drift detection."* Genericity
here means failing loud on the unknown shape, not pattern-matching mind-vault's
shape and calling a non-match clean.

**Large prose / architectural-narrative rewrites are always follow-up**, never
auto-rewritten (IDEA-013 non-goal). The test is Step 6's: if one to three
mechanical edits close the gap, patch now; if a section needs rewriting for a new
architecture, flag it in the PR body.

## Optional per-project hint

Zero-config by default. A project may declare an override block anywhere in the
README (read if present):

```html
<!-- wrap:readme-currency
N: 5
counts:
  skills: ls skills/*/SKILL.md | wc -l
  agents: ls agents/AGENT_*.md | wc -l
  commands: ls commands/*.md | wc -l
-->
```

`N` overrides the staleness threshold; `counts` declares the authoritative source
command per count claim (resolves probe 2's fail-loud case for non-mind-vault
README shapes).

## Sprint-auto asymmetry (intentional)

In sprint-auto, per-IDEA S5 wraps run `--scope=idea-only` → Step 6b is **skipped**
and the marker is **never touched** — even though those wraps may still patch the
README via Step 6's per-identifier scan. The single whole-README audit point for
the cohort is the **S11.7 batch wrap** on the integration branch (a regular,
non-`idea-only` wrap): it fires 6b once and resets the marker. Per-IDEA partial
touches not resetting the marker is the **same insight as the marker design** (a
partial touch is not a whole-README refresh), at batch scale — one audit per
sprint, not N.

## Dogfood note

The first run of this audit was mind-vault's own README during IDEA-013's `/work`
(2026-06-03): it caught the `v4.0.4` headline banner stale against CHANGELOG
`v4.6` (probe 1), verified the `Skills (17)` count (probe 2), and seeded the
marker. See the IDEA-013 archive for the worked diff.
