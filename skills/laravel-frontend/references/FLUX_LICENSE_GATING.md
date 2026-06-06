# Flux license gating — the CI build-gate hazard

Deep-dive for the **Component system** contract heading, `[Variant: Livewire + Flux]`. Flux is Livewire's first-party UI kit (`<flux:…>`). It is **freemium**: a free tier plus a Pro tier that is **license-gated**. Using a Pro component without a valid license + auth token is a real **CI build-failure hazard** — this reference is how to recognise and prevent it.

## Free vs Pro split

- **Free tier** — the common primitives. `<flux:button>`, `<flux:input>`, `<flux:checkbox>`, `<flux:field>`, and similar are free. Example (verified free-tier):

  ```blade
  <flux:button variant="primary" type="submit">Save</flux:button>
  ```

- **Pro tier (license-gated)** — richer components: chart, date-picker, editor, calendar, and others. These require a **paid Flux license** and an authenticated Composer/npm source to install. Their assets only resolve in the build when the license/token is present.

Flux also requires **Tailwind** and a Flux install — so it is a **variant-only** option (Livewire + Tailwind projects), never the plain-Blade baseline.

## Why it gates CI

When a template references a Pro tag (e.g. `<flux:chart>`) but the build environment has no license/auth token:

- the Composer install of the Pro package fails (`composer.json` points at `composer.fluxui.dev` with auth that CI lacks), or
- the Vite/asset build cannot resolve the Pro component's styles/JS,

so the **CI asset-build step fails** — even though the same template renders fine on a developer machine that has the license configured locally. This is the classic "works on my machine, breaks in CI" auth-token gap.

## Detect before it breaks CI

1. **Grep for Pro tags** before relying on them in CI:

   ```bash
   grep -rEn '<flux:(chart|date-picker|calendar|editor|command|autocomplete)' resources/views
   ```

   Any hit means the build needs a Flux Pro license/token configured in CI.

2. **Confirm the auth source is wired** — check `composer.json` / `auth.json` (or the CI secret store) has the Flux Pro credentials. Never commit the token; it belongs in CI secrets.

3. **Fail loud, not silent** — if a Pro component is required and the token is absent, the build SHOULD fail at install time with a clear message, not silently ship an unstyled/broken component.

4. **Prefer free-tier or hand-rolled** for components on the critical path unless the Pro license is already provisioned in CI — a date-picker built from a free `<flux:input>` + a small vanilla-JS calendar avoids the gate entirely.

## Rule

Treat any `<flux:*>` Pro component as a **build dependency with a credential requirement**. Surface it in review the same way you would a new paid SaaS key — never assume the license exists in CI just because it exists locally.

## Sources

- fluxui.dev — component catalogue, free vs Pro tiers, installation/license docs (Laravel 12 / Livewire 4).
