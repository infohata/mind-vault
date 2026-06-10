# Structured error detection — classify on the error body, not the message string

When a resilience path must catch **one precise upstream failure** (and let every other
failure propagate), classify the exception on its **structured body**, never on the rendered
message string. Client libraries for HTTP/JSON services (Elasticsearch, S3, payment APIs)
expose the server's error document on the exception (`err.body` / `err.response` /
`err.error`); the human-readable `str(err)` is a lossy rendering of it that the library, the
server version, or a proxy can reword at any time.

## The shape

A versioned-resource migration leaves a read path that can hit either the new or the legacy
resource. Queries against the legacy one fail with a specific server error (e.g. a vector
dimension mismatch); the resilient loop should **skip that variant and continue** — but a
timeout, an auth failure, or an unrelated 400 must still surface as the hard error it is.

```python
def _is_dim_mismatch(err: BadRequestError) -> bool:
    """Return True only for the knn dimension-mismatch shape; everything else propagates."""
    root_causes = (err.body or {}).get("error", {}).get("root_cause", [])
    return any(
        rc.get("type") == "illegal_argument_exception"
        and "different number of dimensions" in rc.get("reason", "")
        for rc in root_causes
    )

try:
    hits = _search_variant(index)
except BadRequestError as err:
    if not _is_dim_mismatch(err):
        raise                       # unrelated 400 → still a hard failure
    logger.warning("dim-mismatch on %s — skipping variant", index)
    continue
```

Two narrowing layers, both required: the **exception class** (only `BadRequestError`, so
timeouts / connection errors / 5xx never enter the handler) and the **structured-body
predicate** (only the one root-cause shape, so other 400s re-raise). A handler that matches
`"dimensions" in str(err)` passes today and silently widens or breaks on the next client
bump — and `str(err)` matching can also false-positive on an unrelated error whose message
merely *mentions* the word.

## The test contract — synthetic exceptions need a real body

The unit test must construct the exception **with the structured body populated**, so it
exercises the predicate's real path:

```python
err = BadRequestError(
    message="...",
    meta=fake_meta,
    body={"error": {"type": "search_phase_execution_exception", "root_cause": [{
        "type": "illegal_argument_exception",
        "reason": "...different number of dimensions [3072] than the document vectors [1536]",
    }]}},
)
```

A test that builds the exception from a bare message string only proves the handler matches
a string repr — the structured path ships unexercised, and the first production error with a
differently-shaped body slips through (or over-matches). Pair the positive case with the
negative ones: an `illegal_argument_exception` with a different `reason` must propagate, and
a non-`BadRequestError` must never reach the predicate.

## When this fires

- Any `except <ClientError>` that inspects the error to decide skip-vs-raise.
- Migration/fallback read paths probing multiple resource versions.
- Retry logic that retries only specific server verdicts (throttle vs hard failure).

Pairs with [`../../django/references/RESOURCE_LIFECYCLE_DROP_VS_ENSURE.md`](../../django/references/RESOURCE_LIFECYCLE_DROP_VS_ENSURE.md) —
the same migration that needs the resilient read path also needs its legacy-drop to stay
dropped.
