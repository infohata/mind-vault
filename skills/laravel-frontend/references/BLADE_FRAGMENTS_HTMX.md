# Blade fragments + HTMX — the Django `HTMXMixin` twin (baseline deep-dive)

Deep-dive for the **Partial/fragment response** contract heading. This is the **plain-Blade baseline** mechanism — the structural twin of Django's `HTMXMixin`: one route returns the full page on a normal navigation, or just the changed fragment on an `HX-Request` (or any `fetch`-driven swap). The server owns which slice ships over the wire.

## The mechanism: `@fragment` + `->fragmentIf(...)`

Wrap the swappable region in a named `@fragment` in the Blade view, then conditionally render only that fragment from the controller based on a request header.

```php
{{-- resources/views/articles/index.blade.php --}}
@extends('layouts.app')

@section('content')
    <form data-fragment-get="{{ route('articles.index') }}" data-target="#article-list">
        <input type="search" name="q" data-debounce="300">
    </form>

    @fragment('article-list')
        <div id="article-list">
            @foreach ($articles as $article)
                <x-article-row :article="$article" />
            @endforeach
            {{ $articles->links() }}
        </div>
    @endfragment
@endsection
```

```php
// app/Http/Controllers/ArticleController.php
public function index(Request $request)
{
    $articles = Article::with('author')
        ->when($request->query('q'), fn ($q, $term) => $q->where('title', 'like', "%{$term}%"))
        ->paginate();

    return view('articles.index', compact('articles'))
        ->fragmentIf($request->hasHeader('HX-Request'), 'article-list');
}
```

- `->fragment('name')` — always return just that fragment.
- `->fragmentIf($cond, 'name')` — return the fragment when `$cond` is true, else the full view.
- `->fragments(['a', 'b'])` — concatenate multiple named fragments.

## Header detection

`HX-Request` is the header HTMX sends. With plain `fetch` (the vanilla baseline) you set it yourself:

```js
// resources/js/fragment.js
async function swapFragment(url, targetSel) {
    const res = await fetch(url, { headers: { 'HX-Request': 'true' } });
    const html = await res.text();
    document.querySelector(targetSel).outerHTML = html;
}
```

The same route serves both shapes — **DO:** one route, one view, dispatched on the header. **DON'T:** a second `/articles/partial` endpoint, which duplicates the query + authorization logic and drifts.

## Guard the trigger

- **Debounce** filter-on-keystroke (the `data-debounce` above) — never fire a request per keystroke.
- A fragment must **never recursively re-request itself** — the swap target's contents must not contain a trigger that immediately re-fires the same fetch on insert.
- Bake visibility into the server response (the fragment ships rendered correctly), not a post-paint JS toggle — avoids layout-shift FOUC.

## `[Variant: Livewire]` — do NOT hand-roll fragments

In a Livewire project, partial updates are automatic: a component re-render produces a server-side DOM diff that Livewire patches in. Hand-rolling `@fragment` + `->fragmentIf` inside a Livewire component fights the framework's own diffing — don't.

## Sources

- laravel.com/docs/12.x/blade — Blade fragments (`@fragment`, `->fragment()` / `->fragmentIf()`).
- htmx.org/docs — `HX-Request` request header.
