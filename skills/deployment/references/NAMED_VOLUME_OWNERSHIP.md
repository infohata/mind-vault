# Named-volume ownership initialization

When a Docker Compose service runs as a non-root user AND mounts a named volume at a path that **does not already exist in the image**, the volume initialises root-owned and the container user can't write to it. The first write attempt (`collectstatic`, file upload, log emit) fails with `PermissionError: [Errno 13] Permission denied`. The symptom looks like a Docker bug; the cause is image build order.

## The trap

Docker's named-volume initialization rule: when a service mounts a named volume to a path that **exists in the image**, Docker copies that path's content (and ownership/permissions) into the empty volume on first mount. When the path **doesn't exist in the image**, the volume initialises empty and root-owned.

A typical Django Dockerfile chowns `/app` recursively to the non-root user *before* anything has populated `/app/staticfiles/` or `/app/media/`:

```dockerfile
WORKDIR /app
COPY requirements.txt /app/
RUN pip install -r requirements.txt
RUN useradd --uid ${UID} app && chown -R app:app /app   # <-- /app/staticfiles doesn't exist here
USER app
```

Then `compose.yml` mounts named volumes on top of paths the image never created:

```yaml
services:
  web:
    volumes:
      - static_data:/app/staticfiles
      - media_data:/app/media
volumes:
  static_data:
  media_data:
```

First run:
- Docker initialises `static_data` empty + root-owned (because `/app/staticfiles` didn't exist in the image to copy ownership from).
- Container starts, app user runs `python manage.py collectstatic`.
- Fails: `PermissionError: [Errno 13] Permission denied: '/app/staticfiles/admin'`.

The error is invisible until the first write — the stack starts healthy, the smoke test (which doesn't write) passes, and only `collectstatic` (or a file upload, or a log write to a volume-mounted path) trips the trap.

## The fix

`mkdir -p` the volume mount points in the image *before* the recursive chown, so Docker has correctly-owned image paths to copy into the volume:

```dockerfile
RUN useradd --create-home --shell /bin/bash --uid ${UID} app \
    && mkdir -p /app/staticfiles /app/media \
    && chown -R app:app /app
USER app
```

On next `docker compose up`, Docker copies the (now-existing, app-owned) image paths into the empty named volumes, preserving ownership.

## When fixing on an existing stack

The fix only takes effect for **freshly-initialised volumes**. If the volume already exists with root-owned content (from a prior broken-stack attempt), it keeps that ownership. You must explicitly remove the broken volume:

```bash
docker compose down                                    # don't use -v if you want to keep other volumes
docker volume rm <project>_static_data <project>_media_data
docker compose up -d                                   # Docker initialises fresh, copying from the rebuilt image
```

`docker compose down -v` removes ALL named volumes for the project — fine in dev, dangerous if you want to keep Postgres / other stateful volumes. Target the affected volumes by name.

## Affected mount points (typical)

- `/app/staticfiles/` — Django `STATIC_ROOT`, populated by `collectstatic`.
- `/app/media/` — Django `MEDIA_ROOT`, populated by user uploads.
- `/app/logs/` — anything writing to a log file inside a volume.
- `/var/cache/<app>/`, `/var/lib/<app>/` — non-Django apps with cache/state in volumes.
- Any path the non-root user writes to that's covered by a named-volume mount.

## Detection in code review

Look for the pair: `USER <non-root>` in the Dockerfile + a named volume in `compose.yml` mounted at a path the Dockerfile never explicitly `mkdir`s. The combination is a latent footgun.

## Related rules / skills

- `skills/deployment/SKILL.md` — overall Docker Compose conventions; this reference is a domain-specific gotcha.
- `skills/django/SKILL.md` — when the affected app is Django, `collectstatic` is the most common trigger.

---

**Last Updated**: 2026-05-19 — promoted from `tasker` IDEA-001 bootstrap. The pattern was caught by running `python manage.py collectstatic` for the first time after the stack was otherwise green (smoke test passing, HTTP 200 on landing view, healthchecks all reporting healthy). See [`tasker/docs/archive/2026-05-DEVELOPMENT_LOG.md`](https://github.com/sarunazs/tasker/blob/main/docs/archive/2026-05-DEVELOPMENT_LOG.md) for the precedent commit (`fix(docker): pre-create staticfiles + media dirs with app-user ownership`).
