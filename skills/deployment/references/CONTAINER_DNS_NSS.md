# Container DNS / NSS Resolution Gotchas

Reference for anything where "what does the public internet see for this name?" is load-bearing — cert issuance (ACME HTTP-01/DNS-01), domain allowlists, webhook URL validation, multi-tenant domain routing, external service discovery. Inside Docker containers, NSS-based lookups (`getaddrinfo`, `gethostbyname`, `getent hosts`) can silently shadow public DNS and return answers that the public internet doesn't.

**When to consult this reference:** deploy or debug a production app that does any form of domain validation against a name the container expects to reach over the public internet. Especially: fresh-VPS bootstrap, any `sync_domains`-style gate that filters by `getaddrinfo`, any cert-issuance failure that's HTTP-01-clean but HTTPS-broken.

## The general principle

Inside a container, the DNS resolution path is **not** public DNS. Three distinct layers can intercept a name lookup *before* the public resolver ever sees it:

1. **`/etc/hosts`** — usually inherited from the image, but on some runtimes (Compose, K8s, `--add-host`) can be augmented at container start. Exact-match wins over every other mechanism.
2. **NSS modules** named in `/etc/nsswitch.conf` — typically `files` (hosts file), `myhostname` (returns loopback for the local hostname), `mdns`, then `dns`. `files` and `myhostname` run *before* `dns` and can return early with an address that has nothing to do with public DNS.
3. **Docker's embedded resolver at 127.0.0.11** — injected into every container on user-defined networks. Resolves container names, service aliases, and forwards everything else upstream. Has its own cache and failover behaviour.

Only after all three pass the name through does the query reach whatever's in the container's `/etc/resolv.conf` (the host's configured resolver, or a Docker-injected one).

**Consequence**: `getaddrinfo("yourdomain.com")` inside a container can return `127.0.1.1` or `127.0.0.1` or any other answer that a clever NSS module fabricated, with zero signal that the public internet disagrees.

## Fix recipe — always query public DNS explicitly

When the business logic needs the **public-internet answer** for a name, bypass NSS entirely and query an authoritative public resolver:

```python
# Python — dnspython, not socket.getaddrinfo
import dns.resolver

resolver = dns.resolver.Resolver(configure=False)
resolver.nameservers = ["1.1.1.1", "8.8.8.8"]   # explicit, not system
answers = resolver.resolve(domain, "A")
public_ips = [a.address for a in answers]
```

```bash
# Shell — dig at a specific resolver, not getent/nslookup
dig @1.1.1.1 +short +time=2 +tries=1 "$DOMAIN" A
```

Never use `socket.getaddrinfo` / `getent hosts` / `gethostbyname` when the decision depends on the public view. Those are correct for "how does my app reach this service *from here*", but wrong for "what does the outside world see?".

### Preflight: refuse to deploy if NSS is already lying

Add a preflight check to deploy scripts that fails fast when NSS for `$DOMAIN` returns a loopback:

```bash
if getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | grep -qE '^127\.'; then
    echo "❌ NSS returns loopback for $DOMAIN on this host — fix /etc/hosts or hostname before deploying" >&2
    echo "   Run: getent hosts $DOMAIN" >&2
    exit 1
fi
```

This catches the failure at deploy time (loud, early, fixable) instead of six hours later when the cert renewal cron fails (quiet, late, mysterious).

## Anchor case study — Debian fresh-VPS `sync_domains` silent drop

**Scenario.** Fresh Debian VPS, hostname set to `app.example.com` (matching the production domain). Django multi-tenant app has a `sync_domains` management command that runs at bootstrap; it iterates candidate domains and filters out any whose `getaddrinfo` answer "doesn't look public". `app.example.com` gets filtered out. Nginx provisions HTTP-only vhosts (ACME HTTP-01 succeeds because it's nginx-relative, not DNS-based). Certbot runs, issues the cert, nginx reloads. Everything looks green.

Hours later, HTTPS requests to `app.example.com` 502 or serve the default vhost — there's no HTTPS server block for the production domain.

**Root cause.**

1. The Debian installer, when the hostname matches a real domain, appends `127.0.1.1 app.example.com app` to `/etc/hosts`. That's Debian's long-standing convention for making `hostname -f` work offline.
2. Every container the app launches inherits the host's NSS config: `files myhostname dns` in `/etc/nsswitch.conf`.
3. The app container's `getaddrinfo("app.example.com")` hits `files` first, matches the `127.0.1.1` entry, returns immediately without ever asking DNS. Loopback.
4. `sync_domains` sees loopback, classifies as non-public, silently skips the domain.
5. Nginx gets no HTTPS vhost for `app.example.com` — only the HTTP-01 challenge vhost (which is sufficient for ACME but not for serving traffic).
6. The cert exists on disk. It's just not bound to anything.

HTTP-01 ACME works throughout because certbot doesn't use the app's `sync_domains` logic — it uses the `/.well-known/acme-challenge/` path on whatever vhost nginx serves for the IP:80 request. That's why everything looks green at deploy time.

**Three independent fixes (belt, braces, trousers — apply all three):**

1. **Make `sync_domains` query public DNS directly**, not NSS. dnspython + 1.1.1.1/8.8.8.8 as shown above. This is the durable fix.
2. **Add the deploy preflight** that refuses when `getent hosts $DOMAIN` returns loopback. Catches this class of misconfiguration before any app code runs.
3. **Change the machine hostname** so it doesn't collide with a real domain. The convention `debian-app-01.internal` (or similar) keeps `hostname -f` useful without hijacking public-DNS names. This is the cleanest but often the hardest to retrofit.

**Validated in:** teisutis IDEA-120 (2026-04-21) — fresh Debian 12 VPS, production domain also used as machine hostname, `sync_domains` NSS shadow dropped the production entry, HTTPS vhost missing after nominally-successful bootstrap.

## Related references

- [`../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md`](../../sprint-auto/references/PARALLEL_WORKTREE_DOCKER.md) — adjacent Docker-networking gotchas (port / subnet / ipv4 collisions when running multiple stacks). Points here for the DNS/NSS layer.
- [`DJANGO_DEPLOYMENT.md`](DJANGO_DEPLOYMENT.md) — Django-specific deploy concerns; any Django project using domain allowlists or ALLOWED_HOSTS gates should consult this file too.
- [`HARDENING.md`](HARDENING.md) — server hardening is the natural place to codify the "machine hostname should not match production domain" convention.
