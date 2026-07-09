# Composer build-PHP ≠ runtime-PHP — pin the platform in the build stage

A multi-stage PHP/Laravel Dockerfile typically installs dependencies in a `FROM composer:N` stage and
runs in a separate `FROM php:X-fpm` runtime. **The `composer:N` official image tracks the *latest* PHP**
(it is rebuilt as new PHP releases land), so its PHP can be **newer** than your pinned runtime. When the
lockfile is not committed (a deliberate float model) — or you otherwise run `composer update` — composer
resolves dependencies against the **build image's** PHP and pulls package versions that floor at a PHP
newer than your runtime. Composer bakes the highest resolved platform requirement into
`vendor/composer/platform_check.php`, which the autoloader runs on **every** request/boot. On the older
runtime it throws:

```
RuntimeException: Composer detected issues in your platform:
Your Composer dependencies require a PHP version ">= 8.4.1". You are running 8.3.x.
  in .../vendor/composer/platform_check.php
```

— a fatal on the **first request**, not at build time.

## Why the usual `--ignore-platform-reqs` makes it worse

The blanket `--ignore-platform-reqs` ignores the `php` constraint **too**, so composer will happily
select packages incompatible with the real runtime and nothing complains during the build. The mismatch
is simply deferred to runtime, where `platform_check.php` fails. It hides the bug instead of preventing it.

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

Resolve inside the composer image and read the generated gate — it should match your **runtime** series,
not the build image's:
```bash
grep PHP_VERSION_ID vendor/composer/platform_check.php   # want >= 80300, not >= 80400
```
A quick before/after in the `composer:N` image also shows a floored transitive dependency dropping from
its newer-PHP major to a runtime-compatible version.

## When this applies / doesn't

- **Applies:** any multi-stage PHP build where the build-stage PHP can float above the runtime **and** the
  lockfile isn't committed (so `composer update` runs at build and resolution can drift).
- **Committed lockfile + `composer install`:** resolution is frozen, so it can't silently drift — but the
  build-image-PHP mismatch still means `install` should either run under the runtime PHP or carry the
  same `config.platform.php` build-scoped pin, so `platform_check.php` is generated for the runtime.
- **Same PHP in both stages:** no mismatch, nothing to pin.

The root shape is general: **whenever the toolchain that resolves/generates artifacts runs a different
platform version than the target that executes them, pin the resolver to the target — and scope the pin
to the build, not the shared manifest.**
