# LOCAL_DOCKER_DEV_GOTCHAS

Non-obvious traps when standing up a **local** Docker Compose dev stack for a web app (nginx + app-server + DB + cache). Each cost real debugging time and recurs across projects and machines. Deployment-to-prod gotchas live in the sibling references (`HARDENING.md`, `CICD.md`, `CONTAINER_DNS_NSS.md`); this file is the *local-dev-stack* counterpart.

---

## 1. The `.dev` TLD is HSTS-preloaded — never use it for an HTTP-only dev host

**Symptom**: you map `something.dev → 127.0.0.1` in `/etc/hosts`, point nginx at it, and `http://something.dev/` simply won't load in any browser — it silently becomes `https://`, and the dev stack (HTTP-only, no TLS listener) refuses the connection. `curl` works fine, which makes it look like an nginx/app problem when it's actually the browser.

**Cause**: the entire `.dev` gTLD (Google-owned) is in the **HSTS preload list** baked into Chrome, Firefox, Safari, and Edge. Every `.dev` host is force-upgraded to HTTPS before a request leaves the browser. `curl` ignores the preload list, so CLI tests pass while browser access fails — a confusing split signal.

**Fix**: use **`.test`** for local dev hostnames. It's reserved by RFC 6761 for testing, is **not** HSTS-preloaded, and serves over plain HTTP. `dev.app.test` instead of `dev.app.dev`. (`.localhost` is also reserved but resolves specially; `.test` behaves like a normal name via `/etc/hosts`.) Other non-preloaded options: `.example`, `.invalid` — but `.test` is the convention.

**Rule of thumb**: HTTP-only dev stack → `.test`. Only reach for `.dev` if you're also terminating TLS locally (self-signed cert + `:443` listener).

---

## 2. Single-file bind mounts go stale on inode swap — `--force-recreate`, not `restart`

**Symptom**: you edit a config file that's bind-mounted into a container as a *single file* (e.g. `./conf/nginx.conf:/etc/nginx/conf.d/default.conf:ro`), then reload/restart the service — and the container still serves the **old** content. `nginx -t` inside the container may even report a syntax error on a line that no longer exists in your host file, or the file appears truncated mid-line.

**Cause**: Docker single-**file** bind mounts bind to the file's **inode** at container-start time. Most editors save by writing a new temp file and `rename()`-ing it over the original — which allocates a **new inode**. The container's mount still points at the old (now-orphaned) inode, so it never sees the edit. (Directory bind mounts don't have this problem — they resolve names live.) `docker compose restart` does **not** fix it: restart reuses the same container with the same mount, same stale inode.

**Fix**: recreate the container so the mount re-resolves to the current inode:
```bash
docker compose up -d --force-recreate <service>
```

**Prevention**: prefer mounting the **directory** (`./conf:/etc/nginx/conf.d:ro`) over the single file when practical — directory mounts reflect host edits live. Verify what the container actually sees with `docker compose exec <svc> sh -c 'wc -l <path>; tail <path>'` before assuming a config bug; a line-count mismatch vs the host file is the tell.

---

## 3. `docker-credential-*` helper missing from PATH blocks even anonymous public pulls (macOS Docker Desktop)

**Symptom**: `docker compose build` / `pull` fails at `load metadata for docker.io/library/<image>` with `error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH`. Happens even for **public** images that need no auth.

**Cause**: `~/.docker/config.json` has `"credsStore": "desktop"`, so the Docker CLI invokes `docker-credential-desktop` for *every* registry interaction — but that helper binary isn't on the `PATH` of the shell running docker (common when docker is invoked outside Docker Desktop's own terminal, e.g. from an IDE-spawned shell or an agent harness). The CLI aborts before it even tries an anonymous pull. Docker Desktop is supposed to symlink the helper next to the `docker` binary in `/usr/local/bin`, but sometimes only `docker` itself gets linked.

**Fix** (durable, no global-config edit): symlink the helper into a dir already on PATH:
```bash
ln -s /Applications/Docker.app/Contents/Resources/bin/docker-credential-desktop \
      /usr/local/bin/docker-credential-desktop
```
**Alternatives**: prepend Docker's bin dir to PATH for the build (`PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH" docker compose build`), or remove `"credsStore": "desktop"` from `~/.docker/config.json` (works for public images but drops stored logins for private registries). The symlink is the least-invasive durable fix.

**Scope note**: this is a macOS-Docker-Desktop quirk; Linux hosts (incl. CI / VPS) don't hit it.

---

## 4. Dev reverse-proxy `default_server` + host-keyed config selection = silent prod-backend fallback

**Symptom / hazard**: a dev nginx vhost is `listen 80 default_server` and the app selects its DB/secret config from the request **Host** header (common in multi-tenant apps — e.g. the app derives a tenant key from the Host's first label and loads `.<key>.env`). When a request arrives with an *unexpected* Host (a bare IP, `localhost`, a stray probe), it still routes into the app because the vhost is the catch-all default. The app finds no matching tenant config and **falls back to a hardcoded production default** (a prod DB host literal, prod cache endpoint, etc.) — so a local dev stack can silently connect to **production infrastructure**. The footgun is invisible in normal use (the intended Host works) and only fires on the "wrong" Host.

**Fix**: in the dev proxy, reject any Host that isn't the intended dev hostname instead of letting it fall through:
```nginx
# catch-all: drop unknown Hosts (fail-safe, no prod fallback)
server {
    listen 80 default_server;
    server_name _;
    return 444;            # connection closed, no response
}
# the real dev vhost — only the intended host reaches the app
server {
    listen 80;
    server_name dev.app.test;
    # ... app config ...
}
```
Crucially, **do not** list convenience aliases like `localhost` in the app vhost's `server_name` if they don't map to a valid dev config — they'd hit the same prod-fallback. Drop them; `444` on an unknown Host is a fail-safe (connection reset) rather than a silent prod connection.

**Reviewer heuristic**: whenever a dev/staging proxy is a `default_server` AND the app behind it derives backend/secret selection from the Host header, check what an unmatched Host does. If the answer is "loads a hardcoded production default," that's a prod-data footgun — require a Host allowlist + reject-unknown. The deeper root cause (a prod literal as the *default* in app config) is usually pre-existing app code and out of scope for a dev-env PR, but the proxy guard closes the practical exposure.

---

**Provenance**: surfaced standing up a Dockerized local dev stack for a legacy PHP / Zend Framework 1 app (IDEA-002, 2026-06). Gotchas 1, 2, 4 surfaced during build + GitHub Copilot review; 3 during the first `docker compose build`.

**Last Updated**: 2026-06-01
