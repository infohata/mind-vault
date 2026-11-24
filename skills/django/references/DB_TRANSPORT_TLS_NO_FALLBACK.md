# Encrypted DB and Redis connections that never fall back

PostgreSQL and Redis connections outside dev/test are encrypted and verified, or they do not happen. Five layers enforce this. Each catches a path the others miss.

## Why the defaults are not enough

Measured on PostgreSQL 17 with psycopg 3.3 (libpq):

| Client setting                                | Server                         | Result                                                               |
| --------------------------------------------- | ------------------------------ | -------------------------------------------------------------------- |
| none (libpq default `sslmode=prefer`)         | plaintext only                 | **connects in plaintext**, no warning; `pg_stat_ssl.ssl = false`     |
| `sslmode=require`, no CA file, wrong hostname | TLS, cert for another name     | **connects**: `require` encrypts but never checks the certificate    |
| `sslmode=verify-full` + CA                    | TLS, cert for another name     | refused: `server certificate for "db.test" does not match host name` |
| `sslmode=verify-full` + CA                    | plaintext only                 | refused: `server does not support SSL, but SSL was required`         |
| `sslmode=disable`                             | `hostnossl … reject` in pg_hba | refused: `pg_hba.conf rejects connection`                            |

If a root CA file is present, libpq treats `require` like `verify-ca`. That is still no hostname check, and it depends on a file that may or may not be there.

Redis has the same trap in a different place. redis-py lets **URL query options override the client's own kwargs**. Measured on redis-py 8.2: `ConnectionPool.from_url("rediss://h/0?ssl_cert_reqs=none&ssl_check_hostname=false", ssl_cert_reqs="required", ssl_check_hostname=True)` ends up with `ssl_cert_reqs='none'` and `ssl_check_hostname=False`. One env-var edit turns verification off, whatever the code says.

The source incident: a review of a multi-tenant Django core found one Redis URL setting that skipped the check the broker URL had. The validator below walks every setting for that reason.

## The rule

|                                            | Allowed outside dev/test                       | Refused                                                                           |
| ------------------------------------------ | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| PostgreSQL                                 | `sslmode=verify-full` (+ `sslrootcert`)        | unset, `disable`, `allow`, `prefer`, `require`, `verify-ca`                       |
| Redis                                      | `rediss://` with certificate + hostname checks | unset, `redis://`, `unix://`                                                      |
| Redis query options, **every environment** | `ssl_cert_reqs=required`                       | `ssl_cert_reqs=none/optional/CERT_NONE/CERT_OPTIONAL`, `ssl_check_hostname=false` |

- **An unset value is refused, never defaulted.** `os.environ.get("REDIS_URL", "redis://redis:6379/1")` is a plaintext fallback.
- **An unset environment name counts as production.** A container started without `APP_ENV` gets the strict rules.
- **Error messages name the setting, never the URL.** The URL carries the password.

Version notes (observed, not gated): on redis-py 8.2, `rediss://` checks the certificate and the hostname by default. redis-py 5.2.1 checks the certificate but defaults `ssl_check_hostname=False`, so on old clients set it explicitly. Celery 5.7's Redis result backend refuses a `rediss://` URL without `ssl_cert_reqs` (ValueError), but it only **logs a warning** for `CERT_NONE`. Write `CELERY_RESULT_BACKEND = "rediss://…?ssl_cert_reqs=required"`.

## Layer 1 — the pooler / container entrypoint exits non-zero

```sh
#!/bin/sh
# docker/pgbouncer/entrypoint.sh
set -eu
case "${APP_ENV:-production}" in   # unset counts as production
  dev|test) ;;
  *)
    if [ "${SERVER_TLS_SSLMODE:-}" != verify-full ]; then
      echo "refusing to start: SERVER_TLS_SSLMODE must be verify-full outside dev/test" >&2
      exit 1
    fi ;;
esac
exec pgbouncer /etc/pgbouncer/pgbouncer.ini
```

PgBouncer has two legs: `server_tls_sslmode` covers pooler → PostgreSQL, and `client_tls_sslmode` plus the client cert/key cover app → pooler. Gate both. A container that refuses to start shows up in `docker ps` at once. A pooler that starts in plaintext shows up nowhere.

## Layer 2 — settings import raises `ImproperlyConfigured`

```python
# config/transport_tls.py
import os
from urllib.parse import parse_qs, urlsplit

from django.core.exceptions import ImproperlyConfigured

DEV_ENVS = frozenset({"dev", "test"})
# Query options that turn certificate or hostname checks off. Refused in every
# environment: redis-py lets URL options override the client's own kwargs.
REDIS_FORBIDDEN = {
    "ssl_cert_reqs": {"none", "optional", "cert_none", "cert_optional"},
    "ssl_check_hostname": {"false", "0", "no", "off"},
}


def environment():
    return os.environ.get("APP_ENV", "").strip().lower() or "production"  # unset counts as production


def check_pg_options(alias, options, env=None):
    env = env or environment()
    mode = (options or {}).get("sslmode")
    if env in DEV_ENVS:
        return
    if mode != "verify-full":  # unset -> libpq "prefer" -> silent plaintext fallback
        raise ImproperlyConfigured(
            f"DATABASES[{alias!r}] OPTIONS sslmode={mode!r}: only 'verify-full' is allowed in {env!r}"
        )


def check_redis_url(setting, url, env=None):
    env = env or environment()
    if not url:
        raise ImproperlyConfigured(f"{setting} is unset")  # never fall back to a default
    parts = urlsplit(url)
    query = {k.lower(): [v.lower() for v in vs] for k, vs in parse_qs(parts.query).items()}
    for key, bad in REDIS_FORBIDDEN.items():
        if any(v in bad for v in query.get(key, [])):
            raise ImproperlyConfigured(f"{setting}: {key}= turns certificate checks off")
    if env not in DEV_ENVS and parts.scheme != "rediss":
        raise ImproperlyConfigured(f"{setting}: scheme {parts.scheme!r}, only 'rediss' is allowed in {env!r}")
    # Error messages name the setting, never the URL: it carries the password.


def redis_urls(settings_module):
    """Every str setting value that is a Redis URL, wherever it is nested."""
    found = []

    def walk(path, value):
        if isinstance(value, str) and value.lower().startswith(("redis://", "rediss://", "unix://")):
            found.append((path, value))
        elif isinstance(value, dict):
            for k, v in value.items():
                walk(f"{path}[{k!r}]", v)
        elif isinstance(value, (list, tuple)):
            for i, v in enumerate(value):
                walk(f"{path}[{i}]", v)

    for name in dir(settings_module):
        if not name.isupper():
            continue
        try:
            value = getattr(settings_module, name)
        except ImproperlyConfigured:  # LazySettings raises for e.g. an empty SECRET_KEY
            continue
        walk(name, value)
    return found


def validate_settings(settings_module, env=None):
    for alias, cfg in settings_module.DATABASES.items():
        if cfg.get("ENGINE", "").endswith("postgresql"):
            check_pg_options(alias, cfg.get("OPTIONS"), env)
    for path, url in redis_urls(settings_module):
        check_redis_url(path, url, env)
```

```python
# config/settings.py — last lines
import sys

from config.transport_tls import validate_settings

validate_settings(sys.modules[__name__])
```

**Check EVERY Redis URL, not the one you remembered.** A Django project usually has five: `CELERY_BROKER_URL`, `CELERY_RESULT_BACKEND`, `CACHES[*]["LOCATION"]`, `CHANNEL_LAYERS[*]["CONFIG"]["hosts"]`, and any app-level client such as `redis.Redis.from_url(settings.RATE_LIMIT_REDIS_URL)`. `redis_urls()` walks every uppercase setting, nested dicts and lists included, so a sixth one added next year is covered. A URL built in code never reaches settings, so grep for that class too:

```bash
grep -rnE "rediss?://|from_url\(|StrictRedis\(|Redis\(" --include='*.py' . | grep -v '/tests/'
```

**DB aliases added at runtime are the path most likely to slip.** A DB-per-tenant router that registers `connections.settings[alias] = {...}` after startup never goes through settings import. Every code path that builds a `DATABASES` entry calls the same gate before the entry is used:

```python
from django.db import connections

from config.transport_tls import check_pg_options


def register_tenant_alias(alias, db_name):
    cfg = {**connections.settings["template"], "NAME": db_name}  # inherits the vetted OPTIONS
    check_pg_options(alias, cfg.get("OPTIONS"))                  # same gate as settings import
    connections.settings[alias] = cfg
```

## Layer 3 — a Django system check, plus the healthcheck

```python
# config/checks.py — import it from an AppConfig.ready()
from django.conf import settings
from django.core.checks import Error, Tags, register
from django.core.exceptions import ImproperlyConfigured
from django.db import connections

from config.transport_tls import check_pg_options, check_redis_url, redis_urls


@register(Tags.security)
def transport_tls(app_configs, **kwargs):
    errors = []
    for alias, cfg in connections.settings.items():  # includes aliases added at runtime
        if cfg.get("ENGINE", "").endswith("postgresql"):
            try:
                check_pg_options(alias, cfg.get("OPTIONS"))
            except ImproperlyConfigured as exc:
                errors.append(Error(str(exc), id="transport.E001"))
    for path, url in redis_urls(settings):
        try:
            check_redis_url(path, url)
        except ImproperlyConfigured as exc:
            errors.append(Error(str(exc), id="transport.E002"))
    return errors
```

The check runs with the commands that run system checks (`runserver`, `migrate`, `check`). Run it as the container healthcheck too (`HEALTHCHECK CMD python manage.py check --fail-level ERROR`), so the environment inside the running image is checked, not the one on the developer's laptop. Tested on Django 6.1: with a runtime alias set to `sslmode=require` and `CELERY_RESULT_BACKEND="redis://…"`, the check reports `transport.E001` and `transport.E002`.

## Layer 4 — runtime proof on first connect

Layers 1–3 check what the config says. This one checks what the server says.

```python
# config/db_guard.py — import it from an AppConfig.ready()
from django.core.exceptions import ImproperlyConfigured
from django.db.backends.signals import connection_created
from django.dispatch import receiver

from config.transport_tls import DEV_ENVS, environment


@receiver(connection_created)
def require_tls_on_connect(sender, connection, **kwargs):
    if connection.vendor != "postgresql" or environment() in DEV_ENVS:
        return
    with connection.cursor() as cur:
        cur.execute("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")
        row = cur.fetchone()
    if not (row and row[0]):
        connection.close()
        raise ImproperlyConfigured(f"database alias {connection.alias!r} connected without TLS")
```

Tested on Django 6.1 against a plaintext-only server: the first query raises, and `connection.connection` is `None` afterwards, so nothing runs on the plaintext socket.

**Behind a pooler, `pg_stat_ssl` describes the pooler → PostgreSQL leg.** The app → pooler leg is invisible to it. That leg relies on layer 2 (`verify-full` against the pooler's certificate) and on the pooler's `client_tls_sslmode`.

## Layer 5 — the server refuses plaintext

```text
# pg_hba.conf — TLS or nothing
local      all  all                peer
hostssl    all  all  0.0.0.0/0     scram-sha-256
hostssl    all  all  ::/0          scram-sha-256
hostnossl  all  all  0.0.0.0/0     reject
hostnossl  all  all  ::/0          reject
```

Verify it from the system, not the file: `SELECT type, address, auth_method FROM pg_hba_file_rules` shows the rules the server loaded. From outside, `psql "host=<db-host> sslmode=disable …"` must fail with `pg_hba.conf rejects connection`. For Redis, the TLS-only server setting is `port 0` + `tls-port 6380` (plaintext listener off).

## Tests that must exist

| Test                                                                                                                                                    | Expect                                      |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| Each forbidden `sslmode` (unset, `disable`, `allow`, `prefer`, `require`, `verify-ca`) at settings import, in the system check, and for a runtime alias | `ImproperlyConfigured` / `transport.E001`   |
| `APP_ENV` unset + `sslmode=require`                                                                                                                     | refused (unset = production)                |
| Each Redis setting kind (broker, result backend, cache, Channels, app client) set to `redis://` or unset                                                | refused                                     |
| `?ssl_cert_reqs=none`, `?ssl_check_hostname=false`, with `APP_ENV=dev`                                                                                  | refused (every environment)                 |
| Error message text                                                                                                                                      | contains the setting name, not the password |
| Entrypoint with `SERVER_TLS_SSLMODE` unset / `require`                                                                                                  | exit 1                                      |
| `verify-full` against a plaintext-only server                                                                                                           | connection error, never a connection        |
| Bad or expired certificate, or hostname mismatch                                                                                                        | refused                                     |
| Runtime guard with the `pg_stat_ssl` query mocked to return `false`                                                                                     | raises and closes the connection            |

The hostname-mismatch test needs no DNS. libpq checks the certificate against `host` and connects to `hostaddr`: `host=wrong.test hostaddr=<server-ip> sslmode=verify-full sslrootcert=ca.crt`.

## Cost

Measured in the source project: the guard query costs about 0.8 ms per new connection, and a direct TLS 1.3 handshake about 7 ms. With `CONN_MAX_AGE = 600` that is once per connection lifetime and nothing to worry about. With `CONN_MAX_AGE = 0` behind a transaction pooler, every request opens a connection and pays both. Measure on your own hosts before you trade the guard away.

## DO / DON'T

✅ DO: `"OPTIONS": {"sslmode": "verify-full", "sslrootcert": os.environ["DB_SSLROOTCERT"]}` with the validator at the end of settings.
❌ DON'T: `"OPTIONS": {"sslmode": os.environ.get("DB_SSLMODE", "require")}`. A missing variable gives an unverified connection, and `require` against a hostile host still "works".

✅ DO: `CACHES = {"default": {..., "LOCATION": os.environ["CACHE_REDIS_URL"]}}`, so a missing variable is a `KeyError` at boot.
❌ DON'T: `os.environ.get("REDIS_URL", "redis://redis:6379/1")`. Production then runs on a plaintext default nobody chose.

✅ DO: validate every Redis URL setting by walking settings.
❌ DON'T: validate `CELERY_BROKER_URL` and assume the cache and Channels layer use the same URL. In the source incident, one of them didn't.

❌ DON'T: `raise ImproperlyConfigured(f"bad Redis URL {url}")`. The message goes to logs and error trackers with the password in it.
