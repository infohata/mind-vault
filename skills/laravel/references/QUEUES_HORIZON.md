# Queues & Horizon — deferred work

Any work over ~300ms (email, external HTTP, image/video processing, report generation, webhooks-out) is decoupled into a queued job so the request returns fast. The Laravel idiom is `ShouldQueue` jobs on **Redis**, supervised by **Horizon**.

## Mechanism — a queued job

```php
// php artisan make:job ProcessPodcast
class ProcessPodcast implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;
    public int $backoff = 10;   // seconds between retries

    // Pass an ID, NOT the model — re-fetch fresh inside handle().
    public function __construct(public int $podcastId) {}

    public function handle(): void
    {
        $podcast = Podcast::findOrFail($this->podcastId);
        // ... heavy work ...
    }

    // Optional: cap how long a single attempt may run.
    public int $timeout = 120;
}
```

**Why IDs not models:** Laravel's `SerializesModels` snapshots the model into the payload. By the time the worker runs, that snapshot is stale; re-fetching by ID inside `handle()` always sees current state and shrinks the payload.

## Dispatch — and the `afterCommit` rule

```php
ProcessPodcast::dispatch($podcast->id);                 // default queue
ProcessPodcast::dispatch($podcast->id)->onQueue('media');
ProcessPodcast::dispatch($podcast->id)->delay(now()->addMinutes(5));

// CRITICAL inside a DB transaction:
DB::transaction(function () use ($data) {
    $podcast = Podcast::create($data);
    // ✅ worker only picks this up AFTER the tx commits — no race on the new row.
    ProcessPodcast::dispatch($podcast->id)->afterCommit();
});
```

Set `after_commit => true` on the queue connection in `config/queue.php` to make `afterCommit` the default for every dispatch.

### Chains and batches

```php
use Illuminate\Support\Facades\Bus;

// Sequential — each runs only if the prior succeeded.
Bus::chain([
    new OptimizeAudio($id),
    new Transcribe($id),
    new Publish($id),
])->dispatch();

// Parallel fan-out with a completion callback.
Bus::batch([new ImportChunk($a), new ImportChunk($b)])
    ->then(fn () => Log::info('import done'))
    ->dispatch();
```

## Idempotency — never double-run

```php
// Dedupe queued copies: only one ProcessPodcast for this id may be queued at once.
class ProcessPodcast implements ShouldQueue, ShouldBeUnique
{
    use Queueable;
    public function uniqueId(): string { return (string) $this->podcastId; }
    public int $uniqueFor = 3600; // lock TTL seconds
}

// OR serialise execution by key (allows queueing, prevents overlap):
public function middleware(): array
{
    return [(new WithoutOverlapping($this->podcastId))->releaseAfter(60)];
}
```

`ShouldBeUnique` prevents *duplicate enqueue*; `WithoutOverlapping` prevents *concurrent execution*. Pick per failure mode — retries and at-least-once delivery mean a job WILL occasionally run twice, so the handler should be idempotent regardless.

## Horizon — the supervised default

Horizon is the dashboard + Supervisor-style process manager for Redis queues:

```php
// config/horizon.php — environments → supervisors → worker pools
'production' => [
    'supervisor-1' => [
        'connection' => 'redis',
        'queue'      => ['default', 'media'],
        'balance'    => 'auto',
        'maxProcesses' => 10,
        'tries'      => 3,
    ],
],
```

```bash
php artisan horizon            # start the supervisor (run under systemd/Supervisor)
php artisan horizon:terminate  # graceful restart after a deploy
```

**Anti-pattern to flag:**

- Dispatching inside a transaction **without** `afterCommit` — the worker grabs the job before the row commits and `findOrFail` 404s intermittently.
- `php artisan queue:listen` or a bare `queue:work` in prod with no process supervisor — it dies silently (fatal, deploy, OOM) and the queue stalls with no alert. Use Horizon (or Supervisor + `queue:work`).
- Serializing a whole model into the constructor — stale snapshot + bloated Redis payload. IDs only.

## Version note

`database` is the default queue connection on a fresh L11/L12 install (was `sync`); set `QUEUE_CONNECTION=redis` for Horizon. `ShouldBeUnique`, `WithoutOverlapping`, `Bus::batch`, and `afterCommit` are stable across L9–L12. (L13 drift — re-verify the default queue connection if targeting 13.)
