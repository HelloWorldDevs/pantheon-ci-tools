# Behat executor image

## Decision

**Base image: `cimg/php:<php_version>-browsers`** (CircleCI's official PHP
convenience image, `-browsers` variant). No published custom image.

This replaces `helloworlddevs/atdove-testing-image:v2`, whose Dockerfile had
drifted out of git (the pushed v2 was PHP 8.2 on `drupal:10-php8.2-apache`; the
committed Dockerfile still said 8.1) and which existed in exactly one PHP
version. The archived files are in `../legacy/`.

### Why this base

Verified by pulling and inspecting `cimg/php:8.2-browsers` (2026-09-11):

| Needed by the Behat jobs            | In the base image                        |
|-------------------------------------|------------------------------------------|
| PHP + gd, pdo_mysql, mbstring, xml, curl, bcmath, zip | yes (plus intl, soap, exif) |
| composer, git, sudo                 | yes                                      |
| dockerize (`-wait tcp://localhost:3306`) | yes                                 |
| Google Chrome (CDP on :9515 for DMore ChromeExtension) | yes, `google-chrome` on PATH |
| node/npm (fallback theme build in behat_setup) | yes                           |
| jq                                  | yes                                      |
| **mysql client** (create DB, load dump) | **no — 15s apt install**             |
| **web server**                      | **no — use PHP's built-in server**       |

Tags `8.1`, `8.2`, `8.3`, `8.4` are all maintained and rebuilt in 2026, so the
PHP version is just the tag. The official `drupal:` image was rejected: it lacks
git, sudo, Chrome and a mysql client, and its 8.1/8.2 variants stopped
receiving builds in 2024/2025.

### Do we need to publish an image?

**No.** The entire delta over the base is one `apt-get install mariadb-client`
(measured: 15s including `apt-get update`). That is a `run` step in the
CircleCI config, not an image. Everything below is "just part of the circle
config".

`Dockerfile` + `build.sh` in this directory are an *opt-in* pre-bake for later,
if shard count makes 15s × N worth shaving. If you ever use them you must
publish (GHCR, like the mirrored Playwright image) and keep them in sync — which
is exactly the maintenance the atdove image failed at, so start without it.

## How it is wired (shipped in `files/.circleci/`)

All of this is in the plugin's CircleCI config, so projects get it by updating
the package. No image is pulled from our registry.

1. **`config.yml` (setup)** reads `php_version` from the project's
   `pantheon.yml` (falls back to `8.2`) and passes it as a pipeline parameter
   alongside `behat_parallelism`.
2. **`continue_config.yml`** uses that parameter for both executors:
   - `pantheon`: `quay.io/pantheon-public/build-tools-ci:8.x-php<php_version>`
     (previously hardcoded to php8.3 for every project).
   - `behat`: `cimg/php:<php_version>-browsers` + the `cimg/mariadb:10.6`
     sidecar, `working_directory: ~/project`.
3. Three reusable **commands** replace what the old image baked in:
   - `install_behat_deps` — `apt-get install mariadb-client` (~15s).
   - `prepare_behat_box` — writes the PHP ini overrides to whatever scan dir
     PHP reports (`/etc/php.d` on cimg, not `/usr/local/etc/php/conf.d`), and
     symlinks `/var/www/project` → the working directory so project files that
     still hardcode the old absolute path (e.g. FailAid's screenshot dir in
     `tests/behat/behat.yml`) keep working without edits.
   - `serve_drupal` — replaces "Setup Apache". Runs PHP's built-in server with
     Drupal core's `.ht.router.php` on `:80` as root (background step), so
     `behat.yml`'s `base_url` and `settings.local.php`'s `trusted_host_patterns`
     (`http://drupal-circleci-behat.localhost`) are unchanged. Followed by a
     30s readiness wait.
4. **`chrome.sh`** resolves the browser at runtime (`google-chrome` on PATH,
   then `chromium`, then the legacy `/chrome/linux-*/` layout, or `CHROME_BIN`)
   instead of a hardcoded Chrome-for-Testing 128 path. Also unpins Chrome.
5. The `Start XVFB` step is gone — Chrome runs `--headless`, so it was inert.

### What projects must NOT have to change

`tests/behat/behat.yml`, `.ci/test/behat/env/settings.local.php`,
`configure-site`, `install-drupal`, `run-tests-circle` — all untouched. The
`sudo chown -R www-data` in `configure-site` is harmless (the user exists on
Ubuntu) but unnecessary now that the server runs as root.

### Known trade-off

The built-in server does not read `.htaccess`. The CI `.htaccess` is stock
Drupal core, so clean URLs, index.php fallthrough and static files are covered
by the router. If a scenario ever depends on an Apache-only rule (a `.yml` deny,
a gzip-serving rule), the fallback is `apt-get install apache2` (+14s) wired to
the image's own `php-fpm` via `proxy_fcgi` — the base ships `/usr/local/sbin/php-fpm`.
