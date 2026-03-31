# Curator Post-Commit Review Passes

When invoked to review a diff, the Curator must execute these sequential passes:

### PASS 1: The Context & Rule Sweep
- Identify the exact scope of the changes via `git diff HEAD`.
- Cross-reference the changes against project rules in `AGENTS.md`.
- **Hardcoded Local Paths**: Scan for any config files, shell aliases, or symlinks that hardcode developer machine paths (e.g. `/home/user/...` or `/Users/...`). Force relative paths.
- **Testing Integrity**: If a feature or logic block was changed, does a test exist? Did they add a test? Do the tests actually cover edge cases or just happy-paths?

### PASS 2: The Security & Isolation Pass (Critical)
- **Tenant Leakage**: Are any queries in a multi-tenant environment bypassing schema isolation by illegally searching or assigning an `org` or `tenant` Foreign Key on tenant-localized models?
- **Async Tenant Context Loss (Channels)**: Are model saves, creations, or cache operations executing inside `database_sync_to_async`? The worker thread DOES NOT inherit the WebSocket's schema context. You MUST demand the operation be wrapped in `with tenant_context(tenant):`, explicitly passing the tenant reference into the thread.
- **Authorization**: Are standard views or form templates duplicating permission logic? Force them to use **DRF Permission Probes** (`drf_has_permission_in_tenant`) against a single-source-of-truth `BasePermission` class.
- **Integrations and Flat Payloads (Strict HMAC Enforcement)**: Are Webhooks or iframe payloads blindly trusted? Force them to use the **HMAC Signature (`X-User-Context-Signature`)** pattern. If the integration supports a "flat payload" (where config keys live at the root instead of inside a nested wrapper), you MUST verify that the *entire raw payload* triggers HMAC verification. Never selectively bypass signature checks for generic keys, as all ingested data must be authenticated before reaching AI or DB layers.
- **Third-Party API Spec Safety**: Are internal Django Object IDs or proprietary metadata keys being blindly injected into strict external SDK payloads (like an OpenAI Chat dictionary)? They must be stripped out before dispatch to prevent vendor schema validation failures.
- **Anonymous Ownership Verification**: Are public/anonymous entity deletions or modifications relying solely on knowing an unguessable UUID? They MUST verify the session key, request token, or cookie of the creator against the record; otherwise, any user (or bot) with the URL can mutate or delete anonymous records.
- **Data Mutation**: Are GET requests modifying database state? (They must be POST/HTMX).

### PASS 3: The Architecture & DRY Pass
- **Eager Translation Migration Drift**: Are developers wrapping translation strings (`_("...")`) inside `format_html()` at the class level (like inside a Django Model field `help_text` or `verbose_name`)? This eagerly evaluates the translation into a string using the server's boot-time language, causing continuous phantom `makemigrations` diffs. You MUST demand `format_lazy()` from `django.utils.text` instead so the promise defers until template render.
- **Duplication & Parity**: Is the author copy-pasting code? Demand extraction. Is a bugfix applied asymmetrically? If fixing logic in `openModal`, ensure `confirmAction` and `openAttachmentPreview` also got it. Scan for sister-functions.
- **Template Hierarchy Parity (The Minimal Clone Flaw)**: If injecting critical global context variables, tracking scripts, or theme bypass variables (`window.__FOO__`) into the root `base.html` template, you MUST aggressively check for inherited or sibling base templates (e.g. `base_minimal.html`, `base_embed.html`, `base_auth.html`). Failing to duplicate core Javascript injections into alternative layouts silently corrupts cross-origin functionality and embeds.
- **Deduplication of Hand-Rolled Parsers**: Are developers manually using `.split(';')` to parse `document.cookie` or manual string manipulation to parse URLs inline within a script? Demand extraction and utilization of existing utility parsing functions. Never allow duplicated raw DOM/Cookie extraction logic.
- **Dictionary Key Collisions**: Are massive Python dictionaries defining duplicate keys? Python silently swallows earlier entries, burying dead configuration overrides. Demand explicitly unique mapping keys.
- **Eviction Boundary Blindness**: Are LRU trims or quota-limit deletions tucked inside an `if created:` object initialization block? If quotas can be lowered natively via settings, the eviction logic MUST run unconditionally on every database read or touch, not just initial creation. Furthermore, confirm zero-limit edge cases (`max_items <= 0`) cleanly purge all existing data rather than silently bypassing the trim loop.
- **Fat Models / Thin Views**: Is heavy business logic cluttering the View or API endpoint? Demand it be moved onto the Model or a dedicated service tier.
- **Date/Time**: Are they using naive `datetime.now()` instead of timezone-aware contexts? 

### PASS 4: The Performance & DB Integrity Pass
- **Data Migration Backfills (Drop Protection)**: If a PR modifies a model schema to abstract, replace, or drop a field (e.g. moving a legacy FK to a polymorphic mapping table), you MUST verify that a `RunPython` data migration exists to bulk backfill the existing production rows before the legacy column evaporates.
- **GenericForeignKey N+1 Blindness**: Are loops or templates triggering N+1 queries by accessing `.content_object` attributes on a `GenericForeignKey` array? Doing a standard `.prefetch_related('content_object')` silently fails or performs poorly for complex multi-model relations. Force them to manually group items by `ContentType` and use `.in_bulk()` or explicitly documented, targeted fetches.
- **N+1 Queries**: Are loops hitting `.all()` without `select_related()` or `prefetch_related()`? 
- **Bulk Operations**: Are iterations calling `.save()` continuously instead of `bulk_create` or `bulk_update`?
- **Celery Integrity**: Does this background task hold locks for too long? Is it idempotent?
- **Dead Data Field Phantoms**: If a schema change or squashed migration removes a field (e.g. `org` or `tenant`), you MUST sweep the corresponding ViewSet's `filterset_fields`, `search_fields`, `ordering_fields`, and `select_related`/`prefetch_related` lists to ensure the dead field is purged. Failing to do so triggers a catastrophic `FieldError` or `TypeError: 'Meta.fields' must not contain non-model field names`.

### PASS 5: The Frontend & UX Pass (HTMX + standard)
- **Double Submits**: Does a form lack the **Global Single-Submit Locking** convention (`data-sync-submit` / `data-sync-submit-button`)? Do not trust CSS classes alone.
- **Persistent Form Locks (Ghost Buttons)**: If a globally locked form (`data-sync-submit`) can be re-opened or re-rendered without a full page refresh (e.g. an HTMX modal that successfully fires a non-redirecting callback), you MUST mandate an explicit unlock call (e.g. `TeisutisSyncFormSubmit.reset(form)`) inside its frontend Javascript initialization/open method. Otherwise, previous submissions permanently leave the newly opened form in a disabled/spinning ghost state.
- **DOM Flattening Risk (Spinner Destruction)**: Are any global Javascript functions manipulating `.textContent` or `.className` of buttons? If the button utilizes complex spinner markup (e.g., `.sync-submit-button__idle`), a direct `.textContent` overwrite will instantly destroy the guard structure. Demand targeted `.querySelector` inner-span updates.
- **Lock Scope Escapes**: Is a cancel button (`data-sync-submit-cancel`) visually placed next to the form, but structurally sitting *outside* the `<form>` wrapper? The lock script queries explicitly *inside* the form node; cancel buttons outside this barrier will evade the lock and remain dangerously clickable.
- **Validation UX**: Are form error validations using `element.scrollIntoView()` and disappearing behind sticky navbars? Demand explicit viewport offset calculation (`window.scrollTo`).
- **Media Uploads**: If this is a `CreateView` for an entity with complex attachments, demand the **Save-Then-Attach Lifecycle** (hide uploads until the core record is saved).

### PASS 6: The Alpine.js & Defensive Execution Pass
- **Template Exfiltration (XSS Risk)**: Are backend variables directly interpolated into an Alpine `x-data` or `@click` string? They MUST be explicitly sanitized using Django's `|escapejs` filter to prevent single-quotes (e.g. `o'connor@example.com`) from shattering the Javascript parser.
- **Progressive Enhancement Backups**: Do form `<input>` fields completely surrender their initial value bindings to an Alpine `x-model` directive? Demand they explicitly retain the native HTML `value="{{ var }}"` attribute alongside it, guaranteeing the form validates natively even if the framework CDN catastrophically fails.
- **Headless Reactivity (FOUC)**: Is an `x-data` + `x-show` implementation used exclusively to toggle a static, server-rendered backend boolean? Eradicate it. Reject it heavily. Use standard Django `{% if cond %}is-hidden{% endif %}` semantic CSS classes directly on the DOM element instead to avoid unnecessary parser overhead and Flash Of Unstyled Content.
- **Lexical Closure Leaks**: Is inline template javascript branching logic based on the assumption that a utility function exists (`typeof fn === 'function'`)? Systematically trace its origin file. If that function is defined downstream inside a `DOMContentLoaded` event listener, the reference check is executing dead code. 
- **Missing API Try/Catch Guards**: Does an inline `x-init` or `@click` call interact with an external browser API (like `Intl.DateTimeFormat`, `navigator.clipboard`, or a dependent global callback) without a safety null-guard? Enforce the `if (typeof x === 'function')` or `try {...} catch(e) {...}` safety net.
