---
name: laravel-frontend
description: Apply Laravel 12 frontend conventions across the four client-surface concerns — where client state lives (server-rendered Blade baseline, with Livewire 4 and Inertia 2 as opt-in variant layers), how a server returns a fragment vs a full page (Blade @fragment + ->fragmentIf on HX-Request, the Django HTMXMixin twin), how reusable UI is composed (Blade components, CSS-framework-agnostic; Flux only as a license-gated Livewire UI kit), and how a form is guarded against double-submit (vanilla-JS in-flight lock baseline, automatic with wire:submit). Baseline is plain server-rendered Blade + Bootstrap-style CSS + Vite + minimal vanilla JS (native fetch; axios is a drop-in alternative); Livewire/Inertia/Flux/Tailwind/Alpine are documented variants, never assumed.
license: Apache-2.0
metadata:
  author: mind-vault
  version: '0.1'
---

# laravel-frontend

Production frontend patterns for Laravel 12, organised around the four client-surface contract concerns. **The baseline is plain server-rendered Blade + a Bootstrap-style CSS framework + Vite + minimal vanilla JS (native `fetch` — axios is a drop-in alternative the adopter happens to use)** — the actual stack of a real Laravel 12 rework PoC (server-rendered Blade, Bootstrap 5, Vite, vanilla JS; NO Livewire / Inertia / Flux / Tailwind / Alpine). Philosophy: the server renders truth as HTML, the browser does the minimum to enhance it. Livewire 4 and Inertia 2 are presented as **opt-in variant layers**, clearly marked `[Variant: Livewire]` / `[Variant: Inertia]`; Flux is a **license-gated Livewire UI kit**, never the default.

**Pairs with:** [laravel](../laravel/SKILL.md) for backend conventions (Form Requests, Eloquent eager-loading, Policies, queues). Load both on full-stack feature work — e.g. a controller returning a Blade fragment on an `HX-Request` and the full page otherwise.

## When to use

**TRIGGER when:** editing Blade templates (`resources/views/*.blade.php`); wiring a server-rendered partial / fragment endpoint; adding a Blade component (`<x-…>`) or anonymous component; configuring or extending the Vite build (`vite.config.js`, `resources/js/app.js`); writing the vanilla-JS submit-lock; **or** working in a project that has opted into Livewire (`wire:*` attributes, `app/Livewire/*`), Inertia (`@inertia`, `resources/js/Pages/*`), or Flux (`<flux:…>`).

**SKIP for:** backend-only work (use [laravel](../laravel/SKILL.md)); pure API/JSON services with no server-rendered views; mobile-native clients; heavy offline-first PWAs needing a full client framework + API backend.

## Stack / variant table

| Layer | What it is | When it applies |
| --- | --- | --- |
| **Baseline — plain Blade** | Server-rendered Blade + Bootstrap-style CSS + Vite + minimal vanilla JS (native `fetch`; axios optional). No reactive framework. | Default. Assume this unless a variant is detected or pinned. |
| **[Variant: Livewire 4]** | PHP component classes; `wire:*` directives; bundled Alpine for local-only UI. Ships in L12 starter kits. | Project has `wire:*` in views / `app/Livewire/*`. |
| **[Variant: Inertia 2]** | Vue 3 / React 19 / Svelte 5 SFCs; JSON props over the adapter; client-side routing. | Project has `@inertia` + `resources/js/Pages/*`. |
| **Flux** (UI kit, not a variant) | Livewire's first-party `<flux:…>` component kit. **Free tier + Pro tier (license-gated).** | Livewire-only, and only when Tailwind + Flux are installed. Never baseline. |

**Variant resolution:** the `stack:` pin (`laravel-frontend`, optionally `+livewire` / `+inertia`) or auto-detect (the directives/dirs above) selects the variant. **Fail-open discipline (the SKILL_CONTRACT clause) extends to variant ambiguity:** if the variant cannot be resolved, **enforce the plain-Blade baseline and announce the unresolved variant** — never silently assume Livewire or Inertia.

## Pattern

The four sections below are the **required contract headings** (verbatim-identical strings to `../django-frontend/SKILL.md` — they are the grep-resolved cross-stack interface; never rephrase them). Each leads with the plain-Blade/vanilla-JS **baseline**, then adds variant sub-notes.

### Reactivity model

**Baseline (plain Blade):** the server is the single source of truth. State changes go back to the server — a full-page navigation, or a server-rendered fragment swap (see *Partial/fragment response*). Local-only interactivity (toggling a menu, disabling a button) is a tiny scoped `<script>` that touches only the element it owns, or a `fetch` call whose response replaces a region. No global function dumping, no framework store.

```js
// resources/js/menu.js — scoped, no globals leak
document.querySelectorAll('[data-toggle-target]').forEach((btn) => {
    btn.addEventListener('click', () => {
        const target = document.querySelector(btn.dataset.toggleTarget);
        target?.toggleAttribute('hidden');
    });
});
```

The closure boundary is the file: imported through Vite (`resources/js/app.js`), never an inline `<script>` defining globals. Visibility that affects layout ships **rendered correctly by the server** (a `hidden` attribute set in Blade), not toggled on after paint — avoid the flash-of-unstyled-content trap of hiding structural DOM with JS only.

**i18n note (client-data-path):** UI strings must NOT be fetched via a per-request translation API + runtime cache — *if you are caching translation strings in Redis just to survive the load, that is the smell.* For server-rendered Blade, resolve them server-side via `__()` / `@lang` so they never cross the wire as data; for an SPA/Inertia variant, compile them to JSON shipped with the Vite bundle (versioned by bundle hash). Only genuinely per-tenant operator content stays a small runtime payload. (Cross-ref `../laravel/SKILL.md` → Translation workflow.)

`[Variant: Livewire]` PHP public props on the component class are the state; they bind to the DOM via `wire:model` (**deferred by default** — synced on the next network round-trip, e.g. a `wire:click` / `wire:submit`). `wire:model.live` is the opt-in real-time modifier. Bundled Alpine (`x-data`) is for **local-only** UI that never needs the server. **ANTI:** `wire:model.live` on every input — a network round-trip per keystroke; default to deferred and reach for `.live` only where live feedback is required.

`[Variant: Inertia]` client state lives in Vue refs / React `useState`; server data arrives as JSON props on the page component. Keep derived state computed, not duplicated into local state that can drift from props.

### Partial/fragment response

**Baseline (plain Blade) — the Django `HTMXMixin` twin:** one route returns either the full page (normal navigation) or just the changed fragment (an `HX-Request` / `fetch` swap), dispatched on a request header. Blade's `@fragment` directive plus the response's `->fragmentIf(...)` is the mechanism — the server owns which slice ships.

```php
// resources/views/articles/index.blade.php
@extends('layouts.app')
@section('content')
    <form data-fragment-get="{{ route('articles.index') }}" data-target="#article-list">
        {{-- filter inputs --}}
    </form>

    @fragment('article-list')
        <div id="article-list">
            @foreach ($articles as $article)
                <x-article-row :article="$article" />
            @endforeach
        </div>
    @endfragment
@endsection
```

```php
// app/Http/Controllers/ArticleController.php
public function index(Request $request)
{
    $articles = Article::with('author')->paginate();

    return view('articles.index', compact('articles'))
        ->fragmentIf($request->hasHeader('HX-Request'), 'article-list');
}
```

A fragment request to the same URL returns only the `article-list` fragment; the tiny vanilla-JS handler swaps it into `#article-list`; the page does not navigate. **DO:** one route, one view, dispatched on the header. **DON'T:** a second `/articles/partial` endpoint — it duplicates the query + authorization. **Guard the trigger** — debounce filter-on-keystroke; never let a fragment recursively re-request itself.

`[Variant: Livewire]` fragments are **automatic** — a component re-render produces a server-side DOM diff that Livewire patches in; you do not hand-roll `@fragment`. **ANTI:** hand-rolling `@fragment` + `->fragmentIf` inside a Livewire component — fights the framework's own diffing.

`[Variant: Inertia]` use `router.reload({ only: ['articles'] })` (or `except: [...]`) to re-fetch a subset of props without a full page visit; Inertia 2 deferred/lazy props let the server mark expensive props as load-on-demand. (See [references/INERTIA_PARTIAL_RELOADS.md](references/INERTIA_PARTIAL_RELOADS.md).)

### Component system

**Baseline (plain Blade):** reusable UI is **Blade components** — class-based (`php artisan make:component`) for components needing logic, anonymous (`resources/views/components/*.blade.php`) for pure markup, with `<x-slot>` for named slots. Styling is **CSS-framework-agnostic** — the baseline adopter uses Bootstrap, but the component contract does not assume any framework; pass classes/variants as props.

```blade
{{-- resources/views/components/button.blade.php (anonymous) --}}
@props(['variant' => 'primary', 'type' => 'button'])
<button type="{{ $type }}" {{ $attributes->merge(['class' => "btn btn-{$variant}"]) }}>
    {{ $slot }}
</button>
```

```blade
{{-- call site --}}
<x-button variant="primary" type="submit">Save</x-button>
```

When a UI element is rendered both server-side (Blade) and re-rendered client-side (a vanilla-JS helper), treat the two as one DOM contract — change both in the same commit (the boundary-parity rule).

`[Variant: Livewire + Flux]` the first-party UI kit is **Flux** (`<flux:…>`), which requires Tailwind + a Flux install — so it is a variant-only option, never baseline. The free tier covers the common primitives, e.g.:

```blade
<flux:button variant="primary" type="submit">Save</flux:button>
```

**ANTI / CI build hazard:** Flux **Pro** components (chart, date-picker, editor, etc.) require a paid license + an auth token at build time. Using a Pro tag without the license/token **gates CI** — the asset build fails to resolve the component. Detect before it breaks CI. (See [references/FLUX_LICENSE_GATING.md](references/FLUX_LICENSE_GATING.md).)

`[Variant: Inertia]` components are Vue / React / Svelte single-file components, commonly paired with **shadcn** (`npx shadcn add …`). Keep the same prop-driven, framework-agnostic styling discipline.

### Form-submission lock

**Baseline (plain Blade) — vanilla JS, the adopter's real pattern:** on `submit`, disable the submit button and set inputs `readonly`. A single delegated listener + an in-flight flag is enough; no per-form `onsubmit` sprinkling. **Lock vs unlock is a navigation question:** a full-page (navigating) submit *keeps* the lock until the new page replaces this one — that's the point, it blocks the double-submit during the in-flight navigation. Only a non-navigating (axios/fetch) submit clears the lock when the request settles, plus the one defensive clear for bfcache below.

```js
// resources/js/submit-lock.js — one delegated listener, no globals
function lockForm(form) {
    form.dataset.locked = '1';
    const btn = form.querySelector('[type="submit"]');
    // flip a data-attr the CSS reads; do NOT overwrite innerHTML (destroys a spinner child).
    if (btn) { btn.disabled = true; btn.dataset.loading = '1'; }
    form.querySelectorAll('input, textarea, select').forEach((el) => { el.readOnly = true; });
}

function unlockForm(form) {                              // for the axios/fetch path + bfcache
    delete form.dataset.locked;
    const btn = form.querySelector('[type="submit"]');
    if (btn) { btn.disabled = false; delete btn.dataset.loading; }
    form.querySelectorAll('input, textarea, select').forEach((el) => { el.readOnly = false; });
}

document.addEventListener('submit', (e) => {
    const form = e.target;
    // Skip framework-managed forms. Livewire's wire:submit already locks the
    // button + sets inputs readonly in-flight; stacking this vanilla lock on top
    // desyncs the two (see the [Variant: Livewire] note below). Opt any other
    // form out with data-no-lock. This keeps the baseline lock to plain forms.
    if (form.hasAttribute('wire:submit') || form.dataset.noLock !== undefined) return;
    if (form.dataset.locked) { e.preventDefault(); return; }
    lockForm(form);                                      // navigating submit: stays locked until the page unloads
});

// bfcache restores a navigated-away page on Back with the lock still set, freezing
// the form. The persisted-pageshow clear is the one case a navigating submit needs.
window.addEventListener('pageshow', (e) => {
    if (e.persisted) document.querySelectorAll('form[data-locked]').forEach(unlockForm);
});
```

For a non-navigating `axios`/fetch submit (the form does **not** reload the page), call `lockForm(form)` before the request and `unlockForm(form)` in `.finally()` so the form re-enables when it settles. **Flip state with a targeted query / data-attribute the CSS reads — never replace the whole button node's text**, which destroys an inner spinner element.

`[Variant: Livewire]` the lock is **AUTOMATIC** — write bare `wire:submit="save"` (it self-prevents the native submit; do NOT write `wire:submit.prevent`). Livewire disables the submit button and sets inputs readonly while the action is in flight. Layer `wire:loading.delay` (spinner), `wire:target="save"` (scope the indicator to one action), and `wire:dirty.class` for unsaved-change affordance. **ANTI:** stacking a manual Alpine/vanilla lock on a `wire:submit` form — the two locks desync and the button can stick disabled. (See [references/LIVEWIRE_LOADING_STATES.md](references/LIVEWIRE_LOADING_STATES.md).)

`[Variant: Inertia]` bind the in-flight state the form helper exposes — `:disabled="form.processing"` (Vue 3; identical `processing` property across Vue/React/Svelte, only the binding syntax differs). Do not roll your own flag.

## When NOT to use these patterns

- **SPA-scale interactivity** — real-time collaborative editing, complex client-side state graphs, rich offline capability. Reach for a full client framework (the Inertia variant, or a separate SPA + API).
- **Backend-only work** — controllers, models, migrations, jobs → use [laravel](../laravel/SKILL.md).
- **Pure JSON API** — no server-rendered views means none of the four concerns here apply.
- **Mobile native** — native iOS/Android or React Native are different stacks entirely.

## References

- [Livewire loading states](references/LIVEWIRE_LOADING_STATES.md) — `wire:loading` / `.delay`, `wire:target`, `wire:dirty`, the automatic in-flight submit lock, deferred-vs-`.live` `wire:model` (variant deep-dive).
- [Blade fragments + HTMX](references/BLADE_FRAGMENTS_HTMX.md) — the Django `HTMXMixin` twin: `@fragment` + `->fragmentIf(...)`, `HX-Request` detection, server-rendered partial responses (the **baseline** deep-dive).
- [Flux license gating](references/FLUX_LICENSE_GATING.md) — Flux free vs Pro split, the CI build-gate hazard when Pro components ship without a license/auth token, how to detect it before CI breaks.
- [Inertia partial reloads](references/INERTIA_PARTIAL_RELOADS.md) — `router.reload({ only: […] })` / `except:`, Inertia 2 deferred/lazy props, `form.processing` (Inertia variant deep-dive).
- [laravel](../laravel/SKILL.md) — backend pairing (Form Requests, Eloquent, Policies, queues, the split-by-ownership translation workflow).
- [Laravel Blade docs](https://laravel.com/docs/12.x/blade)
- [Livewire docs](https://livewire.laravel.com/docs)
- [Inertia docs](https://inertiajs.com)
- [Flux UI](https://fluxui.dev)
