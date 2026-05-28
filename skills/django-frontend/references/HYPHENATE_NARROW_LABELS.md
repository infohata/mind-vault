# Hyphenate narrow labels for multi-language UIs

**Scope**: text labels in shell chrome / table headers / nav buttons that compress visibly on narrow viewports (320-480px) in inflected languages (Lithuanian, Polish, Russian, German, Norwegian, etc.). Words in these languages are typically 1.3-1.6× longer than the English source string, and uppercase labels add another 5-15% width via wider glyph metrics. Without hyphenation, long labels either truncate mid-word ("Pilnas administ…") or squeeze siblings into illegible widths.

## The pattern — `hyphens: auto` keyed off `<html lang>`

```scss
.long-narrow-label {
    hyphens: auto;
    -webkit-hyphens: auto;
    -moz-hyphens: auto;
    -ms-hyphens: auto;
    overflow-wrap: break-word;       // belt-and-suspenders for browsers without a dictionary for the active locale
}
```

Browsers resolve hyphens based on `<html lang="...">`. Set the lang attribute correctly per locale (`lt`, `pl`, `ru`, `nb`, etc. — not `en`) and modern browsers (Chrome / Firefox / Safari recent versions) auto-hyphenate using their bundled dictionaries. Without `<html lang>`, browsers default to no hyphenation regardless of the CSS property.

`overflow-wrap: break-word` is the fallback for browsers that don't have a dictionary for the active locale — instead of soft-break at syllable boundaries, the word breaks at the narrow-viewport edge. Less elegant (mid-syllable breaks) but better than overflowing the container.

## Where it earns its keep

Three independent surfaces have needed this in the same shell-architecture project:

1. **Table column headers** inside section cards — multi-word column labels ("Customer Support" / "Pilna kontrolė įskaitant naudotojų valdymą") on 320px viewports squeeze into 2-3 character columns. `hyphens: auto` on `.table th` (mobile breakpoint scope) lets them soft-break naturally.
2. **Workspace nav labels** — uppercase letter-spaced labels (`text-transform: uppercase; letter-spacing: 0.04em`) like "PRENUMERATOS / KVIETIMAI" (lt "Subscriptions / Invitations") squeeze on narrow workspace widths. The pattern applies to ANY long uppercase chrome label.
3. **Sticky section-nav chip labels** (when used in a desktop horizontal strip) — same lt term-length problem.

Pattern is robust across `.table th`, navigation chrome (`.shell-workspace__label`), and any narrow-column display element.

## When NOT to use it

- **Buttons with action-verb labels** ("Add scope" / "Edit" / "Save") — these are short enough that hyphenation never fires; the property is harmless but useless.
- **Headings (h1/h2) on full-width surfaces** — when the heading has enough width, hyphenation doesn't fire. Adding it doesn't help; not adding it doesn't hurt.
- **Content prose** (article body, FAQ text) — apply hyphens at the article level if you want, but it's a style choice, not a width-rescue. Don't bundle it into this pattern's scope.

## Adjacent — using a verb form to sidestep noun-length problems

Where adding `hyphens: auto` rescues the *layout*, using a verb form sidesteps the *content*: "Add property" (verb + accusative noun) replaces "New property" (adjective + nominative noun) in inflected languages, dropping the adjective-noun gender-agreement decision tree. See `<django>/I18N_WORKFLOW.md` § Add-X over New-X for the i18n side of the pattern; this reference covers only the CSS-side hyphenation rescue.

## Test mechanics

Set `<html lang="lt">` on the dev tenant + open the surface at 320×762. The label that was previously squeezing ("Customer<br>Support" or "Pilnas administ…") should now soft-break with a `-` at a syllable boundary. If the break point looks odd, the browser's dictionary for that locale might be incomplete (rare but happens for very recent locale additions); `overflow-wrap: break-word` then kicks in as the fallback.

## Who relies on this

- Any shell chrome / table / nav surface that renders translated labels in lt/pl/ru/nb/de/et/lv/lt etc. languages.
- The CSS-side complement to `<django>/I18N_WORKFLOW.md`'s "Add X" verb-form convention.
