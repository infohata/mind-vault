# Livewire loading states & the automatic submit lock

`[Variant: Livewire]` deep-dive for the **Form-submission lock** and **Reactivity model** contract headings. Livewire is **v4** (ships in Laravel 12 starter kits — do not pin v3). The plain-Blade baseline owns its own vanilla-JS lock; this reference is only for projects that have opted into Livewire.

## The lock is automatic — start from `wire:submit`

`wire:submit` self-prevents the native form submit. Write it **bare** — `wire:submit="save"`, NOT `wire:submit.prevent` (the `.prevent` is redundant in v3/v4 and signals a stale habit).

```blade
<form wire:submit="save">
    <input type="text" wire:model="title">
    <button type="submit">Save</button>
</form>
```

While `save` is in flight, Livewire **automatically**:

- disables the submit button,
- sets bound inputs `readonly`,
- re-enables everything when the round-trip settles.

You do not write a manual lock. **ANTI:** stacking an Alpine or vanilla `submitting` flag on top of a `wire:submit` form — the two locks desync and the button can stick disabled after an error.

## Loading affordances

Layer these on top of the automatic lock:

```blade
<button type="submit">
    <span wire:loading.remove wire:target="save">Save</span>
    <span wire:loading.delay wire:target="save">Saving…</span>
</button>
```

- `wire:loading` — show an element only while a request is in flight.
- `wire:loading.delay` — wait ~200ms before showing (avoids a flash on fast requests). Variants: `.delay.shortest` / `.shorter` / `.short` / `.long` / `.longer` / `.longest`.
- `wire:loading.remove` — hide an element while in flight (the inverse).
- `wire:target="save"` — **scope the indicator to one action**, so clicking "Save" does not spin the "Delete" button's indicator.
- `wire:loading.class="opacity-50"` / `wire:loading.attr="disabled"` — apply a class / attribute only in flight.

## Dirty-state affordance

```blade
<input wire:model="title" wire:dirty.class="border-warning">
<span wire:dirty wire:target="title">Unsaved</span>
```

`wire:dirty` reflects "the input differs from the last server-synced value" — useful for unsaved-change cues. Pair with deferred `wire:model` (below).

## Deferred vs live `wire:model`

`wire:model` is **deferred by default** in v3/v4 — the value syncs to the server on the next network action (a `wire:click`, `wire:submit`, etc.), NOT on every keystroke. This is the correct default: one round-trip per meaningful action.

```blade
{{-- deferred (default) — syncs on submit/click --}}
<input wire:model="search">

{{-- live — syncs on every input event (use sparingly) --}}
<input wire:model.live="search">

{{-- live but debounced --}}
<input wire:model.live.debounce.500ms="search">
```

**ANTI:** `wire:model.live` on every input — a network round-trip per keystroke floods the server. Reach for `.live` only where live feedback is genuinely required (e.g. a search-as-you-type box), and add `.debounce` when you do.

## Sources

- livewire.laravel.com/docs — wire-loading, wire-dirty, wire-model, forms (Laravel 12 / Livewire 4).
