# Form Requests & API Resources — the input/output boundary

Untrusted input is validated **once, at the edge**, in a Form Request. The controller never validates inline and never reads raw input after validation. Output goes through an API Resource so the wire shape is explicit and decoupled from the table.

## Form Request — `make:request`

```php
// php artisan make:request StorePostRequest
class StorePostRequest extends FormRequest
{
    // authorize() — coarse gate; return false → 403 before rules() runs.
    public function authorize(): bool
    {
        return $this->user()->can('create', Post::class);
    }

    public function rules(): array
    {
        return [
            'title'      => ['required', 'string', 'max:255'],
            'body'       => ['required', 'string'],
            'tags'       => ['array'],
            'tags.*'     => ['integer', 'exists:tags,id'],
            'publish_at' => ['nullable', 'date', 'after:now'],
        ];
    }

    // Optional: normalise BEFORE validation runs.
    protected function prepareForValidation(): void
    {
        $this->merge(['slug' => str()->slug($this->title)]);
    }

    // Optional: custom messages / attribute names.
    public function messages(): array
    {
        return ['body.required' => 'A post needs a body.'];
    }
}
```

## The `validated()`-only controller contract

The controller is thin. It receives the typed Form Request (Laravel resolves + validates it before the method body runs) and reads **only** `$request->validated()`.

```php
public function store(StorePostRequest $request): JsonResponse
{
    // validated() = ONLY the keys that passed rules(). Never $request->all().
    $post = Post::create($request->validated());

    return (new PostResource($post))
        ->response()
        ->setStatusCode(201);
}

// Need a subset / safe extras:
$data = $request->safe()->only(['title', 'body']);
$data = $request->safe()->merge(['user_id' => $request->user()->id]);
```

**Anti-pattern:**

- `$request->validate([...])` inline in a 200-line controller (fat controller — extract to a Form Request, and push multi-model orchestration into a service/action class).
- Reading `$request->all()` / `$request->input('x')` **after** validation — re-admits keys validation deliberately dropped (mass-assignment vector).
- `Post::create($request->all())` — same hole, plus relies on `$fillable` as the only guard.

## Output — API Resources, never raw models

Returning an Eloquent model directly serialises **every** attribute (including ones you forgot to `$hidden`) and couples the API to the schema. A `JsonResource` makes the contract explicit.

```php
// php artisan make:resource PostResource
class PostResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'        => $this->id,
            'title'     => $this->title,
            'author'    => new UserResource($this->whenLoaded('author')),
            'tag_count' => $this->whenCounted('tags'),
            'created'   => $this->created_at->toIso8601String(),
        ];
    }
}

// Collections:
return PostResource::collection(Post::with('author')->paginate());
```

`whenLoaded()` / `whenCounted()` keep the Resource N+1-safe — they emit the relation only if it was eager-loaded, so the Resource never triggers a lazy query. Pair with [`EAGER_LOADING.md`](EAGER_LOADING.md).

## The 422 envelope

A failed Form Request auto-returns HTTP **422** with a JSON body when the request expects JSON (`Accept: application/json` or an `/api` route):

```json
{
  "message": "The title field is required.",
  "errors": { "title": ["The title field is required."] }
}
```

No try/catch needed — the framework throws `ValidationException` and the handler renders it. For web (non-JSON) requests the user is redirected back with errors flashed to the session.

## Reviewer grep

- `$request->all()` or `$request->input(` appearing *after* a `validate(` / inside a `store`/`update` body.
- `return $model;` / `return Model::...->get();` straight out of a controller (no Resource).
- `->validate([` inside a controller method (should be a Form Request).

## Version note

Form Requests, `safe()`, `whenLoaded`/`whenCounted`, and the 422 JSON envelope are stable across L9–L12. (L13 drift — re-verify the validation-exception response shape if targeting 13.)
