---
stage: plan
slug: scripts-tools-taxonomy
created: 2026-06-07
source: ./IDEA-016-reorganize-scripts-tools-by-concern.md
status: ready
project: mind-vault
architect_review: "🟡 REQUIRES ABSTRACTION → all 8 findings folded (2026-06-07): broadened R4 gate (F1/F7), expanded ref table + corrected statusline L47 (F2/F4), honest tools/ genre for cleanup-contamination (F3/Q5), refreshed IDEA frontmatter (F5), added Q4 scripts/-naming + Q5 (F6), post-merge cross-wire note (F8)."
---

# IDEA-016: Reorganize scripts/ and tools/ by concern (scoped re-partition)

## Context

`scripts/` and `tools/` have drifted into an incoherent split — both hold
`install`/`setup`-named routines, so it's no longer obvious where a script lives
or belongs. The IDEA identified three distinct concerns mixed across the two
dirs: (1) **runtime skill helpers** invoked by skills at runtime, (2) **machine
provisioning** (`install-*`), (3) **mind-vault → host config wiring**
(`setup-*-symlinks`). The sharp tell: Cursor appears in both dirs, and the
review-loop adapters (`find_*`, `*_retrigger`) — pure skill machinery — sit in a
toolbox-named dir.

Decision taken at plan time (user, 2026-06-07): **scoped re-partition.** Fix the
genuine miscategorization without churning the IDEA-017-doomed symlink scripts.
The outcome is a clean three-concern separation *by content* — the only thing
deferred is the cosmetic **rename** of the config-wiring dir (`scripts/` →
`link/`), which IDEA-017 may make moot for the Claude Code host.

## Problem Frame

- **Runtime helpers masquerade as tools.** `tools/find_*_comments.sh`,
  `tools/*_retrigger.sh`, `tools/sprint-auto-bootstrap.sh`,
  `tools/validate-skills.sh` are read *by skills at runtime*, not installation —
  yet they share `tools/` with one-shot machine provisioners.
- **`statusline-command.sh` is stranded.** It's a runtime helper sitting in
  `scripts/` (the config-wiring dir), the inverse of the above.
- **Provisioning is split across both dirs.** `install-*` live in `tools/`, but
  `install-wsl.ps1` lives in `scripts/`.
- **Real-world cost already paid:** a memory note claimed the symlink-all-skills
  installer needed building when `scripts/setup-claude-code-symlinks.sh` already
  existed — the muddy split hid it.

## Requirements Trace

- **R1.** `tools/` ends up containing skill machinery **and repo-maintenance
  utilities** — review-loop adapters (`find_*`, `*_retrigger`), sprint-auto
  bootstrap, validate-skills, statusline, and `cleanup-contamination.sh`. Note
  honestly: `cleanup-contamination.sh` is a one-shot repo-repair utility, **not** a
  runtime skill-helper (zero skills invoke it). `tools/` is therefore "skill
  machinery + dev/maintenance utilities," and `tools/README.md` must say so —
  rather than mislabel it a runtime helper. (See Q5.)
- **R2.** A new `install/` dir contains **only** machine provisioning (`install-*`
  from `tools/` + `install-wsl.ps1` from `scripts/`).
- **R3.** `scripts/` ends up containing **only** host config-wiring
  (`setup-*-symlinks.sh` + `_symlink-lib.sh`) — files unmoved, dir un-renamed
  (rename deferred to IDEA-017).
- **R4.** Every **live** reference to a moved file is repointed; no skill,
  command, README, ONBOARDING doc, or the symlink installer points at a dead path.
- **R5.** The statusline cross-wire in `scripts/setup-claude-code-symlinks.sh`
  resolves to the new `tools/statusline-command.sh` path so the status line keeps
  linking on a fresh `setup-claude-code-symlinks.sh` run.
- **R6.** No script's *behaviour* changes — only location, the `# Usage:` header
  path, and references. Idempotency markers stay byte-identical.
- **R7.** Each of `tools/`, `install/`, `scripts/` carries a README stating its
  single concern and the boundary.
- **R8.** Migration follows `RULE_rename-before-drop`: move+shim, repoint, green
  gate, then drop shims in a separate commit, then re-verify.

## Scope Boundaries

**In scope:**

- `git mv` of 8 provisioners → `install/`; `statusline-command.sh` `scripts/` → `tools/`.
- Repointing **live** references (skill refs, READMEs, ONBOARDING, the symlink installer).
- Per-dir READMEs (`tools/README.md` reshaped, new `install/README.md`, new `scripts/README.md`).
- Transitional symlink shims at old paths, dropped in a separate commit.

**Out of scope (deferred to IDEA-017):**

- Renaming `scripts/` → `link/` and `setup-*-symlinks.sh` → `link-*.sh`. The
  config-wiring scripts stay put, named as-is, pending the plugin decision.
- Any change to the per-skill-symlink mechanism in `_symlink-lib.sh`.

**Explicit non-goals:**

- **Do NOT touch consuming-project convention paths.** `tools/deploy.sh`,
  `tools/backup_db.sh`, `tools/sprint-auto-hooks.sh`, `scripts/harden_server.sh`,
  etc. are paths skills describe for *adopter projects* — they don't exist in
  mind-vault and must stay exactly as written.
- **Do NOT rewrite historical CHANGELOG entries.** A dated entry "Added
  `tools/install-cursor.sh` (#80)" records the path at that PR's date and stays
  factually correct; the new v-section entry documents the move. (This is why the
  R4 verification gate excludes `CHANGELOG.md` + `docs/archive/`.)
- Do NOT change what any script does.

## Context & Research

### Actual migration surface (measured 2026-06-07)

The IDEA's "~190 refs" conflated mind-vault's own files with consuming-project
convention paths. The real surface is far smaller:

| File(s) | Move | Live refs to repoint |
| --- | --- | --- |
| `find_*`, `*_retrigger`, `sprint-auto-bootstrap`, `validate-skills`, `cleanup-contamination` | **stay in `tools/`** | **0** — no path change |
| `statusline-command.sh` | `scripts/` → `tools/` | `README.md:169`; `scripts/setup-claude-code-symlinks.sh` **L47** (the load-bearing `ln` source), **L40** (comment), **L52/L57** (echo strings); README tree-diagram `tools/` line |
| `install-{docker,gcloud-cli,mosh-tmux,aliases,oh-my-posh,emoji-support,cursor}.sh` | `tools/` → `install/` | `skills/deployment/references/SHELL_INSTALLERS.md:394–397` (canonical-example list, `tools/`-prefixed); `skills/deployment/SKILL.md:460` (`tools/install-*.sh` glob); `tools/README.md` body → `install/README.md` |
| `install-wsl.ps1` | `scripts/` → `install/` | `README.md` tree-diagram `scripts/` line; `docs/guides/ONBOARDING.md:61` (`.\scripts\install-wsl.ps1` — Windows backslash form) |

**Consciously left (illustrative, not path refs):** `SHELL_INSTALLERS.md:156,173`
use the **bare** name `install-gcloud-cli.sh --with-components …` as inline
*command examples*, not file paths — per "don't over-harden illustrative
examples," these stay. The broadened R4 gate surfaces them; eyeball-and-skip is
the deliberate call, not an oversight.

The find_*/retrigger group echoes its sibling `*_retrigger.sh` by relative path
(`find_bugbot_comments.sh:542`, etc.) — both halves stay in `tools/`, so those
intra-`tools/` relative refs survive untouched. **No `.github/` workflow
references either** — the IDEA's CI-break worry is void.

### Idempotency-marker trap (R6)

`tools/install-aliases.sh` writes managed-block markers
`# BEGIN mind-vault-aliases (managed by install-aliases.sh)`. These are **content
identifiers users already have in their `~/.bash_aliases`** — rewriting the marker
string would orphan previously-installed blocks. On move, update only the
`# Usage:` header path; leave every BEGIN/END / `(managed by …)` marker byte-identical.
Same caution for any `# disabled by install-cursor.sh`-style generated markers.

### Institutional learnings

- [`RULE_rename-before-drop`](../../../rules/RULE_rename-before-drop.md) — drives R8's
  move→shim→repoint→green→drop→re-verify sequence; the surface-coverage grep
  (`*_FIELDS`-style) maps here to grepping every old path before the shim drop.
- [`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) #1.4 —
  the `# Usage:` header in each moved script is a stale-comment-vs-code site;
  sweep them in the same commit as the move.
- [`IDEA-018` provenance scrub](../2026-06-idea-018-provenance-scrub/) — precedent for a
  positive count-assertion verification gate scoped with `:!` path excludes
  (here: `:!CHANGELOG.md :!docs/archive/`) rather than brittle `grep -v`.
- [`docs/guides/SKILL_AUTHORING_WALKTHROUGH.md`](../../guides/SKILL_AUTHORING_WALKTHROUGH.md)
  — skills must not hardcode project paths; the runtime-helper refs we keep are
  mind-vault-internal, which is correct.

### IDEA-017 interaction (bidirectional)

IDEA-017 (mind-vault as a CC plugin) is the long-term supersede for concern #3.
This plan **deliberately leaves `scripts/` config-wiring untouched** so 017 can
own that dir's fate. On `/wrap`, append a backref to IDEA-017's file noting that
016 deferred the `scripts/` → `link/` rename to it.

## Key Technical Decisions

- **Provisioning dir named `install/`, not `setup/`.** The config-wiring scripts
  staying in `scripts/` are named `setup-*-symlinks.sh`; a `setup/` dir would
  collide semantically with that `setup-` prefix. `install/` mirrors the
  `install-*` filenames — "install = provisioning" vs "setup = wiring" stays
  unambiguous. *(Confirm at review — this is the one naming call.)*
- **Runtime helpers do not move.** Highest-ref-count, machine-invoked, already in
  the conceptually-correct dir (`tools/` = skill machinery). Moving them would be
  pure churn + max blast radius for zero coherence gain.
- **Config-wiring dir keeps its name `scripts/` for now.** Separation is complete
  by content; only the cosmetic rename is deferred to IDEA-017. Document the
  deferral in `scripts/README.md`.
- **Historical CHANGELOG entries are not repointed.** They record path-at-date;
  the move is documented in the new v-section entry at `/wrap`. Verification gate
  excludes `CHANGELOG.md`.
- **Symlink shims during transition, dropped separately (R8).** Each moved file
  gets a relative-symlink shim at its old path; references repoint; the grep gate
  goes green; then a separate commit deletes the shims and re-verifies. Protects
  the statusline cross-wire window in particular.

## Open Questions

- **Q1. `install/` vs `setup/` for the provisioning dir?**
  - **Default:** `install/` (collision-free with `setup-*-symlinks.sh`; mirrors filenames).
  - **Trade-off:** `setup/` reads slightly more "fresh-box bootstrap," but reintroduces the setup/setup naming muddle this IDEA exists to remove.
- **Q2. Keep transitional shims, or atomic move+repoint in one commit?**
  - **Default:** keep shims (RULE_rename-before-drop compliant; green gate before the destructive drop). Shim window is intra-PR only — gone by merge.
  - **Trade-off:** atomic is fewer commits, but violates the rule's >2-file anti-pattern and loses the bisectable green gate.
- **Q3. Split `tools/README.md` into `tools/` + `install/` READMEs, or one combined?**
  - **Default:** split — each dir documents its single concern (R7). The install-* sections move verbatim to `install/README.md`.
  - **Trade-off:** split is more files but matches the whole point (one concern per dir); combined would re-pool the ambiguity in docs.
- **Q4. Is leaving config-wiring in a generically-named `scripts/` acceptable for the IDEA-017 window?** Post-refactor, the genuinely "script-like" provisioners move out to `install/` while `scripts/` holds *only* `setup-*-symlinks.sh` — a reader landing in `scripts/` finds the opposite of what the name implies.
  - **Default:** defer the `scripts/` → `link/` rename to IDEA-017 (it may dissolve the dir for the CC host); mitigate now with an explicit `scripts/README.md` stating the deferral.
  - **Trade-off:** deferring keeps blast radius minimal and avoids redoing the dir if 017 lands, but ships a transient name/content mismatch. Renaming now is cleaner immediately but risks churn 017 would undo.
- **Q5. Where does `cleanup-contamination.sh` belong?** It's a one-shot repo-repair utility, not a runtime skill-helper (zero skill refs) — neither provisioning nor config-wiring.
  - **Default:** keep in `tools/`, and have `tools/README.md` honestly frame the dir as "skill machinery + dev/maintenance utilities" (R1) rather than mislabel it a runtime helper.
  - **Trade-off:** a fourth `maintenance/` dir would be purer but over-partitions for a single file; the honest-label approach keeps it discoverable beside the other dev tooling.

## Execution Sequence

Commits ordered for `RULE_rename-before-drop` (move+shim → repoint → green → drop → re-verify).

1. **Create `install/` + move provisioners (with shims).**
   `mkdir install/`; `git mv tools/install-*.sh install/`;
   `git mv scripts/install-wsl.ps1 install/`;
   `git mv scripts/statusline-command.sh tools/`.
   For each old path, add a relative symlink shim
   (`ln -s ../install/install-docker.sh tools/install-docker.sh`, etc.;
   `ln -s ../tools/statusline-command.sh scripts/statusline-command.sh`) and
   `git add` it. Update each moved script's `# Usage:` header path; **leave all
   idempotency markers byte-identical** (R6). Commit:
   `refactor(tools): IDEA-016 — move provisioners to install/, statusline to tools/ (shimmed)`.

2. **Repoint live references (R4, R5).**
   - `scripts/setup-claude-code-symlinks.sh` — **L47 is the load-bearing one**
     (`statusline_src="$(cd "$MV/scripts" && pwd)/statusline-command.sh"` →
     `$MV/tools`); also the comment L40 and echo strings L52/L57. **This is R5 —
     the one cross-wire the whole shim strategy exists to protect. Edit by content,
     not by line number** (lines drift).
   - `README.md:169` statusline prose path `scripts/` → `tools/`.
   - `README.md` tree diagram: change `scripts/` line to config-wiring only (drop
     the `install-wsl.ps1` example), change `tools/` line to mention statusline,
     and **add a new `install/` line** (provisioning — `install-*`, `install-wsl.ps1`).
   - `skills/deployment/references/SHELL_INSTALLERS.md:394–397` `tools/install-*`
     → `install/install-*`. (Leave bare-name examples L156/L173.)
   - `skills/deployment/SKILL.md:460` `tools/install-*.sh` → `install/install-*.sh`.
   - `docs/guides/ONBOARDING.md:61` `.\scripts\install-wsl.ps1` → `.\install\install-wsl.ps1`.
   - Commit: `refactor(docs): IDEA-016 — repoint live refs to install/ + tools/ statusline`.

3. **Per-dir READMEs (R7).**
   - Reshape `tools/README.md` to document only runtime helpers (move the
     install-* sections out).
   - New `install/README.md` — provisioning (the moved install-* sections + the
     `sudo ./install/install-X.sh [--check]` convention).
   - New `scripts/README.md` — host config-wiring; **state the IDEA-017 deferral**
     ("dir name + `setup-*-symlinks.sh` naming pending plugin decision").
   - Commit: `docs(tools): IDEA-016 — per-dir READMEs stating single-concern boundaries`.

4. **Green gate (R8 — the merge-blocking verification).** Run the Verification
   block below. All checks must pass with shims still present.

5. **Drop the shims (destructive, isolated commit).**
   `git rm` every shim symlink created in step 1. Commit:
   `refactor(tools): IDEA-016 — drop transitional path shims`.

6. **Re-verify.** Re-run the full Verification block (now shim-free). `bash -n`
   every moved `.sh`; confirm `tools/validate-skills.sh --all` green; confirm the
   R4 grep gate still reads 0.

## Verification

- **R4 dead-path gate (live refs only) — broadened to catch bare-name + glob + `.ps1`:**
  ```
  git grep -nE '(tools/)?install-[a-z*-]+\.(sh|ps1)|scripts/(statusline-command|install-wsl)\.(sh|ps1)' \
    -- ':!CHANGELOG.md' ':!docs/archive/' ':!tools/install-*' ':!install/'
  ```
  The original `tools/install-[a-z-]+\.sh` regex was path-prefix-anchored and
  **missed** bare names (`SHELL_INSTALLERS.md:156,173`) and the glob
  (`SKILL.md:460`) — false-confidence hole. The broadened form catches them.
  Expected residual after step 2: **only the two consciously-left illustrative
  bare-name examples (`SHELL_INSTALLERS.md:156,173`)** — eyeball each remaining hit
  and confirm it is one of those, not a real dead path. `git grep` matches file
  *contents*, so shim symlinks never appear here.
- **R5 statusline cross-wire:** `grep -n statusline-command scripts/setup-claude-code-symlinks.sh`
  → all three references read `tools/statusline-command.sh`.
- **R1/R2/R3 dir contents:** `ls tools/ install/ scripts/` matches the chosen tree
  (runtime helpers / provisioners / config-wiring). **Expected to show shim entries
  until step 5** (a `tools/install-docker.sh` symlink lingers pre-drop) — only the
  post-step-6 re-verify asserts a fully clean, overlap-free tree.
- **R6 markers intact:** `git show HEAD~N:tools/install-aliases.sh | grep 'managed by'`
  vs the moved file — the `(managed by install-aliases.sh)` strings are byte-identical.
- **R6 behaviour smoke:** `bash -n install/*.sh tools/*.sh scripts/*.sh` clean;
  `./tools/install-*`-style `--check` not required (no behaviour change), but
  `tools/validate-skills.sh --all` must stay green.
- **Self-sweep:** `# Usage:` header in each moved script names its new path.
- **No consuming-project paths touched:** `git diff --stat` shows no edits to
  lines mentioning `deploy.sh`, `backup_db.sh`, `sprint-auto-hooks.sh`, `harden_server.sh`.
- **R5 end-to-end (post-merge, executor action):** this machine's
  `~/.claude/statusline-command.sh` is currently a **regular file**, not a symlink
  into the repo — so nothing on disk points at the old path and the move is safe
  here. After merge, run `scripts/setup-claude-code-symlinks.sh` once and confirm
  it prints `… -> mind-vault/tools/statusline-command.sh` — that is the only true
  end-to-end validation of the R5 cross-wire.

---

**Status:** ready — architect-reviewed (🟡 → all findings folded). Open Questions
Q1 (install/ vs setup/), Q4 (defer scripts/ rename), Q5 (cleanup-contamination
genre) carry sensible defaults; surface them at `/work` start for a yes/no rather
than blocking. Next: `/work docs/archive/2026-06-idea-016-scripts-tools-by-concern/2026-06-07-scripts-tools-taxonomy-plan.md`.
