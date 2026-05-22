---
name: django
description: Apply cross-project Django backend conventions — BaseModel abstractions, DRF viewsets, ORM optimisation (select_related / prefetch_related), multi-tenancy boundaries, generic-FK patterns, permission probes, and translation workflow — before hitting templates.
license: MIT
metadata:
  author: mind-vault
  version: '5.0'
  replaces:
    - django-architecture
    - django-async-websocket
    - django-celery
    - django-multi-tenant
    - django-celery-multitenant
    - django-async-websocket-multitenant
---

# django

Core Django backend patterns for project organisation, model abstractions, DRF conventions, ORM optimisation, middleware, and testing. Applies identically across single-tenant and multi-tenant projects; specialised concerns (Channels, Celery, multi-tenancy, i18n) live in `references/`.

**Pairs with:** [django-frontend](../django-frontend/SKILL.md) for HTMX / Alpine / Bulma template patterns. Load both on full-stack feature work (e.g. a view that returns an HTMX partial on `HX-Request`).

## When to use

**TRIGGER when:** editing a Django project (`manage.py`, `models.py`, `views.py`, `serializers.py`, `admin.py`, `migrations/`); adding a DRF endpoint, viewset, or permission; touching BaseModel / mixins / middleware; running `makemessages`; debugging N+1 or query-count issues.

**SKIP for:** template-only work (use [django-frontend](../django-frontend/SKILL.md)); pure-frontend JS; non-Django Python projects (FastAPI / Flask / Starlette have different idioms); DevOps without code (use [deployment](../deployment/SKILL.md)).

## Pattern

### Project structure

Infrastructure at repo root, Django code under `web/`:

```text
git_repo_root/
├── docker-compose.yml         # Infrastructure
├── Dockerfile
├── nginx/
├── docs/
├── tools/
└── web/                       # ← All Django code here
    ├── manage.py
    ├── requirements.txt
    ├── .env.example
    ├── project/               # settings.py, urls.py, asgi.py
    ├── core/                  # BaseModel, mixins, permissions, middleware
    ├── auth/
    ├── api/
    └── [feature]/
```

**Why `web/`:** clean separation of infra vs. app code. Docker's `web` service mounts `web/` to `/app` in the container, keeping Django self-contained and infra isolated from the Python path.

### Type hints and docstrings

Mandatory on all function signatures and classes. Explicit arg/return types (`def process(data: dict) -> bool:`) and a descriptive docstring per class / function / method.

### BaseModel abstraction

Reduce duplication with an abstract base:

```python
# core/models.py
from django.db import models, transaction

class BaseModel(models.Model):
    """Abstract base with timestamps and soft-delete support."""
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_deleted = models.BooleanField(default=False)

    class Meta:
        abstract = True
        indexes = [
            models.Index(fields=["created_at"]),
            models.Index(fields=["updated_at"]),
        ]

    def soft_delete(self):
        """Atomic soft-delete with row lock to prevent double-delete races."""
        with transaction.atomic():
            obj = self.__class__.objects.select_for_update().get(pk=self.pk)
            if obj.is_deleted:
                return False
            obj.is_deleted = True
            obj.save(update_fields=["is_deleted", "updated_at"])
            return True
```

**PK convention:** `id = models.BigAutoField(primary_key=True)` on concrete models — future-proof vs. 32-bit integer overflow; Django 3.2+ defaults to this for new projects but legacy apps often still use `AutoField`.

✅ DO: `Article.objects.filter(is_deleted=False)` — explicit filter on every query surface.
❌ DON'T: `Article.objects.all()` — will include soft-deleted rows and leak them to the UI.

**When NOT to soft-delete:** audit logs (never delete), temporary/cache data (hard delete), FK-integrity-critical records (soft deletes break cascades and `on_delete=PROTECT`).

### Blankable CharField — `null=True` over `default=""`

**The rule**: any `CharField` / `TextField` declared with `blank=True` should also declare `null=True`, **not** `default=""`. Two reasons, both load-bearing:

1. **No empty-string sentinel ambiguity.** With `default=""`, an unset row stores `""`, and every read site has to decide whether to treat `""` and `None` as the same case. With `null=True` the unset case is unambiguously `NULL` — `is None` is the one truthful check. (Django's official advice "avoid `null=True` on string fields" was good in 2007 when callers freely passed `None` to `len()`; it's outweighed today by the readability cost of the empty-string sentinel.)
2. **Additive migrations need no default value.** A new `CharField(blank=True, null=True)` column can be added with `AddField` and zero existing-row mutation — `NULL` is a valid value for every existing row. With `blank=True, default=""`, the migration either ships `default=""` (extra column-level overhead Django carries forward in the DDL) or asks the operator interactively for a one-off default. Neither matters at small scale; both bite in big-table migrations or in CI / cron environments where interactive prompts hang the deploy.

```python
# ✅ Recommended — symmetric blank/null, no default required.
embed_failure_reason = models.CharField(
    max_length=64, blank=True, null=True,
    verbose_name=_("Embed failure reason"),
)

# ❌ Avoid — empty-string sentinel + default-value baggage.
embed_failure_reason = models.CharField(
    max_length=64, blank=True, default="",
    verbose_name=_("Embed failure reason"),
)
```

**Exception — when `default=""` IS the right call**: the field is populated synchronously by `save()` or a signal *before* the row is ever read, so the brief unset window is never observed by application code. The `Attachment.mime_type` example below is one such case (`save()` derives the MIME from the upload, no reader sees `NULL`). For everything else — operator-set fields, optional admin metadata, descriptive notes, last-error messages, soft-delete reasons — go `null=True`.

**On serializer / API surface**: DRF's `CharField` defaults to `allow_null=False`. If the model is `null=True`, the corresponding serializer field needs `allow_null=True` *and* `required=False` to honour the model contract. Forgetting either means the API rejects valid `None` payloads with a 400 — silently breaking what the model permits.

```python
# Serializer for a model with embed_failure_reason: CharField(blank=True, null=True)
class IndexableSerializer(serializers.ModelSerializer):
    class Meta:
        model = Article
        fields = ["id", "title", "embed_failure_reason"]
        extra_kwargs = {
            "embed_failure_reason": {"allow_null": True, "required": False},
        }
```

The user articulated the convention during code review: *"I'm always making fields nullable if blankable to avoid forcing empty string value, also if it's not nullable, field requires default value for additive migration."* That sentence is the rule.

### Multi-tenancy vs. ForeignKey boundaries

For projects using schema-based isolation (`django-tenants`):

- **Tenant-schema tables** (Articles, Events, Scopes): **no** `org`/`tenant` FK — the PostgreSQL schema itself is the isolation. Tenant-local BaseModel without the org column.
- **Public-schema tables** (Users, Billing, Subscriptions, Organization directory): live in `public`. Use an `OwnedModel` mixin with the `org` FK here.

Getting this wrong (FK on tenant-schema tables) duplicates the schema isolation at the row level, wastes indexes, and turns every tenant-scoped query into a needless `WHERE org_id = ?` on top of the already-scoped schema.

**Validate-and-prune helpers walking BOTH kinds**: when a single helper iterates a heterogeneous list of FK kinds (some tenant-schema, some public-schema-with-`org_id`) and does existence checks like `Model.objects.filter(id__in=session_ids)`, the public-schema queries MUST add an explicit `.filter(org_id=org_id)` — schema routing protects only the tenant-schema queries, and a session can carry stale ids from a foreign tenant. See [`references/TENANT_SCOPED_FK_VALIDATION.md`](references/TENANT_SCOPED_FK_VALIDATION.md) for the full pattern (per-kind `tenant_scope_required` flag) and the diagnostic recipe.

### Generic foreign keys and polymorphism

When a model references heterogeneous types (AI context item pointing to Article / Event / Property), use `contenttypes.GenericForeignKey` via a reusable mixin:

```python
# core/mixins.py
from django.contrib.contenttypes.fields import GenericForeignKey
from django.contrib.contenttypes.models import ContentType
from django.db import models

class GenericFKMixin(models.Model):
    content_type = models.ForeignKey(ContentType, on_delete=models.CASCADE)
    object_id = models.PositiveIntegerField()
    content_object = GenericForeignKey("content_type", "object_id")

    class Meta:
        abstract = True
        indexes = [models.Index(fields=["content_type", "object_id"])]
```

**Critical caveat — Django ticket #30214:** `Meta.indexes` declared on an abstract parent are **NOT** propagated when a concrete subclass defines its own `Meta` (which it almost always does). Consumers must manually re-declare:

```python
class ConversationContextItem(GenericFKMixin, models.Model):
    conversation = models.ForeignKey("Conversation", on_delete=models.CASCADE)

    class Meta:
        indexes = [
            models.Index(fields=["content_type", "object_id"]),  # MUST mirror the mixin
            models.Index(fields=["conversation"]),
        ]
```

**N+1 prevention:** always `prefetch_related("content_object")` when iterating — Django otherwise fires one query per row to resolve the generic reference:

```python
items = (
    ConversationContextItem.objects
    .filter(conversation_id=conv.id)
    .select_related("content_type")
    .prefetch_related("content_object")
)
```

### FileField MIME capture + registry drift guards

**Fires when** an app handles file uploads and categorises content by MIME type. Two failure modes recur: (1) `FieldFile.content_type` returns empty because `FieldFile.__getattr__` doesn't delegate `content_type` from the underlying `UploadedFile` — the obvious code falls through to extension-based guessing silently; (2) "one true list" registries drift between consumer modules as formats get added to the canonical set but not to the parallel `{mime → format_hint}` dict elsewhere.

Fixes: capture browser-supplied MIME at upload into a dedicated DB column (`mime_type`) by reading `self.file.file.content_type` (NOT `self.file.content_type`), strip `;codecs=…`/`;charset=…` suffixes, prefer the column on read; pair the canonical set + consumer dict with a module-scope `assert` that fires at import time so missing entries crash `python manage.py check` rather than the first user-facing upload. Mechanics — full save() override, backfill migration with `RunPython.noop` reverse, drift-guard assert example — are in [`references/FILEFIELD_MIME_CAPTURE.md`](references/FILEFIELD_MIME_CAPTURE.md). Read that reference when this section fires.

### DRF — base viewset and permissions

```python
# core/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

class BaseViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return super().get_queryset()  # subclasses add select_related / prefetch_related
```

```python
# core/permissions.py
from rest_framework.permissions import BasePermission

class IsResourceOwner(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user
```

### Permission DRY-ness via probe pattern

**Never duplicate authorisation logic** between DRF `BasePermission` classes and plain Django views / forms / template tags. The DRF permission class is the single source of truth.

When checking permission in a non-DRF context, build a synthetic DRF request and feed it to the same permission class:

```python
# core/permissions.py — helper
def build_drf_request(django_request, data=None):
    from rest_framework.request import Request
    drf_req = Request(django_request)
    if data is not None:
        drf_req._data = data
    return drf_req

# usage in a Django FBV/CBV or template tag
drf_request = build_drf_request(request, data=request.POST)
has_perm = CanManageArticles().has_permission(drf_request, None)
```

✅ DO: Reuse the DRF permission class via a probe for consistent authz across endpoints.
❌ DON'T: Reimplement "is this user allowed?" in a template tag or form — divergence from DRF is a permission bypass waiting to happen.

### Reusable view mixins

```python
# core/mixins.py

class SoftDeleteMixin:
    """Use with ModelViewSet — DELETE becomes soft-delete."""
    def perform_destroy(self, instance):
        instance.soft_delete()

class AuditMixin:
    """Stamps created_by / updated_by on writes."""
    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    def perform_update(self, serializer):
        serializer.save(updated_by=self.request.user)
```

Stack them on viewsets:

```python
class ArticleViewSet(AuditMixin, SoftDeleteMixin, BaseViewSet):
    queryset = Article.objects.filter(is_deleted=False)
    serializer_class = ArticleSerializer
```

HTMX-aware template selection and response-type switching lives in [django-frontend](../django-frontend/SKILL.md).

### Cross-entity session-filter state — fan-out invalidation on shared-key change

**Fires when** user-facing filter state spans multiple list/detail surfaces (articles ↔ events ↔ FAQs ↔ dashboard) and per-entity state is derived from a cross-entity field. Common session-key shape: `cross_filters_<org_id>` for fields that travel (`scope`, `property`, `category`) + `kb_<entity>_filters_<org_id>` for per-entity fields (`q`, `tags`).

The recurring trap: when the cross-entity field changes value, derived per-entity state goes stale on **every** sibling entry, not just the current request's. The canonical example: tags are FK-scoped to Scope; user picks `scope=A, tag=X` on `/articles/`, cross-links to `/events/`, changes `scope=B`. Entity-local tag-clearing fixes events but leaves `kb_articles_filters_<org>.tags=['X']` referencing a scope-A tag. Articles' picker renders for scope B (no escape) yet session still applies X → 0 results.

Fix: iterate session keys with the stable `kb_*_filters_<org_id>` namespace prefix and clear the derived field from every matching entry except the current. Two safety gates: `old_scope_value` truthy gate (excludes empty-to-something first-submit case from "change"); `isinstance(key, str)` defence inside the helper. Mechanics — full `get_effective_filters` shape, `_clear_tags_from_other_entity_sessions` helper implementation, both safety gates with rationale, generalisation rule, canonical test contract — are in [`references/CROSS_ENTITY_SESSION_FILTER.md`](references/CROSS_ENTITY_SESSION_FILTER.md). Read that reference when this section fires.

### Middleware

Request-context middleware pattern (classic class-based style):

```python
# core/middleware.py
from django.utils import timezone

class RequestContextMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.user_context = {
            "user_id": request.user.id if request.user.is_authenticated else None,
            "timestamp": timezone.now(),
        }
        return self.get_response(request)
```

### ASGI configuration

HTTP-only app — the one-liner suffices:

```python
# project/asgi.py
import os
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "project.settings")
application = get_asgi_application()
```

For WebSocket/Channels routing (protocol router, auth middleware stack, consumers), see [references/ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md).

### Settings

Environment-driven configuration:

```python
# project/settings.py
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv("SECRET_KEY", "dev-key-change-in-production")
DEBUG = os.getenv("DEBUG", "false").lower() == "true"
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("DB_NAME", "project_db"),
        "USER": os.getenv("DB_USER", "postgres"),
        "PASSWORD": os.getenv("DB_PASSWORD", ""),
        "HOST": os.getenv("DB_HOST", "localhost"),
        "PORT": os.getenv("DB_PORT", "5432"),
        "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", "600")),
    }
}
```

For URL-encoded `DATABASE_URL` parsing and typed casting, use `django-environ` or `python-decouple` — see [references/DEVELOPMENT_WORKFLOW.md](references/DEVELOPMENT_WORKFLOW.md).

### Env-driven allowlists / denylists as `frozenset`

**Fires when** a list (blocked MIMEs, blocked extensions, IP allowlists, feature flags) needs all three of: per-deployment override without code change, O(1) hot-path membership lookup, and immutability against accidental request-handler mutation.

The shape: parse a comma-separated env var into a `frozenset` at settings-import time, with a sane default literal embedded in code. Five details earn their keep — replace-not-extend semantics (env var REPLACES the default; `.env.template` must list the full default), normalise on parse not call-site, `filter(None, ...)` to drop empty entries from trailing commas, `frozenset` not `set` so handler `.add()` raises, extensionless guard (`'.' in filename` before `rsplit('.', 1)[-1]` to avoid `'Makefile'`-style collisions). Mechanics — full settings.py block with the BLOCKED_UPLOAD_MIMES + EXTENSIONS shape, hot-path `is_blocked` helper, all five earn-their-keep notes, when-NOT-to-use guidance for small-cardinality / per-tenant cases — are in [`references/ENV_DRIVEN_ALLOWLISTS.md`](references/ENV_DRIVEN_ALLOWLISTS.md). Read that reference when this section fires.

### Docker-generated migrations — ownership bypass

`docker compose exec web python manage.py makemigrations` creates files owned by `root` (the container user), blocking host-side edits and AI-agent rewrites. Chown from inside the container using the host's UID/GID:

```bash
CURRENT_UID=$(id -u) CURRENT_GID=$(id -g) \
  docker compose exec web chown -R $CURRENT_UID:$CURRENT_GID /app/your_app/migrations
```

Wrap in a Makefile target so it's one command:

```makefile
makemigrations:
	docker compose exec web python manage.py makemigrations
	docker compose exec web chown -R $$(id -u):$$(id -g) /app
```

### `ManifestStaticFilesStorage` — `collectstatic` is not enough, restart the app server

**Fires when** a Django staging / production deployment uses `ManifestStaticFilesStorage` (DEBUG=False) and `collectstatic` runs as part of deploy. The trapdoor: `staticfiles.json` (the hash→URL mapping that powers `{% static %}`) is read once at app-server process startup and **cached in-memory for the worker's lifetime**. After `collectstatic` writes the new hashed file + new manifest entry, the running server's `{% static %}` still resolves to the OLD hash. User refreshes — including hard-refresh — and sees no change because the rendered HTML references the old URL, which still exists on disk and serves old content.

The contract: every static-file change requires `make static && make restart-web`. Same shape as env-var change-then-recreate (`docker compose restart` ≠ env reload; need `up -d --force-recreate`) — "the disk changed but the process is still on the old view." Mechanics — full settings.py STORAGES backend toggle for DEBUG vs not, ❌/✅ Makefile target shapes, four-step symptom-during-debug diagnostic, applicability scope (any post-processed asset; staging/prod-only) — are in [`references/MANIFEST_STATIC_FILES_STORAGE.md`](references/MANIFEST_STATIC_FILES_STORAGE.md). Read that reference when this section fires.

### ORM optimisation — N+1 prevention

```python
# ❌ N+1 storm — one query per article to fetch author
articles = Article.objects.all()
for article in articles:
    print(article.author.name)

# ✅ single join
articles = Article.objects.select_related("author")

# ✅ prefetch for reverse FK / M2M
articles = Article.objects.prefetch_related("comments")
```

Batch update instead of loop-save:

```python
# ❌ one UPDATE per row
for article in articles:
    article.status = "published"
    article.save()

# ✅ one UPDATE total
Article.objects.filter(status="draft").update(status="published")
```

**When NOT to optimise:** small result sets (\<10 rows), related objects not accessed in the code path, measured impact negligible. Premature `select_related` over-fetches columns and can make things worse.

**Assert query count in tests:**

```python
from django.test import TestCase

class ArticleTest(TestCase):
    def test_list_query_count(self):
        with self.assertNumQueries(2):
            articles = Article.objects.prefetch_related("tags")
            for article in articles:
                list(article.tags.all())
```

### Formsets with `UniqueConstraint`

When a model has `UniqueConstraint(fields=["author", "preset"])`, a naive formset submission with duplicate rows raises `IntegrityError` — which bubbles to the user as a 500.

**Belt-and-braces pattern:**

1. **Formset-level `clean()`** — subclass `BaseModelFormSet`, collect constrained fields from each form's `cleaned_data` (skip deleted), raise `ValidationError` on duplicates with a clear message.
2. **View-level `try/except IntegrityError`** — catches races the clean pass missed, adds a user-facing error instead of 500.
3. **Shared table UI** — JS contract (TOTAL_FORMS, template cloning, reindexing on delete) lives in [django-frontend](../django-frontend/SKILL.md).

### String building with optional parts

Append B to A, or use only B when A is empty:

```python
body = (base_value or "").strip()
if optional_part:
    line = "Label: " + optional_part
    body = "\n".join(filter(None, [body, line]))
```

- Non-empty base: both kept, joined by newline.
- Empty base: `filter(None, [...])` drops the empty string; result is just the new part.
- Avoids the ternary / if-else ceremony for append-vs-replace.

### Date / time / timezone

**Centralise timezone handling** in one module (convention: `core/timezone_utils.py`): `get_timezone_object`, `normalize_to_user_tz`, `validate_timezone_string`, `get_available_timezone_names`. All call sites (DRF serializers, consumers, template tags, auth forms) go through it so zoneinfo/pytz fallback and exception handling live in one place.

**Sensible-date validation:** for forms/APIs accepting a `date`, use shared min/max constants (from env) and one `validate_sensible_date(value)` raising `ValidationError` on out-of-range. HTML5 widget attrs (`min`, `max`) come from the same constants.

**All-day events in iCal export:** date-only events use the user's daily reminder time (e.g. 09:00) so "1 day before" resolves to 09:00 on the previous day. Compute the absolute trigger in a shared helper taking `(event_date, event_time, preset, user_tz, daily_reminder_time)` — both the iCal exporter and the in-app notification scheduler go through it.

### Translation workflow

**Never edit `.po` files directly** — they are clobbered on the next `makemessages` run.

Canonical flow:

1. Add user-facing `msgid` entries to the project's translation-map script (convention: `tools/translation_maps/<lang>.py`).
2. `make translate-extract` — runs `makemessages` + Docker-chown + fuzzy-wipe.
3. `make translate-fill` — applies map values into `.po`.
4. `make translate-audit` — catches carryovers, placeholder parity mismatches, fuzzy residue.
5. `make translate-compile` — produces `.mo` files.

Key gotcha — **Gettext fuzzy matching**: `msgmerge` appends `#, fuzzy` markers to guessed translations. If the pipeline strips the flag without wiping the msgstr, bad guesses burn into the `.mo` files. The extract target must invoke `msgattrib --clear-fuzzy --empty` to reset all fuzzy entries to empty msgstr, forcing explicit re-translation.

Full workflow detail in [references/I18N.md](references/I18N.md). Hard rules across projects in [`RULE_i18n-workflow`](references/I18N_WORKFLOW.md).

### Testing UI strings under locale

When test assertions inspect response content for string presence (error messages, labels, alerts), force English explicitly — don't rely on host locale:

```python
from django.test import override_settings
from django.utils.translation import activate

@override_settings(LANGUAGE_CODE="en")
def test_error_message(self):
    activate("en")
    response = self.client.post(url, bad_data)
    self.assertIn("Expected English string", response.content.decode())
```

Without this, tests pass locally but fail in CI when the container locale differs, or when translations are incomplete. See [references/TESTING.md](references/TESTING.md).

### `verbose_name` discipline for AI-driven CRUD models

When a model is exposed to an AI agent (via DRF + a tool harness — see `claude-api` skill / Anthropic-style tool use), the `verbose_name` of every field becomes part of the model's surface vocabulary visible to the agent through:

- Form labels rendered into HTML the agent reads.
- Django admin column headers.
- `serializer.is_valid()` error messages echoed back into the agent's context.
- Translation `.po` catalogues if the agent is multilingual.

If `verbose_name` text drifts from the field name, the agent sees one vocabulary in labels and another in JSON keys. Result: hallucinated field names in tool-call payloads. Common shape:

```python
# DRIFT-PRONE — model has `contents` field but the human-friendly label says "Body":
contents = models.TextField(verbose_name=_("Body"))
```

The agent reads "Body" in form labels + admin + error text and may emit `{"body": "..."}` in the next tool call. The DRF serializer's `Meta.fields = ['contents', ...]` then 400s because `body` isn't a registered key. Worse, the agent's failure-recovery loop may keep guessing variants (`text`, `description`, `body_text`) without ever finding `contents`.

**The rule**: for any model that the AI can write to via tool calls, `verbose_name` text exact-matches the field name (capitalisation aside).

```python
# SAFE — label, JSON key, and field name align:
contents = models.TextField(verbose_name=_("Contents"))
notes = models.TextField(verbose_name=_("Notes"), blank=True)
```

Translations keep matching: lt → "Turinys" / "Pastabos", ru → "Содержание" / "Заметки", etc. — the per-language label tracks the canonical English term.

**Exceptions that don't apply**: fields the AI never reads or writes (internal-only configuration, hidden audit fields, opaque foreign keys with `_id` suffix). For those, label freely.

**Detection during code review**: grep the model file — for each `verbose_name=_("X")`, verify `X.lower().replace(' ', '_')` is the field name (modulo language). Mismatches are review fodder.

### LLM output post-processing — strip-and-trust pattern

When an LLM's system prompt asks for verbatim output (transcribe this audio, translate this string, summarise to one line), the model still occasionally hallucinates a preamble — `Here is the transcription:`, `The translation is:`, `Sure, here you go.` — even when the prompt explicitly forbids it. The prompt is the first line of defence; a regex post-strip on the response is the second.

```python
class AIService:

    _TRANSCRIBE_PREAMBLE_RE = re.compile(
        # Order matters — longest alternative first so ``Transcription`` is
        # matched fully instead of stopping at ``Transcript``.
        r'^(Here is the transcription|The transcription is|I have transcribed|Transcription|Transcript)[:\s]*',
        re.IGNORECASE,
    )

    def _strip_transcript_preamble(self, text: str) -> str:
        """Drop common LLM transcript preambles + outer matched quotes.

        Defence-in-depth even when the system prompt forbids preambles —
        models occasionally hallucinate "Here is the transcription:" anyway.
        Idempotent and cheap enough to run on every transcription return.
        """
        if not text:
            return ""
        cleaned = self._TRANSCRIBE_PREAMBLE_RE.sub('', text).strip()
        if len(cleaned) >= 2 and cleaned[0] == cleaned[-1] and cleaned[0] in ('"', "'"):
            cleaned = cleaned[1:-1].strip()
        return cleaned
```

Three trapdoors worth naming explicitly:

1. **Regex alternation order — longest alternative first.** Python's `re` is leftmost-first, not longest-match: `(Transcript|Transcription)` matches `Transcript` from `Transcription:` and leaves `ion:` behind. Always order the alternation longest-first; a single unit test that asserts a known long-preamble shape strips entirely catches reorder regressions.
2. **Idempotent + cheap.** The function should be safe to call on already-clean output (no preamble = pass-through) and should not allocate per call beyond the regex match. Compile the regex once at class scope.
3. **Outer matched quotes.** Models often wrap the verbatim payload in quotes that weren't in the source. Strip them after the preamble strip — only when both ends match (`"foo"` → `foo`, `"foo'` stays `"foo'`).

Pair this pattern with a per-message resource cap when the LLM accepts attachments — the prompt asks for one transcript, but a buggy upload UI could submit twenty audio clips and the model will dutifully transcribe all of them, blowing the token budget. Enforce the cap at the WebSocket consumer / view layer (where `request.user` and the org are visible), not deeper — input validation belongs at the boundary. See [references/ASYNC_WEBSOCKET.md § Per-Message Resource Caps](references/ASYNC_WEBSOCKET.md#per-message-resource-caps) for the consumer-side pattern.

When NOT to use: free-form generation tasks (chat replies, brainstorming) where the preamble IS legitimate output. Strip-and-trust is for verbatim-output tasks specifically.

## When NOT to use these patterns

- **Non-Django Python projects** (FastAPI, Flask, Starlette) — different idioms; the BaseModel / DRF / ORM patterns map poorly.
- **Small single-model project** — BaseModel + soft-delete is overhead; a plain `models.Model` is fine.
- **Microservices / stateless APIs** — audit trails and soft-delete may not apply. Reconsider which patterns you actually need per service.
- **Fundamentally async app** — if the app is mostly WebSocket/Channels-driven with only a handful of HTTP endpoints, start from [references/ASYNC_WEBSOCKET.md](references/ASYNC_WEBSOCKET.md) and treat the ViewSet pattern as secondary.

## References

- [Cross-entity session-filter](references/CROSS_ENTITY_SESSION_FILTER.md) — fan-out invalidation when a cross-entity field's change leaves derived per-entity state stale across sibling session entries; full `_clear_tags_from_other_entity_sessions` helper + two safety gates
- [FileField MIME capture](references/FILEFIELD_MIME_CAPTURE.md) — `FieldFile.content_type` is empty by design; capture browser MIME at upload + import-time `assert` that locks the canonical set ↔ consumer dict against drift
- [Env-driven allowlists / denylists as `frozenset`](references/ENV_DRIVEN_ALLOWLISTS.md) — three-property pattern (env override + O(1) hot-path + immutable global), full BLOCKED_UPLOAD_MIMES + EXTENSIONS shape, replace-not-extend env semantics
- [`ManifestStaticFilesStorage` restart contract](references/MANIFEST_STATIC_FILES_STORAGE.md) — `collectstatic` writes the new file + manifest, but the running app server's `{% static %}` cache holds the OLD hash; require `make static && make restart-web` for changes to land for users
- [Multi-Tenant Architecture](references/MULTI_TENANT.md) — schema-per-tenant isolation (django-tenants)
- [Async WebSocket](references/ASYNC_WEBSOCKET.md) — Channels consumers and routing
- [Celery Background Tasks](references/CELERY.md) — async job processing
- [Logging Patterns](references/LOGGING.md) — structured logging and audit trails
- [Internationalization](references/I18N.md) — translation workflow, fuzzy-wipe, locale testing
- [Testing Patterns](references/TESTING.md) — query-count asserts, locale enforcement, isolation
- [Development Workflow](references/DEVELOPMENT_WORKFLOW.md) — env config, Docker dev-loop
- [Multi-Tenant + Async](references/MULTI_TENANT_ASYNC.md)
- [Multi-Tenant + Celery](references/MULTI_TENANT_CELERY.md)
- [django-frontend](../django-frontend/SKILL.md) — HTMX / Alpine / Bulma frontend pairing
- [deployment](../deployment/SKILL.md) — production deployment patterns
- [surgical-tdd](../surgical-tdd/SKILL.md) — focused test execution
- [`RULE_i18n-workflow`](references/I18N_WORKFLOW.md) — hard rules for translations; FORCE_SYNC_MSGIDS overwrite-existing-msgstr gotcha; don't-translate-dev-notes; blocktrans `%(var)s` placeholder format
- [Form-invalid status](references/FORM_INVALID_STATUS.md) — Django's default `form_invalid` returns 200 + form-with-errors, NOT 422; status-only gating closes HTMX modals on validation failure; fix via `HTMXFormStatusMixin` or `HX-Trigger` header gate
- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimisation](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
