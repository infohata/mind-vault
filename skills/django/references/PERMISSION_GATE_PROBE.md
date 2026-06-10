# Permission-gate probe — replicate the view's *effective* gate, not the permission class

When you re-implement authorization for an existing surface in a **new place** — a render-fn or
HTMX fragment that replaces a class-based view, a second API endpoint, a management command, a
Celery task — replicate the gate the original view *effectively applies*. That effective gate is
usually **narrower** than the view's declared `permission_classes` / `PermissionRequiredMixin`.
Copying only the declared class into the new code path silently **widens** the gate — an
authorization regression that no test catches unless you wrote one for the narrower case.

## Why the declared class is not the gate

A DRF `permission_classes = [CanManageThings]` (or a `PermissionRequiredMixin` permission) is a
**coarse pre-filter**. The view's real authorization is the **AND** of three layers, and the last
two are easy to miss:

1. **`permission_classes` / mixin** — the coarse pre-filter ("is an org admin *somewhere*").
2. **`get_queryset()`** — object-level scoping ("things in orgs the user administers"; current-tenant
   vs the object's owning org cross-tenant). A view that edits via `get_queryset().get(pk=…)` is
   gated by the queryset, not the class — a `pk` outside the queryset 404s before the class ever
   matters.
3. **`dispatch()` / `get_object()` / `has_object_permission()`** — per-object checks ("admin of
   **this specific** thing", not any thing of the type).

### Worked divergence (generic)

- `CanManageThings` = "user administers *some* org in the current tenant."
- But `ThingUpdateView.dispatch` *additionally* requires admin of **that specific thing** (a per-object
  `UserThing(user, thing, role='admin')`) — strictly narrower.
- And `OtherThingUpdateView.get_queryset` scopes to the **object's owning org**, allowed
  *cross-tenant* — a different axis than "current tenant" the class implies.

Port `CanManageThings` alone into a fragment and any current-tenant org-admin can edit any thing —
wider than the CBV ever allowed. The architect/review catches this as "the gate moved"; cheaper to
get right at design time.

## The inverse case — sometimes the legacy gate is *wrong*

The probe also surfaces gates that are narrower in the wrong way. The classic is **authorizing on
historical authorship** — `author == request.user` (or `author_id == request.user.pk`). That
authorizes on a *past* state: a user demoted from admin keeps mutate rights on rows they once
created, and it's also wrong for team management (a current admin can't touch a colleague's row).

When re-implementing, that's the moment to **fix** the gate to the correct current-role check
(`user_can_admin_org(user, obj.org)` or equivalent), not faithfully copy the bug. Distinguish:

- *"the view's gate is narrower than the class"* → **replicate** it, and
- *"the view's gate is wrong"* → **fix** it — and when you do, re-gate the **legacy endpoint** too
  (not just the new code path) and migrate the tests that asserted the old behaviour, in the same
  change. Otherwise the loophole stays open on the old URL and a test still pins the bug.

## The probe checklist (before porting any gate)

1. Read the source view's `permission_classes`/mixin **AND** `get_queryset` **AND**
   `dispatch`/`get_object`/`has_object_permission`. The effective gate is their AND.
2. Classify the scope: per-object vs per-type vs per-org; current-tenant vs owning-org cross-tenant.
3. Replicate the effective gate at the new call site — gate on the **queryset/selector**, not just
   the class. A single `user_can_admin_<x>(user, obj)` selector reused everywhere beats re-deriving
   the predicate per surface.
4. **Enforce server-side at EVERY mutating endpoint.** Hiding a UI affordance is not authorization;
   a direct (UI-bypassing) request must be rejected. Write a UI-bypass test: a non-admin / wrong-role
   user POSTs straight to the endpoint and gets 403 + no state change.

## The dual — server-gated but the affordance still leaks

Step 4 says hiding the affordance isn't *sufficient*. The dual failure is just as common: the endpoint
**is** correctly gated server-side, but the UI affordance (the "Invite", "Cancel", "Manage →" link /
button) renders for **everyone**, so non-admins see actions they can't perform. Not an authorization
hole — clicking 403s — but a confusing leak, and exactly what an affordance-presence test
(`assert no "Invite" button for a non-admin viewer`) is meant to catch.

The reliable smell: **a permission flag passed into a render-fn / context-builder "for signature
symmetry with the cohort" but never threaded to the template.** A `can_admin` parameter the function
accepts while a docstring says it's "kept for symmetry, unused for display" is a dead parameter *and*
a guarantee the affordance is ungated — the template can't hide what it was never told. Two fixes, do
both:

- **Thread the flag to the template context** and gate the affordance: `{% if can_admin %}…{% endif %}`
  (or the cotton primitive's `can_admin` prop) — gate at the same `user_can_admin_<x>` selector the
  endpoint uses, so affordance-gate == server-gate.
- **Or drop the parameter** if the surface genuinely shows the affordance to all viewers by design.
  A passed-but-unused permission param is never the right resting state — it reads as "gated" while
  doing nothing, and a self-sweep / review bot flags it anyway (`RULE_self-sweep-before-push`).

The complete picture: gate the **endpoint** (step 4, the security boundary) **and** gate the
**affordance** (this section, the UX boundary), both off the one selector.

## Gate the GET render path too, not just the POST action

A shell/preview surface that renders an **edit form fragment** on `GET` (e.g. `?open=<entity>-edit.<pk>`
or `…/ui/form/<pk>/`) has a *third* gate the affordance-hide misses. Hiding the "Edit" button stops
the button-click path, but the GET render endpoint is still **directly reachable** — a non-editor
deep-links the preview-seed URL, bookmarks it, or hand-types it, and the server happily renders an
editable form (or, for create, an uncompletable stub). They fill it in, hit save, and only THEN eat a
403 from the POST gate. Editable-looking form → 403-on-submit is a worse UX than an honest empty-state,
and on a create-stub it wastes the user's input.

The smell: a `render_<entity>_form(request, identifier)` whose POST handler checks
`user_can_edit_<entity>` but whose **GET render path checks nothing** — it builds the form for anyone
who can reach the URL. Gate the render at the SAME selector the POST uses:

```python
def render_<entity>_form(request, identifier):
    # 'new' → create-perm; <pk> → edit-perm. Mirror the POST handler's gate.
    if identifier == 'new':
        if not user_can_create_<entity>(request.user, org, scope):
            return render_empty_state(request)            # not an editable form
    else:
        obj = get_object_or_404(<Entity>, pk=identifier, org=org)
        if not user_can_edit_<entity>(request.user, obj):
            return render_empty_state(request)
    ...  # build + render the form only past the gate
```

Three gates, one selector: **endpoint POST** (security), **GET render** (don't serve an editable form
to someone who can't save it), **affordance** (don't show the button). A deep-link / preview-seed URL
bypasses the affordance, so the GET-render gate is not redundant with hiding the button — it's the
boundary for every path that doesn't start at the button. (Surfaced on a taxonomy shell migration: the
edit-form fragment GET rendered for readers who'd be 403'd on save; three such GET-gate gaps in one PR.)

## The anonymous dual — "anon sees nothing" is a premise, not a fact

On an app with **public content** (anonymous-readable articles/FAQs/chat), the inverse
over-narrowing shows up: a shared endpoint short-circuits anonymous requests wholesale
(`if not request.user.is_authenticated: return HttpResponse(status=204)`) on the premise that
anonymous users see nothing anyway. Review bots love suggesting this guard — and on a
public-content app the premise is **false**.

The correct shape: anonymous flows through the **same resolver** as authenticated, with the
visibility selector doing the narrowing — `visible_to(None)` / `visible_to(request.user)`
returning the public-only subset for anon. The data layer already knows what anon may see;
a blanket endpoint short-circuit second-guesses it and breaks every anon-reachable surface
the endpoint serves. Private objects still leak nothing (the selector returns empty), so the
short-circuit buys no security — it only subtracts function.

The telltale symptom when this regresses: the surface works on **cold load** (server-rendered
markup includes the chrome) but breaks on **client-side interaction** (the JS path re-fetches
the fragment from the short-circuited endpoint and gets nothing). Cold-start ≠ hot-path is the
grep cue that some endpoint in the re-fetch chain special-cases anon. Test contract: one
anon-public-renders test + one anon-private-no-leak test on the same endpoint, replacing any
test that pinned the blanket-deny behavior.

## When NOT to over-probe

If the view's only gate genuinely *is* the permission class — no `get_queryset` narrowing, no
`dispatch`/object check — then copying the class is correct and complete. Verify (read all three
layers), don't assume. The rule is "read the effective gate," not "always invent a narrower one."
