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

## `FORCE_SYNC_MSGIDS` — translate-fill silently skips existing msgstr without it

When a project's fill script (e.g. `tools/fill_empty_po.py`) updates `.po` catalogs from translation maps, the default behaviour is **only write to msgids where msgstr is empty**. Updating a translation map entry whose msgid already has a (different, possibly wrong) msgstr does *nothing* — the fill skips it silently.

The escape hatch is a `FORCE_SYNC_MSGIDS` set of msgids the script considers "always overwrite". To re-sync an msgid after fixing the translation map, add it to the set:

```python
# tools/translation_maps/shared.py
FORCE_SYNC_MSGIDS: set[str] = {
    'Save',                  # had wrong translation; new value forces overwrite
    'Hello %(name)s!',       # blocktrans entry that needed placeholder-form fix
    # ...
}
```

Without this, the workflow leaves a dead map entry behind: the map looks right, the fill script reports success, the `.po` file still has the wrong (or empty) msgstr. The user-facing translation never updates.

### The telemetry trap

If the fill script reports "force-synced N entries", N is the count of entries **in `FORCE_SYNC_MSGIDS`**, not the count actually overwritten. An entry in the set with no matching msgid still counts toward N. The telemetry suggests progress when none happened.

Recommendation: add a `--force <msgid>` CLI flag to the fill script for one-off overrides without permanent set membership, and surface "actually-overwritten N" telemetry separately from "force-set size N".

### Diagnostic recipe

When a translation isn't updating:

1. Confirm the map entry exists in the right `<app>.py` (the wrong-map regression is more common — see *Map ownership* above).
2. If the entry is in the right map, check the `.po` file's existing msgstr — is it empty (will fill) or populated (won't fill without force)?
3. If populated, add the msgid to `FORCE_SYNC_MSGIDS` and re-run translate-fill.
4. Re-check the `.po` to confirm the new value landed.

### The same msgid can live in MULTIPLE app catalogs — fix EVERY map, not just one

*Map ownership* above describes the single-owner case (a string `makemessages` extracts to exactly one app's `.po`). But a short literal used in templates across apps (e.g. `"FAQ"` appearing in both a `ui` shell template and a `kb` partial) is extracted into **each** of those apps' `.po` files. The fill script resolves the force-sync value **per-app** — `all_trans = SHARED + <that-app>.py` — so:

- Correcting the msgid in only `ui.py` updates `ui/<locale>.po` but leaves `kb/<locale>.po` on the old/stale value (or, worse, *introduces* a wrong value if `kb.py` had its own divergent entry that force-sync then writes).
- The catalogs silently disagree: one surface renders the corrected term, another the stale one.

**Fix recipe**: grep ALL maps for the msgid — anchor on the quoted key, not a fixed indent, since maps nest (`APP_TRANSLATIONS = { 'lt': { … } }`) and msgid lines sit deeper than any one column: `grep -rn "'<msgid>':" tools/translation_maps/*.py` (or `grep -rnF "'<msgid>':"` if the msgid has regex metachars). Set the same value in **every** app map that has it (or that its `.po` extracts to), add the msgid to `FORCE_SYNC_MSGIDS` once (it's global), then `translate-fill`. Verify each affected `.po` shows the new msgstr. A one-map edit is the trap — the per-app resolution means consistency is only as good as the *least*-updated catalog.

## Don't translate developer notes — they leak into `.po` and ship to users

A `{% trans "TODO: refactor this in Phase 2" %}` block extracts into `.po`, translation maps add msgstr entries, the result ships to end users as page copy. The fix is at the template layer (`{% comment %}` instead of `{% trans %}`) — see [`../../django-frontend/references/TEMPLATE_COMMENT_SYNTAX.md`](../../django-frontend/references/TEMPLATE_COMMENT_SYNTAX.md) § *Don't translate developer notes* for the canonical template-side recipe + audit grep.

## `{% blocktrans %}` placeholders extract as `%(var)s`, not `{{ var }}`

Inside `{% blocktrans %}…{% endblocktrans %}`, template variables write as `{{ var }}` — but makemessages converts them to `%(var)s` in the extracted msgid. Translation map keys MUST match the `.po` form:

```python
APP_TRANSLATIONS = {
    'lt': {
        'Hello %(name)s!': 'Sveiki, %(name)s!',   # ✅ matches .po msgid
        # 'Hello {{ name }}!': '…',               # ❌ never matches, dead entry
    },
}
```

The audit's placeholder-parity check is the canary — every map entry whose key contains `{{ }}` is suspect; convert to `%(var)s` form.
