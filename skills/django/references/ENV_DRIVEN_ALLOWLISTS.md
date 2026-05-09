# Env-driven allowlists / denylists as `frozenset`

**When this fires**: needing a list (blocked MIME types, blocked file extensions, IP allowlists, feature flags keyed by tenant) that wants three properties at once: per-deployment override without code change, O(1) membership lookup at hot paths, immutability so request handlers can't mutate global state. The django SKILL.md body's env-driven-allowlists section holds the firing-conditions stub; this reference holds the full pattern + earn-their-keep notes + when-not-to-use.

## Three properties, one shape

1. **Per-deployment override without a code change** — sysop changes the policy via env var.
2. **O(1) membership lookup** at request-handling hot paths.
3. **Immutability** so a request handler can't accidentally mutate the global set.

`frozenset` parsed from a comma-separated env var with a sane default in code gives all three:

```python
# settings.py
ATTACHMENT_BLOCKED_UPLOAD_MIMES = frozenset(filter(None, (
    m.strip().lower() for m in os.getenv(
        'ATTACHMENT_BLOCKED_UPLOAD_MIMES',
        'application/x-msdownload,application/x-msdos-program,'
        'application/vnd.microsoft.portable-executable,application/x-dosexec,'
        'application/x-msi,application/x-executable,application/x-elf,'
        'application/x-mach-binary,application/x-sh,application/x-shellscript,'
        'application/java-archive'
    ).split(',')
)))
ATTACHMENT_BLOCKED_UPLOAD_EXTENSIONS = frozenset(filter(None, (
    e.strip().lower().lstrip('.') for e in os.getenv(
        'ATTACHMENT_BLOCKED_UPLOAD_EXTENSIONS',
        'exe,dll,msi,bat,com,scr,cpl,so,dylib,class,jar,war,ear'
    ).split(',')
)))
```

```python
# usage
def is_blocked(mime: str, filename: str) -> bool:
    norm = (mime or '').split(';', 1)[0].strip().lower()
    if norm and norm in settings.ATTACHMENT_BLOCKED_UPLOAD_MIMES:
        return True
    if filename and '.' in filename:
        ext = filename.rsplit('.', 1)[-1].lower()
        if ext and ext in settings.ATTACHMENT_BLOCKED_UPLOAD_EXTENSIONS:
            return True
    return False
```

## Notes that earn their keep

- **Replace, not extend, semantics.** The env var **replaces** the default list, not extends it. Document this in `.env.template` next to the example so an operator who uncomments a partial example doesn't silently weaken the policy. The `.env.template` example must list the full default — not a subset.
- **Normalise on read, not on write.** Lower-case + strip on the parse side, not at every call site. The hot path stays a clean `if x in settings.X`.
- **`filter(None, ...)` drops empty strings** from trailing commas / accidental blank entries. Cheaper than re-validating each entry.
- **`frozenset` (not `set`)** so accidental `.add()` / `.discard()` from request handlers raises immediately instead of mutating shared global state.
- **Extensionless guard.** When checking by extension, gate on `'.' in filename` first — `'Makefile'.rsplit('.', 1)[-1]` returns `'Makefile'`, which can collide with denylist entries by sheer coincidence.

## When NOT to use

Small-cardinality static lists that never need per-deployment override (use a literal `frozenset(...)` constant), or lists that need per-tenant override (use a model + cached lookup, not a settings constant).
