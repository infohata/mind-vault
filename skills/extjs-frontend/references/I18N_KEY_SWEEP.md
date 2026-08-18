# i18n as backend data — key sweep, dynamic families, idempotent seeds

## 1. How a string reaches the screen

```text
code:  'app_entitydialog_title'                    ← a KEY, never a literal
  │  TranslateText.t(key)  /  localized: { title: key } (auto-applied by a Component override)
  │  / wrapper-field *Label / *Info configs
  ▼
dictionary (in memory)  ← GET /api/app/translations/<lng>   once at boot (language = a cookie)
  ▼
value — or, if the key is absent OR empty: THE KEY ITSELF, verbatim, on the screen
```

Consequences: **translations are backend data** (the SPA holds keys; a key is done only when the
row exists in the backend table); **a missing key is invisible to every automated gate** — unit
tests never render, mock e2e serves the dictionary from a fixture; it surfaces only on a real
screen against a real backend (a first credentialed walk through a pilot found ~330 raw keys);
**empty ≠ absent but renders the same** (`lt` filled, `pl` empty → Polish users see the key).

## 2. The gate: a static sweep of `app/**` vs the live dictionary

A script scans `app/` for `'<prefix>_*'` string literals (comments stripped), applies the dynamic
families below, fetches the dictionary per language (`--base-url <host>` / `--dict file.json` /
the e2e fixture offline) and **exits 1 while anything is missing**.

```bash
npm run i18n:sweep -- --base-url https://<host> --lng lt,en,ru,pl                 # MISSING per language
npm run i18n:sweep -- --overlay <feature-dir>/translations.json --base-url …      # seed completes the code? → MISSING: 0
npm run i18n:sweep -- --expect-missing <feature-dir>/translations.json --base-url … # exit 0 iff missing == exactly the seed
npm run i18n:sweep -- --sql > new-keys.sql                                       # skeleton for what is still missing
```

Pre-merge habit for any UI PR: the sweep against a dev backend lists exactly your new keys
(proves they are keys, not literals) and your feature dir carries a seed for exactly that set.

**Hidden fields count** (a `hidden: true` field's label is still a key). **Dynamic families must be
enumerated by hand** — the scanner cannot see them:

| pattern in code | key actually looked up | handling |
| --- | --- | --- |
| info-handle configs `appselectfieldInfo: 'app_faq_field_x'` | `app_faq_field_x_info` (the helper appends `_info`) | sweep rule: `*Info` handles → `+ '_info'` |
| concat stems `'app_status_' + record.get('status')` | data-driven | list the enum values in the sweep's family table |
| `AppContext.param('app_…')` | not a translation — an app parameter | exclude by prefix |

Add a family row whenever you introduce a new stem.

## 3. Per-feature manifest → idempotent seed SQL

Each feature that adds keys ships in its own dir:

- `translations.json` — source of truth: `{ meta, inserts: { key: { lt, en, ru, pl, files } }, updates: { key: { lng: value } } }`
- `translations.sql` — GENERATED (`npm run i18n:seed -- <dir>/translations.json > <dir>/translations.sql`)
- `translation-keys.md` — GENERATED manifest for reviewers (`--md`)

SQL contract, identical for every feature so ops treat every seed alike:

```sql
-- inserts: never overwrite
INSERT INTO translations (`default`, lt, en, …) SELECT 'app_x', 'Reikšmė', 'Value', … FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM translations WHERE `default` = 'app_x');
-- updates: fill EMPTY cells only, never a human-authored value
UPDATE translations SET pl = 'Wartość' WHERE `default` = 'app_x' AND (pl IS NULL OR pl = '');
```

To *change* a value, write a plain `UPDATE` by hand and say why in `meta.note`. Never hand-edit
the `.sql`: edit JSON, regenerate, commit all three.

## 4. Applying a seed on a backend (operator, HITL)

- Apply **through the backend app's own DB connection** (a small PHP/Python helper executing one
  statement per line via the app's PDO/ORM under the tenant's host context) — the operator never
  handles DB credentials, and multi-tenant backends select the tenant from the host.
- The served dictionary is usually **cached** (file/redis) with no TTL — **drop the backend's
  dictionary cache after seeding** (the app's own cache-clear command, or the cache key by hand);
  it rebuilds on the next request; no frontend build step.
- Verdict from the laptop: `npm run i18n:sweep -- --base-url https://<host> --lng …` → `MISSING: 0` × N.
- Order for a release: seed **before** the image rebuild — the app references the keys from that
  build on.

## 5. Authoring

- Source language first; match the existing glossary (grep the live dictionary for sibling keys —
  the house style is in there). Other languages mirror meaning, not word order.
- Agent-authored non-source values are machine-grade by definition — say so in `meta.note`; a
  native reviewer amends the JSON, regeneration is one command.
- Confirm dialogs: `<x>_title` short with `?`, `<x>_text` a sentence; loadmasks end with `…`;
  toasts past tense.
- Assertions in Jest pin the **key** (identity `t` stub); e2e in mock mode sees keys too — do not
  assert translated text there.
