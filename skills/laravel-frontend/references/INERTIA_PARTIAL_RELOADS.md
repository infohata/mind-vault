# Inertia partial reloads & form processing (Inertia 2)

`[Variant: Inertia]` deep-dive for the **Partial/fragment response** and **Form-submission lock** contract headings. Inertia is **v2** (Vue 3 / React 19 / Svelte 5). This reference applies only to projects that have opted into Inertia (`@inertia` + `resources/js/Pages/*`); the plain-Blade baseline uses `@fragment` instead (see [BLADE_FRAGMENTS_HTMX.md](BLADE_FRAGMENTS_HTMX.md)).

## Partial reloads — fetch a subset of props

A normal Inertia visit re-fetches **all** of a page's props. To re-fetch only some, use `router.reload` with `only:` (allow-list) or `except:` (deny-list). The server still runs the controller, but only the listed props are evaluated and sent.

```js
import { router } from '@inertiajs/vue3'

// re-fetch only the `articles` prop (e.g. after applying a filter)
router.reload({ only: ['articles'] })

// re-fetch everything except an expensive prop
router.reload({ except: ['analytics'] })
```

On the server, wrap the prop in a closure so it is only evaluated when actually requested:

```php
// app/Http/Controllers/ArticleController.php
return Inertia::render('Articles/Index', [
    'articles' => fn () => Article::with('author')->paginate(),
]);
```

A closure prop is **lazy** — skipped entirely on a partial reload that does not name it, so the query never runs.

## Inertia 2 deferred & lazy props

Inertia 2 adds first-class deferred/lazy props for expensive data — the page renders immediately, the prop loads on demand:

```php
use Inertia\Inertia;

return Inertia::render('Dashboard', [
    'stats'  => Inertia::defer(fn () => $this->expensiveStats()),
    'optional' => Inertia::lazy(fn () => $this->onlyWhenAsked()),
]);
```

`defer` auto-loads after the initial render; `lazy` loads only when explicitly requested via a partial reload. Use these instead of blocking the whole page on a slow query.

## Form-submission lock — `form.processing`

The Inertia form helper exposes an in-flight flag. Bind it directly — **do not roll your own** submitting flag.

```vue
<script setup>
import { useForm } from '@inertiajs/vue3'
const form = useForm({ title: '' })
const submit = () => form.post('/articles')
</script>

<template>
  <form @submit.prevent="submit">
    <input v-model="form.title" :disabled="form.processing">
    <button type="submit" :disabled="form.processing">Save</button>
  </form>
</template>
```

`form.processing` is `true` from submit until the response settles. The **`processing` property is identical across Vue / React / Svelte** — only the binding syntax differs (`:disabled=` in Vue, `disabled={form.processing}` in React, `disabled={form.processing}` in Svelte). The helper also exposes `form.errors`, `form.recentlySuccessful`, and `form.reset()`.

## Sources

- inertiajs.com — partial reloads, deferred props (Inertia 2), forms (`useForm` / `processing`).
