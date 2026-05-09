# Django i18n workflow — map-first, never edit `.po` by hand

## The discipline

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

### Map Ownership Follows Template-Extraction Path

When a project shards its translation maps per-app (`tools/translation_maps/<app>.py` — e.g. `ui.py`, `kb.py`, `auth.py`, `core.py`), the map a string belongs in is determined by **which app's `.po` file `makemessages` extracts the msgid to**, NOT by which app the string "logically" belongs to. The fill script loads each map only for its corresponding app's catalog.

The mistake: putting a string in `<app-A>.py` because the string was authored for an app-A surface, but the string actually appears in a template owned by app-B (e.g. an app-A cotton component renders inside an app-B template; an app-A consumer uses an app-B partial that has its own `{% trans %}` calls; an app-A view's template `{% include %}`s an app-B partial). `makemessages` extracts the msgid into `app-B/locale/*/django.po` (because that's where the template lives in the source tree), but `fill_empty_po.py` for `app-B/locale/...` only loads `B_TRANSLATIONS` from `<app-B>.py` — the entry in `<app-A>.py` is dead. All locales render the source-language fallback.

The diagnostic recipe — run from project root after `make translate-extract`:

```bash
# For a specific msgid you suspect is in the wrong map:
grep -l '^msgid "Load older"' web/*/locale/*/LC_MESSAGES/django.po
# → web/<app-B>/locale/lt/LC_MESSAGES/django.po
#   (etc — every locale of the EXTRACTED-INTO app)

# That output tells you which app's <app>.py the map entry needs to live in.
```

A second sweep that's cheap to run periodically — looks for strings that ARE in a map but DON'T appear in the corresponding app's `.po`:

```bash
# Pseudocode — adapt to project's map shape:
for msgid in $(extract_msgids tools/translation_maps/<app>.py); do
    if ! grep -q -F "msgid \"$msgid\"" web/<app>/locale/lt/LC_MESSAGES/django.po; then
        echo "DEAD MAP ENTRY in <app>.py: $msgid"
    fi
done
```

The structural fix when you find a wrong-map entry: cut the entry from `<app-A>.py`, paste into `<app-B>.py`, re-run `make translate-fill` — the empty-msgstr regex picks up the previously-untranslated entries and fills them in one pass.

The deeper design tension this surfaces: **shared cotton components / shared partials with embedded `{% trans %}` calls force translations into every consuming app's catalog.** A `<c-foo>` cotton component used by 5 apps has its `{% trans %}` strings extracted to all 5 apps' catalogs (because each consuming app's template is what `makemessages` scans). The map-ownership rule says: maintain the entries in the consuming-app's `<app>.py`, even when the string was authored alongside the cotton component. Duplicate the entries in each app's map if the same component renders across apps. Yes — translation maps are fragile, AI-token/performance optimised over surface elegance, but the duplication is the price.

#### Worked diagnostic recipe

When a string isn't translating, the FIRST diagnostic is "which app's `.po` file does `makemessages` extract this msgid into?" — NOT "which app's translation map should logically own it?":

```bash
# 1. Find which app's .po file makemessages extracted the msgid into.
grep -l "^msgid \"<the visible string>\"" web/*/locale/*/LC_MESSAGES/django.po
# Output → e.g. web/<app>/locale/<locale-1>/LC_MESSAGES/django.po
#                web/<app>/locale/<locale-2>/LC_MESSAGES/django.po
#                web/<app>/locale/<locale-3>/LC_MESSAGES/django.po
#                (one line per configured locale of the EXTRACTED-INTO app)

# 2. Check that app's translation map has the entry.
grep -n "'<the visible string>'" tools/translation_maps/<that-app>.py
# If absent → the entry needs to live HERE.

# 3. Check OTHER maps for misplaced duplicate entries.
grep -rn "'<the visible string>'" tools/translation_maps/
# If a different app's map has the entry → that's the wrong-map regression.
# Cut from the wrong map, paste into the right map per step 2.
```

Logical-ownership traps that cause this regression:
- A workspace button labelled with content-domain wording (e.g. "+ Article") *feels* like a content-app concern, but if it lives in the shared shell/UI app's template, the msgid extracts to the shell-app catalog.
- A toast or label emitted by shared infra (e.g. a `notifications.js` helper) *feels* like UI, but if the calling code is in `<content-app>/static/...`, the msgid extracts wherever the JS path's source files reside.
- Cotton components consumed across apps: the msgid extracts to EVERY consuming app's catalog (one shared component → N entries needed in N maps; see the previous paragraph).

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
| Translation map shipping msgids with no Python source | `makemessages` never extracts the msgid; map entries never reach `.po`; lookups fall back to source-language; translations sit dead | Every msgid in `tools/translation_maps/*.py` MUST have a matching `_()` / `gettext_lazy(...)` source somewhere in `web/`. When adding strings, add the Python source FIRST (e.g. `_NETWORK_ERROR = _("Connection failed")` in a module that gets imported at startup), then the map entry. `makemessages` is the bridge — it only sees what the AST contains. |

### After Translations

Restart the web server (and Celery if translations affect background tasks) — Django caches compiled `.mo` files in memory.

---

**Last Updated**: 2026-05-08
