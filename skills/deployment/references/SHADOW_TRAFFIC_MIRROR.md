# Shadow traffic with nginx `mirror` — safe only per route

**Fires when** a cutover plan says "mirror live traffic to the new container while the old stack
keeps serving", or any time nginx's `mirror` directive is proposed as a no-risk test.

## A GET is not a read

A plan shadow-tested each app's new container by mirroring live traffic to it while the host's
PHP-FPM kept answering. A read of the code before the switch showed that many "read" endpoints
had side effects on GET: a reservation-create call carried guest data in about 60 path segments,
an invoice GET checked a guest in, and a price call could send mail. Mirroring those would have
run each side effect twice, once from the live app and once from the shadow, against the same
database and the same partners.

**A mirror is safe only for routes classified side-effect-free from the code, never from the HTTP
method.** So:

- **The mirror location denies by default.** Anything not on the reviewed safe list is answered
  `204` inside nginx and never reaches the shadow.
- **Where possible the shadow gets no write credentials**: a read-only database account, partner
  credentials blanked, mail pointed at a sink. Then a misclassified route fails instead of writing.
- **Compare per path shape, from both access logs**, using status and body size, with the pass
  thresholds written down before the run.
- **Queue workers cannot be shadowed.** Two consumers of one queue split the work, they don't
  duplicate it. A worker move is a cutover: stop the host program, start the container, and keep
  an instant restart of the host program as the rollback.
- **Doubled outbound calls count against partner rate limits**, even for safe routes that call out.

## The config, and what a lab run showed

```nginx
map "$request_method:$request_uri" $shadow_ok {   # $request_uri: the client's URI, query included
    default 0;
    "~^GET:/api/avail/[0-9]+(\?|$)" 1;            # one line per route proven side-effect-free
}
upstream live   { server 127.0.0.1:8081; }
upstream shadow { server 127.0.0.1:8082; }

server {
    log_subrequest on;               # off by default: the mirror subrequest is not logged at all
    location / {
        try_files $uri @app;
    }
    location @app {
        mirror /_shadow;             # HERE, in the location that serves; see the trap below
        mirror_request_body off;     # only while every safe route is bodyless
        proxy_pass http://live;
        proxy_set_header X-Request-Id $request_id;
    }
    location = /_shadow {
        internal;
        if ($shadow_ok = 0) { return 204; }
        proxy_pass http://shadow$request_uri;
        proxy_set_header X-Request-Id $request_id;
    }
}
```

Run on nginx 1.27.5 with a live and a shadow backend that log `$http_x_request_id`:

- **`mirror` next to `try_files … @app` mirrors only what `try_files` serves itself.** With the
  directive in `location /`, a static file was mirrored and every request that fell through to
  `@app` was not mirrored at all: the shadow log stayed empty while the plan believed it was
  shadowing the app. Put `mirror` in the location that finally serves the request (`@app`), or at
  server level. Either fired exactly once per request.
- **The deny-by-default gate works.** A POST to a listed path and a GET to an unlisted one were
  answered `204` in nginx (`upstream_addr` empty); only the listed GET reached the shadow.
- **`$request_id` is shared by a request and its mirror**, so passing it as `X-Request-Id` lets the
  two backends' logs be joined line for line.
- **With `log_subrequest on`, the mirror subrequest gets its own access-log line** (`$uri` is
  `/_shadow`, `$request_uri` is the client's) carrying `$upstream_addr` and `$upstream_status`.
  Without it, a dead shadow is invisible in nginx's logs.

Not measured in that run: whether a slow shadow delays the client. nginx is widely reported to
finish a request only after its mirror subrequests complete, so the next request on a keepalive
connection may wait.
Load the shadow before trusting the mirror on a latency-sensitive route.

Related: [DARK_DEPLOY_KILL_SWITCH.md](DARK_DEPLOY_KILL_SWITCH.md) (shadow inside the application:
observes, does not protect) · [CONFIG_STATES_INTENT.md](CONFIG_STATES_INTENT.md) (prove the
effect, here the shadow's own log, never the directive) ·
[`../../shell/references/VERIFY_DISCIPLINE.md`](../../shell/references/VERIFY_DISCIPLINE.md).
