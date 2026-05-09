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
