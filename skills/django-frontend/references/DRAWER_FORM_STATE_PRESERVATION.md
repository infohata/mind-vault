# Drawer form-state preservation — clone-mirror-strip pipeline

Companion reference to [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md). When a megastack-style preview drawer takes a snapshot of a frame before pushing a child (so the parent can be restored on pop), the naive `host.innerHTML` snapshot loses in-flight form state — typed-into textareas snap back to their server-rendered defaults, unsaved checkbox flips revert, in-progress selects reset.

The fix isn't "serialize form state separately and merge on restore" — that path proliferates with every new widget. Instead, snapshot a *cloned host with form state mirrored onto its DOM*, then strip widget-specific artefacts via a public cleanup hook.

## When to use

- A drawer (or any container) that swaps content on push/pop and must restore the prior content on pop.
- Frames may contain forms with user-typed input — textareas, selects, checkboxes, radios, text inputs.
- Frames may contain rich-text editors, file uploaders, or other widgets that mount sibling DOM (TipTap toolbars, dropzones).

## When NOT to use

- Frames are pure read-only views with no form state. Plain `innerHTML` snapshot is fine.
- The pop always re-fetches from the server (no snapshot reuse). Skip snapshotting entirely.

## The pipeline

```js
function takeSnapshot(host) {
    // 1. CLONE — non-destructive deep copy of the live host
    const clone = host.cloneNode(true);

    // 2. MIRROR — serialise live runtime form state onto the clone's DOM
    //    so the next innerHTML serialization includes user input
    _mirrorFormState(host, clone);

    // 3. STRIP — give widget modules a chance to remove their mounted
    //    sibling DOM (toolbars, hidden inputs, etc.) from the clone
    document.dispatchEvent(new CustomEvent('previewSurface:beforeSnapshot', {
        detail: { clone, host },
    }));

    // 4. SERIALIZE — read innerHTML from the cleaned clone
    return clone.innerHTML;
}
```

### `_mirrorFormState` — what to copy and how

Live form state lives in JavaScript property-land — `element.value`, `element.checked`, `element.selected` — but `innerHTML` serialization reads HTML attributes. Mirror the runtime state onto the corresponding attribute:

```js
function _mirrorFormState(host, clone) {
    // Iterate paired (live, clone) elements via matching positions
    const liveTextareas = host.querySelectorAll('textarea');
    const cloneTextareas = clone.querySelectorAll('textarea');
    liveTextareas.forEach((live, i) => {
        // textContent is what gets serialised for <textarea>
        cloneTextareas[i].textContent = live.value;
    });

    const liveSelects = host.querySelectorAll('select');
    const cloneSelects = clone.querySelectorAll('select');
    liveSelects.forEach((live, i) => {
        const cloneSel = cloneSelects[i];
        cloneSel.querySelectorAll('option').forEach((opt, j) => {
            const liveOpt = live.options[j];
            if (liveOpt && liveOpt.selected) {
                opt.setAttribute('selected', 'selected');
            } else {
                opt.removeAttribute('selected');
            }
        });
    });

    const liveCheckables = host.querySelectorAll('input[type=checkbox], input[type=radio]');
    const cloneCheckables = clone.querySelectorAll('input[type=checkbox], input[type=radio]');
    liveCheckables.forEach((live, i) => {
        const cloneEl = cloneCheckables[i];
        if (live.checked) {
            cloneEl.setAttribute('checked', 'checked');
        } else {
            cloneEl.removeAttribute('checked');
        }
    });

    const liveTextInputs = host.querySelectorAll(
        'input[type=text], input[type=email], input[type=number], input[type=tel], input[type=url], input[type=search], input[type=date], input[type=time], input[type=datetime-local]'
    );
    const cloneTextInputs = clone.querySelectorAll(
        'input[type=text], input[type=email], input[type=number], input[type=tel], input[type=url], input[type=search], input[type=date], input[type=time], input[type=datetime-local]'
    );
    liveTextInputs.forEach((live, i) => {
        cloneTextInputs[i].setAttribute('value', live.value);
    });
}
```

The pairing-by-position approach assumes the clone has identical DOM order — which it does, because `cloneNode(true)` preserves it. If a widget mutates DOM order after mount (TipTap reorders toolbar buttons, for example), this can mis-pair — the cleanup hook (step 3) is where TipTap's module removes those reordered siblings entirely.

### The cleanup hook — `previewSurface:beforeSnapshot`

Widgets that mount sibling DOM (toolbars, hidden state-mirror inputs, dropzone overlays) must clean their artefacts off the snapshot. The clone-mirror-strip pipeline dispatches a `previewSurface:beforeSnapshot` event on `document` with `{ clone, host }` in detail; widget modules subscribe and remove their own mounted siblings from `clone`:

```js
// TipTap widget — at mount time, registers a cleanup subscriber
document.addEventListener('previewSurface:beforeSnapshot', (event) => {
    const { clone } = event.detail;
    // Remove TipTap-mounted toolbars + ProseMirror sibling nodes
    clone.querySelectorAll('.tiptap-toolbar, .ProseMirror, [data-tiptap-mounted]')
         .forEach(el => el.remove());
    // TipTap stores content as Markdown in a hidden textarea — mirror its
    // current document into that textarea's textContent so the snapshot
    // restores correctly on pop (the textarea is the source of truth on
    // re-mount, not the rendered ProseMirror DOM).
    clone.querySelectorAll('[data-tiptap-textarea]').forEach(textarea => {
        const editorId = textarea.dataset.tiptapEditorId;
        const editor = _activeEditors.get(editorId);
        if (editor) textarea.textContent = editor.storage.markdown.getMarkdown();
    });
});
```

```js
// form-help widget — similar pattern, removes its dynamically-injected help text
document.addEventListener('previewSurface:beforeSnapshot', (event) => {
    event.detail.clone.querySelectorAll('[data-form-help-injected]').forEach(el => el.remove());
});
```

The contract is **generic** — the drawer doesn't know about widgets, widgets don't know about the drawer. They meet at the named event. Future widgets (file uploaders, autocomplete dropdowns, color pickers) participate by subscribing.

## Restore — `innerHTML` reassignment + widget re-mount

```js
function restoreSnapshot(host, snapshotHtml) {
    host.innerHTML = snapshotHtml;
    // Re-fire the HTMX rebind events so widgets re-mount against the restored DOM.
    // See PREVIEW_DRAWER_URL_STACK.md § Walker rebind contract for the three-event sequence.
    for (const name of ['htmx:afterSwap', 'htmx:afterSettle', 'htmx:load']) {
        host.dispatchEvent(new CustomEvent(name, {
            bubbles: true,
            detail: { elt: host, target: host, successful: true, requestConfig: {} },
        }));
    }
}
```

The runtime state-mirroring done in `_mirrorFormState` makes the restored `innerHTML` carry the user's in-flight input. Widget remount via the rebind events brings the rich widgets back online — TipTap reads the textarea's content, dropzones rebind to the file-input, autocompletes re-subscribe.

## The WHY of the megastack drawer pattern

The clone-mirror-strip pipeline is the load-bearing piece that makes a megastack drawer *usable* for forms. Without it:

- Pushing a child frame on top of a parent form snapshots `parent.innerHTML` with the server's empty defaults.
- Popping back restores the empty form. Every keystroke the user typed before pushing is gone.
- The user learns to avoid using the megastack while editing — defeats the purpose of the drawer.

With the pipeline, push/pop is transparent to form state. The drawer can stack 3 frames deep, the user can edit at any depth, pop back through all 3, and every frame's form state survives intact.

## Test contract

Cover the runtime-state mirroring with a deterministic test:

```js
test('snapshot preserves typed textarea content', () => {
    const host = document.createElement('div');
    host.innerHTML = '<textarea name="body"></textarea>';
    host.querySelector('textarea').value = 'User typed this';

    const snapshot = takeSnapshot(host);

    expect(snapshot).toContain('>User typed this</textarea>');
});

test('cleanup hook removes widget artefacts', () => {
    let cleanupCalled = false;
    const handler = (event) => {
        cleanupCalled = true;
        event.detail.clone.querySelectorAll('.widget-artefact').forEach(el => el.remove());
    };
    document.addEventListener('previewSurface:beforeSnapshot', handler);

    const host = document.createElement('div');
    host.innerHTML = '<div class="widget-artefact">should not be in snapshot</div><p>keep me</p>';

    const snapshot = takeSnapshot(host);

    expect(cleanupCalled).toBe(true);
    expect(snapshot).not.toContain('widget-artefact');
    expect(snapshot).toContain('keep me');

    document.removeEventListener('previewSurface:beforeSnapshot', handler);
});
```

## Anti-patterns

- ❌ **Serialise form state into a separate object on snapshot, merge on restore.** Proliferates state-store/restore code per widget; clone+mirror keeps the surface uniform.
- ❌ **Skip the cleanup hook; let widget artefacts land in the snapshot.** Toolbars accumulate, ProseMirror's hidden nodes get re-serialised into the next render, IDs collide. The hook is cheap (~5 LoC per widget) and bounds the snapshot to clean HTML.
- ❌ **Re-fetch on every pop instead of snapshotting.** Loses the user's work the moment they push; defeats the form-friendly drawer use case.
- ❌ **Mirror state ONLY for `<textarea>` because that's the most-edited element.** Selects, checkboxes, radios all lose state without their attribute updates too.

## Reference

The pipeline name + the event-based cleanup contract are reusable across any drawer-style UI in any project; the implementation is project-specific to the framework + widget set. See [`PREVIEW_DRAWER_URL_STACK.md`](PREVIEW_DRAWER_URL_STACK.md) for the surrounding URL-stack contract this pipeline operates within.
