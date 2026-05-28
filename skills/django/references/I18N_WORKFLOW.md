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
- **A toast / `messages.*` emitted from a view in app-A *about* an app-B entity** (e.g. app-A's shell-fragment or CRUD view sends a `_("…created")` success toast for a model that lives in app-B). The `_()` call site is in app-A's Python, so `makemessages` extracts the msgid into **app-A**'s catalog and the map entry belongs in `<app-A>.py` — NOT the app whose entity the message is "about". The about-ness is the trap; the `gettext` call-site app is the authority. (Symptom: blank toasts in every non-source locale because the entry sat in the entity's app map, where that catalog never extracted it.)
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

## GNU gettext singular/plural hash collision — don't rewrite an existing singular msgid into a plural-only entry

GNU gettext stores singular and plural forms under **different hash keys** in the compiled `.mo`. A `gettext("Scope")` lookup hashes the singular form; an `ngettext("Scope", "Scopes", n)` lookup hashes the plural pair. The two are independent — a singular lookup against a plural-only entry **does not fall back** to the plural's `msgstr[0]`; it falls back to the source string (English).

The failure mode: an existing singular msgid `"Scope"` with msgstr `"Aprėptis"` is consumed by a refactor that introduces `{% blocktrans count counter=N %}Scope{% plural %}Scopes{% endblocktrans %}`. After `makemessages`, the `.po` file has **one** entry for `msgid "Scope"` — the plural one. The dozens of pre-existing singular callers (`{% trans "Scope" %}`, `_("Scope")` in models / forms / table headers) now fall back to English silently.

```
# Before refactor — singular-only entry, singular callers translate
msgid "Scope"
msgstr "Aprėptis"

# After refactor — plural entry merged in via makemessages dedup
msgid "Scope"
msgid_plural "Scopes"
msgstr[0] "Aprėptis"
msgstr[1] "Aprėptys"
msgstr[2] "Aprėpčių"
# (Same msgid key; the singular-only entry no longer exists.)

# Now `gettext("Scope")` ↛ "Aprėptis"; instead returns "Scope" (English).
```

Symptom: section-card *count-bearing* headers translate correctly (the blocktrans is finding the plural entry), but the same noun appearing as a standalone column header, `verbose_name`, or `<th>{% trans "Scope" %}</th>` renders the source English string only in non-English locales. Visible only in inflected target locales, never in English.

### Fix — drop the blocktrans, use always-plural `{% trans 'Plural' %}` with a count separator

The clean fix is to NOT inflect the noun based on count, and instead present the noun in its plural form unconditionally, with the count carried in a separate element:

```html
{# Before — blocktrans inflects, collides with singular callers: #}
<div class="card-header-title">
    {% blocktrans count counter=N %}Scope{% plural %}Scopes{% endblocktrans %}
    ({{ N }})
</div>

{# After — always-plural noun + count separator (e.g. " · 6"): #}
<div class="card-header-title">
    {% trans "Scopes" %}<span class="count-separator"> · {{ N }}</span>
</div>
```

Modern UI convention (Slack / Linear / GitHub) accepts this — section labels like "1 Scopes" or "1 Properties" read slightly off grammatically but are universally understood, AND the gettext semantics stay clean (one singular-only msgid per noun, one plural-only msgid for any inflected callsite that genuinely needs it under a different msgid).

### Alternative — `msgctxt` disambiguation

The grammatically-correct fix is to keep the blocktrans + add `context "count"` so the plural form lives under a different hash key:

```html
{% blocktrans count counter=N context "count" %}Scope{% plural %}Scopes{% endblocktrans %}
```

This produces `msgctxt "count"; msgid "Scope"; msgid_plural "Scopes"` in the `.po` — distinct from the singular-only `msgid "Scope"`. Both can coexist.

The trade-off: the project's translation-map / fill-script pipeline needs `msgctxt` awareness. If the fill script regex-matches on bare `^msgid "X"$` (a common shape), it won't match the `msgctxt`-prefixed entry and the new plural msgstrs go unfilled. Audit the fill tooling before choosing this path.

### Diagnostic recipe

When a string suddenly renders as English in non-English locales after a blocktrans refactor:

1. `grep -rn '^msgid "<X>"$' web/<app>/locale/<locale>/LC_MESSAGES/django.po` — count occurrences.
2. If 1 hit AND the next line is `msgid_plural "..."`, you've just rediscovered this trap. The singular callers stopped translating.
3. Check translation extraction warnings — `makemessages` emits "Here is the occurrence without plural / Here is the occurrence with plural" warnings when it dedupes the singular into the plural entry. They are NOT errors; they SHOULD be.

## Always-plural button labels — use the verb form to sidestep adjective-noun gender agreement

`{% trans "New scope" %}` requires the target locale's translation to express *adjective gender agreement* with the noun. In Lithuanian, `scope` (lt `aprėptis`) is feminine, so the adjective is `nauja` (feminine "new"): `Nauja aprėptis`. But `property` (lt `nuosavybė`) is ALSO feminine — `Nauja nuosavybė`. Easy to consistently apply the rule, until somebody chooses a parallel word for "property" (`objektas` — masculine "object"): `Naujas objektas`. Now scope says `Nauja…` and property says `Naujas…` and the inconsistency is the bug.

In Polish, Russian, German, etc. the same problem fires per-locale with different noun-gender conventions.

The escape hatch — use the **verb form** instead of the **adjective + noun**:

```html
{# Before — adjective + noun, every locale must express gender agreement: #}
<a class="button">{% trans "New scope" %}</a>            {# lt: Nauja aprėptis | pl: Nowy zakres | … #}
<a class="button">{% trans "New property" %}</a>         {# lt: Naujas objektas (DISAGREEMENT vs scope) | … #}

{# After — verb + accusative noun, no adjective gender to agree: #}
<a class="button">{% trans "Add scope" %}</a>            {# lt: Pridėti aprėptį | pl: Dodaj zakres | ru: Добавить область | nb: Legg til omfang #}
<a class="button">{% trans "Add property" %}</a>         {# lt: Pridėti nuosavybę | pl: Dodaj nieruchomość | ru: Добавить объект | nb: Legg til eiendom #}
```

Why this works: the verb is invariant (no adjective), and the noun takes its accusative case (which the translator's reflex handles correctly because every Lithuanian / Polish / Russian schoolchild learns "the direct object of a transitive verb takes accusative"). No adjective-noun gender decision tree.

The pattern matches the established **"Add Domain"** convention any well-internationalised CRUD app already uses for one entity — generalise it across every entity-CRUD button (`Add scope`, `Add property`, `Add organization`, `Add article`, `Add event`, `Add FAQ`, etc.).

### When NOT to apply

- **Chat-specific UX vocabulary** ("New session", "New conversation", "New chat") — these aren't "add to a collection"; they're "start fresh". The semantic distinction matters more than gender-agreement uniformity. Keep the existing form; if the locale has a gender bug, fix it locally without overhauling the verb.
- **Page titles / headings that read like English nouns** — "New project" as a page title is a noun phrase, not a button label. Heading-style usage carries its own conventions; don't rename "New project" the *heading* just because you renamed "Add project" the *button*.
- **Single-word labels** (`+ New`, `+ Add`) — these are short enough that no inflection happens; the choice is cosmetic.

### Migration discipline

When renaming `"New X"` → `"Add X"` in templates, the translation map keys also rename. **Update FORCE_SYNC_MSGIDS to track the new key** — a stale entry pointing at the renamed-away `"New X"` becomes a silent no-op (the fill script's `all_trans.get("New X")` lookup finds nothing; the force-sync exits without writing). See § *FORCE_SYNC stale msgid after rename* below.

## FORCE_SYNC stale msgid after rename

When a translation map key is renamed (e.g. `"New property"` → `"Add property"`), grep `FORCE_SYNC_MSGIDS` for the old name. A stale entry silently no-ops:

```python
# Before — entry valid, fill overwrites the .po
FORCE_SYNC_MSGIDS = {
    'New property',          # auth.py has 'New property': {...}
}

# After a rename of the auth.py key from 'New property' → 'Add property'
# but FORCE_SYNC_MSGIDS NOT updated:
FORCE_SYNC_MSGIDS = {
    'New property',          # auth.py NO LONGER has 'New property'; stale.
}
# Fill script: all_trans.get('New property') → None → no-op.
# Future canonical-value edits to lt 'Add property' don't propagate.
```

**Audit recipe** for any rename that includes a translation map key:

```bash
# After renaming 'OldKey' → 'NewKey' in tools/translation_maps/<app>.py,
# grep FORCE_SYNC_MSGIDS (typically in shared.py) for the old key:
grep -n "'OldKey'" tools/translation_maps/shared.py
# If hit → replace with 'NewKey'.
```

Even better — fold the audit into the rename-before-drop sequence (`RULE_rename-before-drop`): the post-rename verification step should include a fill-script telemetry check that the renamed key still has an effective force-sync. The earlier "translate-fill reports force-synced N entries" telemetry trap discussed in [*FORCE_SYNC_MSGIDS — translate-fill silently skips existing msgstr without it*](#force_sync_msgids--translate-fill-silently-skips-existing-msgstr-without-it) § *The telemetry trap* compounds with this: if FORCE_SYNC_MSGIDS has N entries but K of them are stale, the fill reports "N force-synced" while only (N-K) effective writes happened.

### Diagnostic recipe — when a renamed string didn't pick up its canonical translation

1. Confirm the map entry exists under the **new** key in the right `<app>.py`.
2. Grep `FORCE_SYNC_MSGIDS` (typically `shared.py`) for the **old** key. If found → replace with new key.
3. Re-run `translate-fill` and verify the affected `.po`'s msgstr changed.

When the rename touched ≥2 keys, audit each.

## Adjacent: the CSS-side rescue for narrow viewports

When labels can't be shortened further (verbose translations of unavoidable concepts), the CSS-side complement is `hyphens: auto` keyed off `<html lang>` — see [`../../django-frontend/references/HYPHENATE_NARROW_LABELS.md`](../../django-frontend/references/HYPHENATE_NARROW_LABELS.md). The two patterns compose: this reference's translation-side conventions for "what string ships at all", that reference's CSS-side conventions for "how it wraps when it doesn't fit".
