# Provenance-Scrub Runbook

**Canonical home for mind-vault's repeatable prior-project-identifier cleanup.**
This is not a one-off. Provenance identifiers (prior-project / client / repo
names) accumulate back into tracked files over time via `/compound` bullets,
even with the scrub gate in place. When drift accumulates, run this procedure
and append a **Run log** entry below — periodic maintenance, *not* a fresh IDEA
each time.

Origin: IDEA-018 (2026-06). Prevention counterpart: the `/compound` scrub-gate
forcing function in `skills/compound/SKILL.md` step 5 (instruction-only, no
denylist — points back here for the recurring-drift case).

---

## Procedure

### 1. Inventory

```bash
# Pick the token(s) that have drifted back in. Start from known prior-project
# names (these live in local memory ~/.claude, never tracked here).
TOKEN=<prior-project-name>

git grep -ic "$TOKEN" | sort -t: -k2 -rn      # per-file counts, tracked only
git grep -i "$TOKEN" | wc -l                   # total hits
```

`git grep` is the right tool: tracked-files-only, ignores `.git/`, honours
pathspec exclusions for whitelisting.

### 2. Categorise by risk (low-blast-radius first is fine — no symbol coupling)

| Category | Files (example) | Nature | Risk |
| --- | --- | --- | --- |
| Tool scripts | `tools/find_*_comments.sh` | check: comment vs functional default | verify `bash -n` after |
| SKILL bodies | `skills/*/SKILL.md` | illustrative examples (load on invocation) | zero behavioural |
| Guides + READMEs | `docs/guides/`, `README.md` | example names / provenance tags | narrative |
| CHANGELOG + archive | `CHANGELOG.md`, `docs/archive/**` | bulk provenance tags | narrative, highest count |

**Tool-script caveat:** confirm each hit is a *comment*, not an executable
default, before editing — `grep -nE "(REPO|OWNER|DEFAULT|repo|owner)=.*$TOKEN|$TOKEN/"`.
If a functional default exists, parameterise it (don't just delete). Re-run
`bash -n` on every edited script.

### 3. Generalise — decide once per category, apply uniformly

- *Prose example name* → "a consuming project" / "an external project".
- *Name-shaped token genuinely needed* → obvious placeholder `project-x` (lowercase, unmistakable — never a real name).
- *Path / command* → `~/projects/<project>`.
- *Provenance tag* (`(tok)`, `tok IDEA-N`, `tok PR #N`) → **drop the tag, keep the lesson**; bare unresolvable `IDEA-N` → drop or qualify `(external)`.

Drop the tag, keep the lesson — never rewrite the compounded knowledge itself.

### 4. Verify (positive count-assertion — merge-blocking)

Whitelist only what legitimately must name the token (e.g. the IDEA archive dir
that documents the scrub itself). Assert the *exact* expected remaining count,
don't trust a content-exclusion `grep -v` (it can silently swallow new leaks).

```bash
WHITELIST_DIR=docs/archive/<this-scrub-idea-dir>
n=$(git grep -i "$TOKEN" -- ":!$WHITELIST_DIR" | wc -l)
echo "outside-whitelist hits: $n (expect the known kept count)"
git grep -i "$TOKEN" -- ":!$WHITELIST_DIR"   # eyeball every remaining line
```

Also: `bash -n` on edited scripts; opportunistic grep for *other* stray names
while you're in here.

---

## Run log

Newest first. One line/entry per scrub run: date, token(s), baseline → end
state, PR.

### Run 1 — 2026-06-07 · token `teisutis` · IDEA-018 · PR (pending)

- **Baseline:** 116 total hits / 22 files. Whitelisted (IDEA-018 archive dir):
  22 hits. **Outside whitelist: 94 hits across 20 files** (incl. `CHANGELOG.md`
  ×47, `IDEA-012` doc ×8, 2 session-notes ×7 each, 3 tool-script *comments*,
  2 SKILL bodies, 2 guides, 2 READMEs, + 8 archive IDEA/plan docs).
- **Key finding:** all 3 tool-script hits were pure comments — the IDEA's
  "functional default" worry was void (`bash -n` clean, no `REPO=`/`owner=`).
- **Prevention shipped same PR:** rewrote the `/compound` scrub gate into an
  instruction-only forcing function (emit a proper-noun classification before
  commit) — no denylist (false-positive cost > value; instruction wins
  long-term). Replaced the gate's own `teisutis` example with `project-x`.
- **End state ACHIEVED:** outside-whitelist count == 0 — gate pass (the
  ideas-index In-Progress line was also scrubbed in this PR, during `/wrap`,
  when the entry moved to References-Implemented in clean framing). 83 narrative
  hits + 11 in SKILL/guide/README/tool-comment surfaces scrubbed; `bash -n`
  clean; no stray client names.
- **Commits:** `6c1cce9` (guard+runbook) · `829d5fa` (tool scripts) ·
  `7f5f187` (SKILL/guides/READMEs) · `0abca11` (CHANGELOG+archive bulk).
