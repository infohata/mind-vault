# RULE_i18n-workflow

## Django Translation Workflow for AI Agents

### The Hard Rules

1. **NEVER edit `.po` files directly** — always regenerate via `makemessages`, then use tooling to fill translations
2. **NEVER run `makemessages` from an app subdirectory** — run from project root to avoid cross-app string contamination (strings from other apps leaking into the wrong locale files)
3. **ALWAYS fix file ownership after extraction** — Docker-based `makemessages` creates root-owned files that block subsequent host edits

### When This Applies

Any time you add or change:
- `gettext_lazy` / `_()` / `ngettext`
- `{% trans %}` / `{% blocktrans %}`
- `format_html` with translatable content
- `verbose_name` / `verbose_name_plural` / `help_text` on models or app configs

### Required Workflow

```bash
# 1. Extract strings from source → regenerate .po files
#    Use project Makefile target or:
python manage.py makemessages -l <locales> --no-obsolete

# 2. Fix file ownership (if using Docker)
chown -R $(id -u):$(id -g) web/*/locale/

# 3. Fill translations from curated map (if project has fill_empty_po.py or similar)
#    Add NEW strings to the map script FIRST, then run it
python tools/fill_empty_po.py <path_to.po> <locale>

# 4. Audit catalogs for carryovers/placeholders/fuzzy regressions (if available)
#    Example: make translate-audit or python tools/audit_translations.py

# 5. Compile .mo files
python manage.py compilemessages
```

### Map-First Principle

If the project has a translation map script (e.g. `fill_empty_po.py`):
- **Add new translatable strings to the map before running fill** — this is cheaper and more reliable than editing each `.po` file by hand
- The map is a reusable asset; direct `.po` edits are lost on next `makemessages`
- Multi-line msgids cannot be auto-filled; leave them for manual review
- If a msgid has a non-empty but wrong carryover translation, keep a force-sync list (for example `FORCE_SYNC_MSGIDS`) so curated map values overwrite stale msgstr entries

### Audit-First Principle

If the project provides translation auditing (for example `translate-audit`), run it before compile.
Typical high-signal checks:
- fuzzy with non-empty msgstr
- placeholder parity mismatch (`%(...)s`, `{...}`)
- action labels translated as bare nouns
- detail/info labels translated as status text carryovers

### Common Pitfalls

| Mistake | Consequence | Prevention |
|---------|------------|------------|
| Edit `.po` directly | Overwritten by next `makemessages` | Use map + fill script |
| Run `makemessages` from app dir | Other apps' strings leak in, existing translations move to obsolete | Always run from project root |
| Skip ownership fix after Docker extract | Permission denied on subsequent edits | Always `chown` after extract |
| Skip audit before compile | Carryovers and placeholder regressions reach runtime | Run audit and fix findings first |
| Forget `compilemessages` | Translations not compiled; runtime uses stale `.mo` | Always compile after changes |
| Skip `--no-obsolete` | Dead strings accumulate in `.po` files | Always pass `--no-obsolete` |

### After Translations

Restart the web server (and Celery if translations affect background tasks) — Django caches compiled `.mo` files in memory.

---

**Last Updated**: 2026-03-17
