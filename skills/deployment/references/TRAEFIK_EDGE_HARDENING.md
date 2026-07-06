# Traefik v3 edge hardening — dotfile-deny (404), `.well-known` carve-out, version-bump audit

Patterns for a **public Traefik v3 reverse-proxy edge** (file-provider dynamic config, central ACME):
block hostile recon at the edge, keep cert renewal alive, and upgrade the image without re-issuing the
prod cert. All native — **no third-party plugin** (an edge is the highest-exposure tier and takes no
plugin supply-chain surface) and **no on-box responder container**.

## 1. Return a true 404 for a path with NO plugin and NO backend

Traefik v3 core has **no "return fixed status" middleware**. The only primitive that emits a
configurable status by itself is **`ipAllowList` + `rejectStatusCode`** (default 403; settable to
**404 only in v3.5+** — absent v3.0–v3.4, where it silently stays 403). Combine it with a
high-priority catch-all router:

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
        rejectStatusCode: 404                  # v3.5+; without it you get 403
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
unnecessary at v3.5+.

## 2. The `.well-known` carve-out is load-bearing — never block cert renewal

`PathRegexp((?:^|/)\.)` matches **any** dot-prefixed segment, which **includes `/.well-known/`** — an
IANA-standard, legitimately-served prefix (`security.txt`, OIDC `/.well-known/openid-configuration`,
MTA-STS, and critically **`/.well-known/acme-challenge/`**). Blocking it:

- **breaks LE HTTP-01 cert RENEWAL** → the cert eventually **expires → edge down**. This is the
  highest-severity failure the guard can cause.
- 404s the discovery endpoints of any auth/OIDC backend, estate-wide.

**RE2 has no lookahead**, so `(?!well-known)` will *not compile*. The carve-out is a rule composition,
not a regex: **`PathRegexp(…) && !PathPrefix(`/.well-known/`)`**. Belt-and-suspenders: also keep the
deny router **`websecure`-only** while the ACME `httpChallenge` is served on the `web` (:80)
entrypoint — the challenge then never even reaches the guard. Gate on it in the verify script
(`/.well-known/security.txt` must NOT be 404; a bogus `/.well-known/acme-challenge/<x>` on :80 returns
the ACME handler's 404, not a redirect — a `301` there means HTTP-01 renewal is at risk).

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

Pairs with [ROOTLESS_DOCKER.md](ROOTLESS_DOCKER.md) (the daemon this edge usually runs on) and
[NGINX_TLS_REDIRECT_AND_CERTS.md](NGINX_TLS_REDIRECT_AND_CERTS.md) (the same ACME-challenge-must-stay-
reachable precondition, nginx flavor). Verify-script discipline:
[../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md).
