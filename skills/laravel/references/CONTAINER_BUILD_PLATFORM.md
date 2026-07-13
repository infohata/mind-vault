# Composer build-PHP ≠ runtime-PHP — pin the platform in the build stage

A multi-stage PHP/Laravel Dockerfile typically installs dependencies in a `FROM composer:N` stage and
runs in a separate `FROM php:X-fpm` runtime. **The `composer:N` official image tracks the *latest* PHP**
(it builds `FROM` a floating `php:8`-series tag and is rebuilt as new PHP releases land — there is no
PHP-pinned variant), so its PHP can be **newer** than your pinned runtime. When the
lockfile is not committed (a deliberate float model) — or you otherwise run `composer update` — composer
resolves dependencies against the **build image's** PHP and pulls package versions that floor at a PHP
newer than your runtime. Composer bakes the highest resolved platform requirement into
`vendor/composer/platform_check.php`, which the autoloader runs on **every** request/boot. On the older
runtime it throws:

```text
RuntimeException: Composer detected issues in your platform:
Your Composer dependencies require a PHP version ">= 8.4.1". You are running 8.3.x.
  in .../vendor/composer/platform_check.php
```

— a fatal on the **first request**, not at build time.

## Why the usual `--ignore-platform-reqs` makes it worse

The blanket `--ignore-platform-reqs` ignores the `php` constraint **too**, so composer will happily
select packages incompatible with the real runtime — and worse, ignored requirements are **excluded from
the generated `platform_check.php`**, so the gate itself is silenced. The mismatch then surfaces as
arbitrary undiagnosed breakage deep inside a newer-PHP-floored package (parse/feature errors), not as
one clear platform fatal. It hides the bug instead of preventing it.

## The fix — two parts

1. **Pin the resolver's PHP to the runtime version — in the BUILD stage, not the committed manifest.**
   In the composer stage:
   ```dockerfile
   RUN composer config --global platform.php 8.3.0   # match the runtime series
   ```
   Do **not** commit `config.platform.php` into `composer.json`: that key is **repo-wide** and forces the
   pin onto *every* consumer — local dev, CI, and any other host. If a different environment runs a
   different PHP (e.g. an older box still on the previous major/minor), it would then bake the *same*
   broken `platform_check.php` and fatal there instead. Scope the pin to the build that needs it.

2. **Keep `php` ENFORCED while ignoring only the missing extensions.** Use the composer 2.2+ wildcard
   `--ignore-platform-req='ext-*'` instead of the blanket flag:
   ```dockerfile
   RUN composer update --no-dev --prefer-dist --ignore-platform-req='ext-*'
   ```
   The `composer:N` image lacks the `ext-gd`/`ext-intl`/`ext-zip`/… that your `php:X-fpm` runtime installs,
   so those must be ignored — but keeping `php` enforced is what makes the platform pin from step 1
   actually **constrain resolution** (composer picks versions compatible with the faked `8.3.0`). `lib-*`
   requirements stay enforced, so confirm a full `install`/`update` still completes.

## Verify

Resolve inside the composer image and read the generated gate — its floor must **not exceed your
runtime** series (it reflects the highest package floor, so after pinning it's ≤ the pin, often lower):
```bash
grep PHP_VERSION_ID vendor/composer/platform_check.php   # <= 80300 (e.g. >= 80100) ok; >= 80400 fatals the runtime
```
A quick before/after in the `composer:N` image also shows a floored transitive dependency dropping from
its newer-PHP major to a runtime-compatible version.

## When this applies / doesn't

- **Applies:** any multi-stage PHP build where the build-stage PHP can float above the runtime **and** the
  lockfile isn't committed (so `composer update` runs at build and resolution can drift).
- **Committed lockfile + `composer install`:** resolution is frozen, so it can't silently drift at build —
  but if the lock was *updated* on a newer PHP, the baked gate follows the **lock's** floor and the
  build-stage pin does NOT rescue it (probed on Composer 2.10: `install` bakes the lock's requirement into
  `platform_check.php` regardless of `config.platform.php`). The working guard is running `install` under
  the **runtime** PHP, which fails the *build* ("Your lock file does not contain a compatible set of
  packages") instead of fataling at runtime.
- **Same PHP in both stages:** no mismatch, nothing to pin.

The root shape is general: **whenever the toolchain that resolves/generates artifacts runs a different
platform version than the target that executes them, pin the resolver to the target — and scope the pin
to the build, not the shared manifest.**

## Version note

`platform_check.php` generation is Composer 2.0+; the `--ignore-platform-req` wildcard (`ext-*`) is
Composer 2.2+ — any current `composer:2` image satisfies both (behavior above probed on Composer 2.10).
Container-build-level pattern, not Laravel-version-sensitive — no L13 drift expected.
