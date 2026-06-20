# nginx redirect vhosts + Let's Encrypt on a busy reverse proxy

Patterns for standing up a redirect / cert change on an nginx host that already serves
many vhosts, applied via the maintenance-script contract (DRY-RUN/`--apply`/`--verify`/
`--rollback`). The general machinery — poll-the-served-effect, exact-token locate,
detect-the-renewer-variant, filter the warning flood — lives in
[`../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md`](../../shell/references/MAINTENANCE_SCRIPT_CONTRACT.md);
this file is the nginx/TLS specifics.

## Discover whether the target vhost even exists — additive vs replace

Don't assume the site you're changing has a dedicated vhost. On a busy proxy the apex
(`example.com` / `www.example.com`) is frequently served by **fallthrough**, not a
named block:

- `http://` → the `:80 default_server` (e.g. a stock `sites-enabled/default`).
- `https://` → the **first** `listen 443 ssl` block in config-load order, when there is
  no `:443 default_server`. That block presents *its own* cert for an unmatched SNI —
  which is why visitors to the apex see a cert for some *other* tenant (often long
  expired). That mismatched/expired default cert **is not yours**: don't back it up,
  rotate it, or delete it.

So the change is usually **additive**, not a replacement: there's no apex vhost to
edit or disable — you *add* a dedicated one. Verify with an exact-token `server_name`
search (see the contract's "Locate by exact token" — `\bexample\.com\b` false-matches
`sub.example.com`). If a real apex vhost *does* unexpectedly exist, refuse and re-assess
rather than stomping it.

## How an additive vhost wins — server_name + SNI precedence

You don't disable anything. nginx selects a server by matching the request `Host`
(and the TLS **SNI** on `:443`) against `server_name` **before** falling back to
`default_server` / the first-`ssl` block. So a new block with an explicit
`server_name example.com www.example.com`:

- wins `:80` for those names over the `default_server`, and
- wins `:443` for those SNIs over the first-`ssl` block's cert.

No `server_name` collision with the hundreds of existing tenant vhosts (they match
their own names). The `--verify` served-cert probe is what *proves* SNI is actually
winning — confirm the served `notAfter` is the **new** cert, not the old default
(poll it; see the contract — a graceful reload drains slowly on a many-vhost host).

## Two-phase write: `:80` (+ACME) → issue → append `:443`

A `:443` server block references `ssl_certificate /etc/letsencrypt/live/<name>/...`,
which **does not exist until the cert is issued**. Writing the full block before
issuance fails `nginx -t` (cannot load cert) and aborts the first-ever `--apply`. Order:

1. Write the **`:80`-only** redirect+ACME vhost; `nginx -t && reload`. Our explicit
   `server_name` wins the http-01 challenge.
2. `certbot certonly --webroot -w <acme-root> -d example.com -d www.example.com
   --deploy-hook 'systemctl reload nginx' --non-interactive --keep-until-expiring --expand`.
   **If issuance fails, STOP** — nothing else changed; the old default still serves `:443`.
3. **Append** the `:443` block (now the `live/` path exists); `nginx -t && reload`.
4. Served-cert probe (poll). Only then decommission anything that was genuinely yours.

`--rollback` for the additive case is symmetric and minimal: remove the vhost you added
(symlink + `sites-available` file), `nginx -t && reload` → reverts to the prior
`default_server`/first-`ssl` fallthrough. There's no prior vhost or cert to "restore."

## ACME challenge must be served by a more-specific location than the redirect

A redirect vhost that swallows `/.well-known/acme-challenge/...` with a 301 will fail
the http-01 challenge and **issuance/renewal fails**. Keep the redirect as a *prefix*
`location /` and the ACME exemption as a more-specific prefix:

```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    location /.well-known/acme-challenge/ { root /var/www/acme; }   # longest-prefix wins
    location / { return 301 https://target.example/; }
}
```

Note the mechanism: nginx picks the **longest matching prefix** location *regardless of
file order*, so `/.well-known/acme-challenge/` already beats `/` for a challenge request
even if `location /` is written first — source order only decides precedence among
**regex** (`~`) locations. So the real ways to break this aren't reordering these two
blocks; they're (a) a `return 301` at the **server** level (outside any `location`,
which applies to every request including the challenge), or (b) a *regex* catch-all
(`location ~ /`) that outranks the prefix ACME block. Avoid both; keep the redirect a
plain prefix `location /`.

This is **not** a one-time concern: certbot *renews* roughly every 60 days (the timer
fires twice daily; an actual issuance happens once the cert is inside its 30-day-to-expiry
window), re-running the same webroot challenge each time — so the exemption is a
*standing* precondition. A later "cleanup" that removes it silently breaks renewal ~60
days on. Assert the exemption is present and reachable in DRY-RUN, and let cert-expiry
monitoring (it exists precisely because this path is fragile) catch a missed renewal at
the <21d/<7d thresholds.

## Renewal mechanism varies by install

Apt certbot ships `certbot.timer`; the **snap** ships `snap.certbot.renew.timer`; older
setups use `/etc/cron.d/certbot`. A `--verify`/`(g)` step that only checks `certbot.timer`
false-reports "renewal not scheduled" on a snap host. Detect any variant — see the
contract's "Detect the mechanism; don't hardcode one variant."
