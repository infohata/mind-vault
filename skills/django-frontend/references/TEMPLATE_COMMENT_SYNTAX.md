# Template comment syntax — `{# inline #}` is single-line only

**When this fires**: writing comments inside Django templates. Django has two comment syntaxes and they are NOT interchangeable. The django-frontend SKILL.md body's template-comment section holds the firing-conditions stub; this reference holds the full syntax matrix + content-leak failure mode + grep-based detection recipe.

## The two syntaxes

| Syntax | Multi-line? | Use for |
| --- | --- | --- |
| `{# … #}` | **No** — single-line only | A short inline note on one line |
| `{% comment %} … {% endcomment %}` | Yes | Anything spanning multiple lines |

## The content-leak failure mode

The failure mode when the wrong one is used: **content leak**. If a `{#` opens and a newline appears before the closing `#}`, Django's tokeniser fails to recognise the construct as a comment and emits the entire block as plain text into the rendered output. No template error, no test failure — just literal "comment" text shown to end users.

```django
{# This is fine — opens and closes on the same line. #}

{# THIS IS BROKEN — multi-line {# #} renders as visible
   text on the page because Django's tokeniser only matches
   {# … #} when both delimiters are on the same line. #}

{% comment %}
    This works for any number of lines. Use this whenever
    the comment doesn't fit on a single line, especially
    documentation comments above template blocks.
{% endcomment %}
```

Worked example — teisutis IDEA-124 PR #375 ([fix commit](https://github.com/infohata/teisutis/commit/c68905ab)): a multi-line `{# … #}` block documenting the audio-fallback behavior leaked its contents onto the rendered chat-input area. Visible to every user picking a voice file pre-send. Bugbot didn't catch it because the regression suite tested the partial in isolation and the comment was in chat.html itself, not the partial. Surfaced immediately on first manual browser hit on staging.

## Detection during review

Grep for `{#` followed by a newline before `#}`:

```python
import re, pathlib
for path in pathlib.Path('.').rglob('*.html'):
    text = path.read_text(errors='replace')
    for m in re.finditer(r'\{#', text):
        rest = text[m.start():]
        nl, end = rest.find('\n'), rest.find('#}')
        if end == -1 or (nl != -1 and nl < end):
            line_no = text[:m.start()].count('\n') + 1
            print(f'{path}:{line_no}: multi-line {{# #}} — convert to {{% comment %}}')
```

CI hook this as a pre-commit lint when the templates surface starts to grow.

## Stacks of single-line `{# … #}` are also broken

A stack of single-line `{# foo #}` lines forming a paragraph reads like a multi-line comment to humans but parses correctly per-line — until one line contains a `{% include %}` / `{% load %}` / `{% extends %}` literal in the prose, at which point the engine tries to parse the tag and crashes. Even when no tag-literal lurks, the stack is fragile: the next contributor adding context "obviously" wraps it as `{# %}` and inherits the multi-line bug.

Convention: any comment intent spanning more than one line — including stacks of single-line `{#` lines forming a paragraph — converts to `{% comment %}…{% endcomment %}`. Single-line inline `{# foo #}` next to a tag stays fine.

## Don't translate developer notes

Never wrap a developer note in `{% trans %}` — it gets extracted into `.po` files, "translated" via translation maps, and shipped to users as page copy. Forward-looking notes ("TODO refactor this", "Phase 2 will replace this", "see IDEA-NNN") belong in `{% comment %}…{% endcomment %}` blocks:

```django
{# ❌ Wrong — string lands in .po, maps add "translations", users see the note #}
{% trans "TODO: drop this fallback in Phase 2 once IDEA-NNN ships" %}

{# ✅ Right — invisible to extraction and to users #}
{% comment %}
TODO: drop this fallback in Phase 2 once IDEA-NNN ships.
See docs/archive/YYYY-MM-idea-NNN/.
{% endcomment %}
```

Audit recipe — grep for `{% trans %}` strings that look like dev notes (contain `TODO`, `FIXME`, `Phase`, `see IDEA`, `legacy`, `deprecated`):

```bash
grep -rEn '\{%\s*trans\s+"[^"]*(TODO|FIXME|Phase|see IDEA|legacy|deprecated)' \
    --include="*.html"
```

Every match is a candidate for conversion. The Django i18n workflow reference covers the catalog-side cleanup: [`../../django/references/I18N_WORKFLOW.md`](../../django/references/I18N_WORKFLOW.md) § *Map ownership follows template-extraction path*.

## `{% blocktrans %}` placeholder format is `%(var)s` in `.po`, not `{{ var }}`

Inside a `{% blocktrans %}…{% endblocktrans %}` block, template variables write as `{{ var }}` — but Django's makemessages converts them to `%(var)s` in the extracted `.po` file. Translation maps that key on the visible-on-template form (`Hello {{ user }}!`) never match — see [`../../django/references/I18N_WORKFLOW.md`](../../django/references/I18N_WORKFLOW.md) § *`{% blocktrans %}` placeholders extract as `%(var)s`, not `{{ var }}`* for the canonical map-key contract + audit-tool placeholder-parity check.

**Last Updated**: 2026-05-14
