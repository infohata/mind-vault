# Traefik v3 edge hardening — dotfile-deny (404), `.well-known` carve-out, version-bump audit

Patterns for a **public Traefik v3 reverse-proxy edge** (file-provider dynamic config, central ACME):
block hostile recon at the edge, keep cert renewal alive, and upgrade the image without re-issuing the
prod cert. All native — **no third-party plugin** (an edge is the highest-exposure tier and takes no
plugin supply-chain surface) and **no on-box responder container**.

## 1. Return a true 404 for a path with NO plugin and NO backend

Traefik v3 core has **no "return fixed status" middleware**. The only primitive that emits a
configurable status by itself is **`ipAllowList` + `rejectStatusCode`** (default 403; in core since
**v3.0** — but **undocumented until late-v3.x doc pages**, so its absence from an older version's
docs does NOT mean unsupported). Combine it with a high-priority catch-all router:

```yaml
http:
  routers:
    block-dotfiles:
      # default router priority = RULE LENGTH, so a long Host(`…`) rule outranks a short path rule and
      # would FORWARD /.env. The explicit high priority is REQUIRED — don't "simplify" it away.
      priority: 10000
      rule: 'PathRegexp(`(?:^|/)\.`) && !PathPrefix(`/.well-known/`)'   # any dotfile segment, except /.well-known/
      entryPoints: [websecure]
      middlewares: [deny-404]
      service: noop            # never reached — deny-404 short-circuits before the service
      tls: {}                  # websecure router: cert selected by SNI from the shared store
  middlewares:
    deny-404:
      ipAllowList:
        sourceRange: ["255.255.255.255/32"]   # a sentinel range no real client can match → every request rejected
        rejectStatusCode: 404                  # omit → 403 (option is in core since v3.0)
  services:
    noop:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:1"   # dummy, never dialed — see § noop below
```

The `ipAllowList` middleware **short-circuits before the service is invoked**, so the request never
reaches `noop`; the sentinel `sourceRange` guarantees every request to this router is "rejected" with
the configured status. One high-priority catch-all router protects **every** route (current and
future) with no per-route opt-in — better than negating dotfiles in each real router's rule (a
forgotten negation silently exposes that route).

**Alternatives and why they lose:** an `ipAllowList` gives **403** by default (fine if you don't need
404); routing to a **zero-server service gives 503**, an unreachable server gives **502** — neither is
a 404. A static-responder container (nginx `return 404;`) works but adds image surface to the edge —
unnecessary on any v3.

## 2. The `.well-known` carve-out is load-bearing — never block cert renewal

``PathRegexp(`(?:^|/)\.`)`` matches **any** dot-prefixed segment, which **includes `/.well-known/`** — an
IANA-standard, legitimately-served prefix (`security.txt`, OIDC `/.well-known/openid-configuration`,
MTA-STS, and critically **`/.well-known/acme-challenge/`**). Blocking it:

- **breaks LE HTTP-01 cert RENEWAL** → the cert eventually **expires → edge down**. This is the
  highest-severity failure the guard can cause.
- 404s the discovery endpoints of any auth/OIDC backend, estate-wide.

**RE2 has no lookahead**, so `(?!well-known)` will *not compile*. The carve-out is a rule composition,
not a regex: **``PathRegexp(…) && !PathPrefix(`/.well-known/`)``**. Belt-and-suspenders: also keep the
deny router **`websecure`-only** while the ACME `httpChallenge` is served on the `web` (:80)
entrypoint — the challenge then never even reaches the guard. Gate on it in the verify script
(`/.well-known/security.txt` must NOT be 404; a bogus `/.well-known/acme-challenge/<x>` on :80 returns
the ACME handler's 404, not a redirect — a `301` there means HTTP-01 renewal is at risk).

> ⚠ The carve-out only protects the **inbound** challenge path. Renewal also needs **outbound** egress
> from the proxy container to the CA API — invisible to every inbound test, and not exercised until
> ~30 days pre-expiry, so a host-network change (e.g. a rootless net-stack swap) that breaks egress
> passes all smoke tests and expires the cert weeks later. After **any** host-network change, actively
> probe egress from inside the container
> (`docker exec <proxy> wget -qO- https://acme-v02.api.letsencrypt.org/directory`) and gate on it. See
> [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) § *Verify BOTH directions*.

## 3. `noop` needs a dummy unreachable server, not zero servers (fail CLOSED)

The deny router's `service` is never dialed (the middleware short-circuits), so it's a schema-satisfier
— but give it **one dummy unreachable server** (`http://127.0.0.1:1`), not an empty `servers: []`. A
zero-server service risks being **pruned at load**, which drops the guard router → dotfiles fall
through to the backend → the guard fails **OPEN**. A dummy server guarantees the router loads. Verify
the router is actually present (`/api/http/routers`), not just that `/.env` returns 404 (an absent
guard + a Host-with-no-fallback also 404s — same symptom, opposite cause).

## 4. Rate-limit: omit `sourceCriterion` on a direct edge

`rateLimit{average, period(default 1s), burst}`. On a **direct** edge that terminates TLS itself, OMIT
`sourceCriterion` — the default groups by the real client `RemoteAddr`. **Never set `ipStrategy.depth
> 0`** here: that trusts a client-spoofable `X-Forwarded-For` and lets attackers evade the per-IP
limit. Attach it **per-router** (a rate-limit *value* is backend-specific; an entrypoint-default
middleware can't be removed per-router). ⚠ Under **rootless Docker** the per-IP intent is defeated by
source-IP masquerading — see [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) § source-IP.

**Set the value LOOSE, and know what it does NOT defend.** A per-IP rate-limit only caps a *single
runaway IP* — a scraper, a broken client in a retry storm. It is **not** distributed-DDoS defense: a
botnet of N addresses each sending ~1/s sails under **any** per-IP cap (300k IPs × 1/s = 300k/s, every
bucket legal). So a *tight* value buys ~zero DDoS benefit and carries real downside — one legitimate
asset-heavy page (a picker pulling 200+ flags/icons in a burst) trips a low `burst` and 429s a real
user. Size `burst` to comfortably clear your heaviest single-page fan-out and `average` to a human's
sustained rate (thousands, not tens); lean generous. Distributed volumetric attacks are an
upstream/network-tier problem (anycast scrubbing, SYN cookies, connection limits), not something a
per-client L7 counter can solve — don't crank this knob pretending it's the mitigation.

## 5. Version-bump audit drill (before changing the `traefik:` tag)

A public edge holds a real prod cert in a persistent `acme.json` volume — an upgrade must not lose it.

- **Target the latest stable minor.** Traefik supports **only the last minor**; older minors are EOL,
  so **down-pinning for "caution" is *less* safe**, not more. Confirm the tag is GA (not RC).
- **Read the cumulative migration guide** (`doc.traefik.io/traefik/v<TARGET>/migrate/v3/`) end to end.
  The load-bearing check is the **`acme.json` on-disk format**: if it hasn't changed across the jumped
  minors, v-new reads a v-old store and **loads the cert without re-issuing** (re-issue burns the
  ~50/week/domain prod-LE quota). (Empirically stable across v3.4–v3.7.)
- **File-provider edges ignore Docker-provider migration notes** (e.g. a Docker-API floor bump doesn't
  apply when you route via the file provider).
- **Behavioral win:** v3.4.1 moved request-path **normalization pre-routing** — `%2E` decodes to `.`
  *before* rule matching, so an encoded-dot (`/%2Eenv`) can't bypass the dotfile guard. Gate on it.
- **Deploy safely:** back up `acme.json` off-box first; make "cert **reused** (issuer prod, `notBefore`
  unchanged)" the **first** post-deploy gate; state an explicit rollback (pin the prior tag + restore
  `acme.json`). Rollback that edits config = a change → follow the **reviewed** path (revert PR → FF
  the deploy branch), with a labeled break-glass exception for an edge that's down.

## 6. A programmatically-rendered dynamic file must emit `{}` when empty — never the populated-but-empty struct

When a sidecar renders a file-provider fragment (rendering routes from a store), the **empty** case is a
landmine. Traefik's file provider **rejects** a document that declares the containers but leaves them
empty —

```json
{"http": {"routers": {}, "services": {}}}
```

— with `routers cannot be a standalone element (type map[string]*dynamic.Router)`, and it does **not**
fail just that fragment: it **aborts the ENTIRE dynamic-config build**. Every `@file` router across all
watched files — the infra routers, the dotfile guard, TLS options, *everything* — vanishes at once. A
renderer that serialises its (empty) typed struct produces exactly this poison the first time its store
is empty, and takes the whole edge down estate-wide.

The accepted "no-op config" forms are a **bare `{}`**, `{"http": null}`, a comment (YAML/TOML
fragments only — JSON has none), or an absent file — NOT the populated-but-empty struct. Guard it at
the top of the renderer:

```go
if len(entries) == 0 {
    return []byte("{}\n"), nil   // NOT a marshalled empty {http:{routers:{},services:{}}}
}
```

Because routers and services grow together (a renderer emits both or neither), the one `len == 0` guard
covers the only bad case. This is a different silent-outage trap from the delivery-mount traps in
[CONTAINER_SINGLE_FILE_MOUNT.md](CONTAINER_SINGLE_FILE_MOUNT.md) but lives in the same render-and-deliver
pipeline — a rendered fragment can blackhole the whole reload, so **commit the render only after Traefik
reflects it** (poll `/api/http/routers` for the expected name) and roll back otherwise.

Pairs with [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) (the daemon this edge usually runs on),
[CONTAINER_SINGLE_FILE_MOUNT.md](CONTAINER_SINGLE_FILE_MOUNT.md) (delivering the rendered fragment
without silent staleness — the other half of §6's pipeline) and
[NGINX_TLS_REDIRECT_AND_CERTS.md](NGINX_TLS_REDIRECT_AND_CERTS.md) (the same
ACME-challenge-must-stay-reachable precondition, nginx flavor). Verify-script discipline:
[../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md).
