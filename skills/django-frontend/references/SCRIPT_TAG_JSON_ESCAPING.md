# Server-rendered JSON in a `<script>` tag must be script-tag-escaped (stored-XSS)

**When this fires**: a Django view serialises model-derived data to JSON and embeds it in the page
for JS to read on load — a preview-seed payload, an Alpine `x-data` bootstrap, a nav/url map, any
`<script>…JSON…</script>` or `<script type="application/json">…</script>` block whose content includes
**any user-controllable string** (entity names, descriptions, filenames, tags, org/scope labels).

The naive shape is a **stored-XSS vector**:

```django
{# views.py #}
context['preview_seed_json'] = mark_safe(json.dumps(preview_seeds))   {# ⚠️ XSS #}
```
```html
<script type="application/json" id="preview-seed">{{ preview_seed_json }}</script>
```

`json.dumps` escapes JSON syntax (quotes, backslashes) but **does NOT escape `<`, `>`, `&`**. An entity
named `</script><img src=x onerror=alert(document.cookie)>` serialises verbatim; the browser's HTML
parser sees the literal `</script>`, closes the block early, and runs the injected markup. `mark_safe`
then disables Django's autoescape, so the payload reaches the DOM intact. It's *stored* XSS: the name
was saved earlier by one user (or tenant) and fires in every later viewer's browser.

## The fix — escape `<`, `>`, `&` as `\uXXXX` before embedding

Mirror what Django's built-in `{{ value|json_script:"id" }}` template tag does. The escaped output is
still valid JSON — `JSON.parse` decodes the `\uXXXX` back to the original characters at runtime — so JS
reads the real string; only the HTML parser is denied the `</script>` sequence.

```python
# json_utils.py — single source of truth for script-tag-safe JSON.
import json
from django.utils.safestring import mark_safe

_SCRIPT_TAG_ESCAPES = {ord('<'): '\\u003C', ord('>'): '\\u003E', ord('&'): '\\u0026'}

def escape_for_script_tag(text: str) -> str:
    """Escape <, >, & as \\uXXXX so a JSON string is safe inside a <script> block."""
    return text.translate(_SCRIPT_TAG_ESCAPES)

def escape_seed_json(seeds) -> str:
    """Serialise + script-tag-escape a seed payload for embedding. '' when falsy."""
    if not seeds:
        return ''
    return mark_safe(escape_for_script_tag(json.dumps(seeds)))
```

## Prefer the built-in when you can

`{{ data|json_script:"preview-seed" }}` does exactly this escaping and emits the wrapping
`<script type="application/json" id="preview-seed">`. Reach for the manual helper only when you need
the raw escaped string in a different context (an inline `x-data="…"`, a custom wrapper, or a context
processor that several templates share) — and route every such site through ONE helper, never an
ad-hoc `mark_safe(json.dumps(...))` per view.

## Sweep ALL siblings, not just the one flagged

This is a systemic vector: a project that embeds one seed payload usually embeds the same shape across
every shell/surface view. When a review flags one `mark_safe(json.dumps(...))`, grep the whole tree
(`grep -rn "mark_safe(json.dumps" web/`) and convert **all** of them in the same PR — fixing one view
while eight siblings stay vulnerable is a false sense of closure. (Surfaced on a shell-migration PR: the
same `mark_safe(json.dumps(preview_seeds))` appeared in 9 surface views; all 9 routed through one
`escape_seed_json` helper in a single sweep.)

## Test it

Render the view with an entity whose name contains `</script>` and assert the literal `</script>` does
NOT appear in the response while the escaped `</script>` does — and that JS still parses the
payload back to the original name.
