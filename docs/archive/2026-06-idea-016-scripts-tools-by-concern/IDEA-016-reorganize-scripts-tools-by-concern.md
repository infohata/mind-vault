---
id: 016
title: Reorganize scripts/ and tools/ by concern
status: complete      # idea | in-progress | complete | superseded
priority: medium   # high | medium | low
supersedes: []       # list of IDEA ids this replaces, or []
superseded_by:
depends_on: []       # list of IDEA ids required before starting, or []
related: [017]             # list of IDEA ids that share context, or []
created: 2026-06-06
completed: 2026-06-07
# Sprint-auto eligibility gates — both must be `true` with explicit reasoning
# before sprint-auto can run this idea unattended overnight.
# Default to `false` at capture; upgrade in `/plan` once the unknowns are nailed down.
auto_safe: false                                     # true | false
auto_safe_reason: "Scheme resolved at /plan (scoped re-partition); still needs the human Q1/Q4/Q5 confirmations (install/ vs setup/, defer the scripts/ rename, cleanup-contamination genre). Measured surface is small (~10 files moved, ~6 live-ref files, NOT the ~190 first estimated — most were consuming-project convention paths) but the statusline cross-wire in setup-claude-code-symlinks.sh is load-bearing, so not unattended-overnight safe."                     # why safe, or what blocks — 1-2 sentences
sensitive_paths_cleared: false         # true | false
sensitive_paths_cleared_reason: "/plan confirmed ZERO .github/ workflow refs (the CI-break worry was void). The one genuinely load-bearing path is the statusline link source in scripts/setup-claude-code-symlinks.sh:47 — repointed under a shim + green gate. Human should eyeball the broadened reference sweep before the shim drop."       # any auth/permission/schema/infra touch? — 1-2 sentences
---

# IDEA-016: Reorganize scripts/ and tools/ by concern

**Status**: ✅ Complete (2026-06-07) · PR #187
**Priority**: Medium

**Problem** (or opportunity): `scripts/` and `tools/` have drifted into an ambiguous split — both hold `install`/`setup`-named routines, so it's no longer obvious where a given script belongs or lives. The real boundary isn't two dirs; it's **three distinct concerns mixed across them**:

1. **Runtime skill helpers** — invoked *by skills at runtime*, not installation at all: `tools/find_*_comments.sh`, `tools/*_retrigger.sh`, `tools/sprint-auto-bootstrap.sh`, `tools/validate-skills.sh`, and `scripts/statusline-command.sh`.
2. **Machine provisioning** — bootstrap a fresh dev box: `tools/install-{docker,gcloud-cli,mosh-tmux,aliases,emoji-support,oh-my-posh}.sh`, `scripts/install-wsl.ps1`.
3. **mind-vault → host config wiring** — symlink mind-vault content into agent hosts: `scripts/setup-*-symlinks.sh`, `scripts/_symlink-lib.sh`.

The sharp tell that the current split is incoherent: **Cursor appears in both dirs** — `tools/install-cursor.sh` installs the *app*, while `scripts/setup-cursor-symlinks.sh` wires mind-vault *config* into it. And the review-loop adapters (`find_*`, `*_retrigger`) are skill machinery that merely happens to sit in a dir named like a toolbox.

**Proposal** (or idea): Decide a partition scheme in `/plan`, then migrate references under [`RULE_rename-before-drop`](../../rules/RULE_rename-before-drop.md) with symlink shims during the transition. Candidate schemes (do NOT pre-decide — `/plan`'s job):

- **(A) Merge into one dir.** Simplest; but pools the ambiguity rather than resolving it — rejected-leaning.
- **(B) Re-partition by concern.** e.g. `tools/` = runtime helpers (skill machinery), a `setup/` (or `install/`) dir = provisioning + config-wiring with a naming convention (`install-<software>` vs `link-<host>`). Resolves the conceptual mixing; highest blast radius.
- **(C) Keep two dirs, sharpen naming + add per-dir READMEs** stating the boundary. Lowest risk; documents intent without moving runtime-critical paths.

Blast radius (measured 2026-06-06): **~97 refs to `tools/*.sh`, ~95 to `scripts/*`** across skills, `commands/review-loop.md`, CI workflows, and docs. Runtime-critical: review-loop reads `tools/find_*.sh` + `tools/*_retrigger.sh` by path; sprint-auto reads `tools/sprint-auto-bootstrap.sh`. Migration must keep a symlink shim at the old path until every reference is repointed and a full green pass confirms it, *then* drop the shims in a separate commit.

**Why now**:

- The 5.x stack-decoupling effort (IDEA-009, IDEA-014) will add new skills and possibly new install routines — settle the taxonomy *before* it grows, not after.
- The ambiguity already caused a real miss: a memory item claimed the idempotent symlink-all-skills installer needed building, when it already existed at `scripts/setup-claude-code-symlinks.sh` — a clearer dir split would have made the existing script discoverable.

**Non-goals**:

- Not changing what any script *does* — purely where it lives and what it's named.
- Not touching the per-skill-symlink mechanism itself (deliberate design per `_symlink-lib.sh` header — a parent-dir symlink broke host discovery).
- Not a `tools/README.md` rewrite for its own sake (that's a side effect of whichever scheme wins, not the goal).

**Related**: [IDEA-017](IDEA-017-mind-vault-as-claude-code-plugin.md) (mind-vault as a Claude Code plugin) — if mind-vault becomes a CC plugin, the config-wiring concern (#3 above) may dissolve for the Claude Code host, so `/plan` should weigh that before investing heavily in re-partitioning the symlink scripts. Both surfaced 2026-06-06 while auditing the install-script story behind IDEA-009 (#164) / IDEA-014 (#178).
