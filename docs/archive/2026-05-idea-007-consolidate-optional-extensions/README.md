# IDEA-007 — Consolidate `Optional extensions` blocks into `## References`

**Status**: ✅ Complete
**Completed**: 2026-05-22
**PR**: [#135](https://github.com/infohata/mind-vault/pull/135)
**Related**: [IDEA-002](../2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md) (body-level debloat precedent), PR [#134](https://github.com/infohata/mind-vault/pull/134) (skill-writer rule codification)

## What shipped

Removed the duplicate `**Optional extensions** (load on demand):` block from three feature-dense skills (`deployment`, `django`, `django-frontend`) and consolidated their entries into the canonical `## References` section per `skills/skill-writer/SKILL.md` body §"Body structure" item 5 (codified in PR #134).

| File | Before | After | Δ |
|---|---:|---:|---:|
| `skills/django/SKILL.md` | 596 | 584 | **-12** |
| `skills/deployment/SKILL.md` | 473 | 465 | **-8** |
| `skills/django-frontend/SKILL.md` | 627 | 608 | **-19** |
| **Total** | | | **-39 lines** |

Also dropped the same `Optional extensions` terminology from `skills/deployment/README.md`'s tree-diagram comment (`references/  # On-demand references (linked from SKILL.md ## References)`).

## Dedup approach

Per file: diff top-block entries vs `## References`, promote any richer descriptions from top → bottom, add any genuinely-unique top entries to bottom, then delete the top block. No reference content edits, no `## References` reordering (append-only preserves git-blame for historical entries).

- **django**: all 9 top entries mirrored. Promoted 6 richer descriptions (the `(django-tenants)` qualifier, `async job processing`, `structured logging and audit trails`, `translation workflow, fuzzy-wipe, locale testing`, `query-count asserts, locale enforcement, isolation`, `env config, Docker dev-loop`).
- **deployment**: 7 of 9 mirrored. Promoted 4 richer descriptions (concrete tool names: `Prometheus, Grafana, ELK` for MONITORING; `SSH, UFW, fail2ban, unattended upgrades` for HARDENING; `GitHub Actions, GitLab CI, secrets, approval gates` for CICD; `migrations, collectstatic, ASGI` for DJANGO_DEPLOYMENT). Added 2 unique entries (`CONTAINER_DNS_NSS`, `SHELL_INSTALLERS`).
- **django-frontend**: all 17 mirrored. Promoted 3 (BASE_TEMPLATE / MODAL_SYSTEM had bare-link descriptions in bottom; SESSION_FILTER_PERSISTENCE had constant names dropped — added back the `cross_filters_<org_id>` / `<namespace>_<entity>_filters_<org_id>` for grep usefulness).

## Why now

- The single-`## References`-block rule had just been codified during PR #134 in `skills/skill-writer/SKILL.md` body §"Body structure" item 5 — the three offender skills were named explicitly. Close the gap while the policy is fresh.
- Each per-activation context load of these three skills (among the highest-frequency in the vault) pays the duplicate-index token tax. Token-cost compounds at sprint-auto-scale invocation rates.
- Index-level continuation of [IDEA-002](../2026-05-idea-002-skill-debloat/IDEA-002-skill-debloat.md)'s body-level debloat lever — same "load-on-demand" discipline applied at the index level rather than the body level.

## Commit sequence (one per file for bisect-ability)

1. `67e9997` — `chore(skills): django — consolidate Optional extensions into ## References (IDEA-007)`
2. `3395484` — `chore(skills): deployment — consolidate Optional extensions into ## References (IDEA-007)`
3. `42c2f75` — `chore(skills): deployment README — drop 'Optional extensions' terminology (IDEA-007)`
4. `3d81557` — `chore(skills): django-frontend — consolidate Optional extensions into ## References (IDEA-007)`
5. `03280ae` — plan paper-trail (✅ markers + `status: shipped`)

Plus the prior `8c263be` from `/plan` (archive-dir creation + IDEA file move + plan emission), and the wrap commit (this README + frontmatter flip + CHANGELOG + ideas-index re-sort).

## Verification (post-execution)

```bash
$ grep -l "Optional extensions" skills/*/SKILL.md
# Returns only skills/skill-writer/SKILL.md (the codified rule), confirming
# zero remaining offenders in the SKILL.md surface.

$ for f in skills/{deployment,django,django-frontend}/SKILL.md; do
    echo "$f: $(grep -c '^## References' $f) References sections"; done
skills/deployment/SKILL.md: 1
skills/django/SKILL.md: 1
skills/django-frontend/SKILL.md: 1
```

## Follow-up

None — sweep is complete. The single-`## References` rule is now both codified (in skill-writer) and enforced across all known violators.
