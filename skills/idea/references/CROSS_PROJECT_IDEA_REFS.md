# Cross-project idea references — `IDEA-NNN:project`

The incident (2026-08-14): a mind-vault session answered "where were we?" by citing another project's IDEAs with bare numbers. Mind-vault has its own IDEA-016/017; that project has an unrelated IDEA-016/017 — the user could not tell which repo the session was even on. Every project numbers its `IDEA-NNN` stream independently, so a bare number is ambiguous on any surface that can mention two projects: session prose, auto-memory, estate docs, harvest ledgers, compound provenance.

## The grammar

- **Bare `IDEA-NNN` is positional**: inside a repo's files it means that repo's stream; in session/conversation prose it means the session's working repo. If the working repo is ambiguous (multi-repo session, estate sweep), suffix every ref.
- **Foreign refs carry the project suffix**: `IDEA-NNN:project` (teaching examples in mind-vault deliberately use non-digit `NNN` — they sit outside the detector regex below by construction).
- **Canonical detector regex** (quote verbatim wherever the class is matched): `IDEA-[0-9]{3,}:[a-z0-9._-]+` — `{3,}` so a future 4-digit stream doesn't escape the class. The truncated `IDEA-[0-9]{3,}:` spelling is banned: it matches every ordinary idea-title colon (`# IDEA-023: …` — 362 measured false positives repo-wide, 2026-08-14).
- This replaces the ad-hoc prose forms (`(project-x) IDEA-178`, `project-x IDEA-112`) going forward; old prose stays unedited.

## The project token

- The repo's **own name** as its docs refer to it (its checkout dir name in the standard layout), lowercase kebab.
- **Never an alias**: not a plugin/marketplace name, not an env-var name — `IDEA-NNN:mind-vault`, never `IDEA-NNN:mv`.
- Tokens must be estate-unique. If two repos ever share a name across orgs, a qualified form is the tiebreak on non-mind-vault surfaces only.

## Where the suffix CANNOT go

- **Git refnames** — `:` is illegal (`git check-ref-format --branch "idea-050:x"` → fatal; measured 2026-08-14). Branch names like `compound/YYYY-MM-DD-idea-NNN-…` already carry the *originating* project's IDEA number and are a known-ambiguous surface (an agent once picked a foreign branch number as "the next IDEA number"). The defense there stays SKILL.md § 4's scan-from-disk rule: the branch name is NEVER the target project's next number. Do not invent a second separator for refnames.
- **Frontmatter relationship lists** (`related` / `depends_on` / `supersedes`) — same-project bare ids only. A machine-readable cross-repo dependency is its own future IDEA, not a silent extension.
- **Unquoted YAML titles** — a suffixed ref inside a `title:` adds one more colon; § 4's quote-your-titles rule already covers it (an unquoted inner colon kills the whole frontmatter block).

## Scrub-gate interaction (mind-vault only)

Inside mind-vault bodies — `skills/`, `rules/`, `agents/`, `commands/`, and `docs/` including `docs/archive/**` (the provenance-scrub runbook scans it) — the no-foreign-names rule is unchanged: **any namespaced ref whose suffix is not a placeholder is a violation by construction.** The suffix makes foreign refs self-identifying, so this one scrub class is mechanically detectable:

```bash
grep -rEn 'IDEA-[0-9]{3,}:[a-z0-9._-]+' --include='*.md' . | grep -v ':project-'
# expected: zero hits — placeholders use the :project- prefix class (project-x, project-a, …)
```

Classification (model judgment) remains the gate's enforcement mechanism; this grep is the one class where regex is *sufficient*. Commit messages stay exempt (git history is acknowledged-noisy). In consumer projects the suffix is a correctness convention, not a leak hazard — no enforcement tooling there.

Wired: idea SKILL.md § 4 (numbering independence — the attribution half lives here) · compound SKILL.md step 5 foreign-class illustrations + drop-the-tag policy bullet + optional grep aid · compound SKILL.md § 5 Cross-link (commit-message-only foreign refs) · compound SKILL.md "For auto-memory" write-up (memory notes) · wrap SKILL.md Step 4 devlog entry (Related-section foreign refs) · rules/RULE_cross-idea-amendments.md (Amends-trailers are same-repo by construction).
