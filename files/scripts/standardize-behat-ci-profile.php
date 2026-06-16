<?php

/**
 * Standardize a project's `circleci` Behat profile for running against a
 * DEPLOYED Pantheon environment (multidev/dev).
 *
 * WHY THIS EXISTS
 * ---------------
 * Projects configure Behat differently for the OLD local-install CI model:
 *   - some drive @javascript via Selenium (`selenium2` + a Selenium container),
 *   - some via the DMore Chrome (CDP) session,
 *   - they hardcode `base_url` (e.g. *.lando / drupal-circleci-behat.localhost),
 *   - they use `api_driver: drupal` (in-process Drupal bootstrap for fixtures).
 *
 * None of that works when the suite runs against a remote multidev on a CI box
 * with no local Drupal and no Selenium container. We also can't fix it with
 * BEHAT_PARAMS: Behat merges configs as [BEHAT_PARAMS, default, named-profile]
 * with the LATER source winning, so a project's `circleci`/`default` profile
 * overrides anything BEHAT_PARAMS injects (that's why retargeting "did nothing").
 *
 * The only layer that reliably wins is the named profile the runner selects
 * (`--profile circleci`). So this script rewrites THAT profile in-place (the CI
 * checkout is ephemeral) to a known-good, deploy-target configuration:
 *   - enables the DMore ChromeExtension (registers the `chrome` session driver),
 *   - adds a dedicated `ci_chrome` session (distinct name, so it never collides
 *     with an existing `selenium2`/`goutte` session under the same key),
 *   - points default + javascript sessions at `ci_chrome` (CDP on :9222),
 *   - sets `base_url` to the deployed URL,
 *   - switches the Drupal driver to remote `drush` with the Pantheon alias.
 *
 * Everything else (suites/filters, contexts, region_map, selectors, screenshot
 * dirs) is preserved — `circleci` is merged over `default` by Behat, so the
 * project's contexts and CI tag filters still apply.
 *
 * Usage:
 *   php standardize-behat-ci-profile.php <behat.yml> <base_url> <drush_alias> [chrome_api_url]
 */

if ($argc < 4) {
    fwrite(STDERR, "Usage: php standardize-behat-ci-profile.php <behat.yml> <base_url> <drush_alias> [chrome_api_url]\n");
    exit(2);
}

$behatYml     = $argv[1];
$baseUrl      = $argv[2];
$drushAlias   = $argv[3];
$chromeApiUrl = $argv[4] ?? 'http://localhost:9222';

// Locate Composer's autoloader (symfony/yaml ships with Behat). Try the usual
// spots relative to both the project root and this script.
$autoloadCandidates = [
    getcwd() . '/vendor/autoload.php',
    dirname($behatYml) . '/../../vendor/autoload.php',
    __DIR__ . '/../../vendor/autoload.php',
    __DIR__ . '/../../../../autoload.php',
];
$autoloadFound = false;
foreach ($autoloadCandidates as $autoload) {
    if (is_file($autoload)) {
        require_once $autoload;
        $autoloadFound = true;
        break;
    }
}
if (!$autoloadFound || !class_exists(\Symfony\Component\Yaml\Yaml::class)) {
    fwrite(STDERR, "ERROR: could not load symfony/yaml (no vendor/autoload.php found).\n");
    exit(1);
}

use Symfony\Component\Yaml\Yaml;

if (!is_file($behatYml)) {
    fwrite(STDERR, "ERROR: behat config not found: {$behatYml}\n");
    exit(1);
}

$config = Yaml::parseFile($behatYml);
if (!is_array($config)) {
    fwrite(STDERR, "ERROR: {$behatYml} did not parse to a mapping.\n");
    exit(1);
}

// Discover the extension keys the project actually uses, so we write to the SAME
// keys (Behat maps both Behat\MinkExtension and Drupal\MinkExtension to config
// key 'mink'; two different keys in one profile would clobber each other).
$defaultExtensions = isset($config['default']['extensions']) && is_array($config['default']['extensions'])
    ? $config['default']['extensions']
    : [];

$minkKey   = null;
$drupalKey = null;
foreach (array_keys($defaultExtensions) as $extKey) {
    if ($minkKey === null && preg_match('/MinkExtension$/', $extKey)) {
        $minkKey = $extKey;
    }
    if ($drupalKey === null && preg_match('/DrupalExtension$/', $extKey)) {
        $drupalKey = $extKey;
    }
}
$minkKey   = $minkKey   ?: 'Drupal\\MinkExtension';
$drupalKey = $drupalKey ?: 'Drupal\\DrupalExtension';
$chromeKey = 'DMore\\ChromeExtension\\Behat\\ServiceContainer\\ChromeExtension';

// Legacy Mink driver configs we strip everywhere. We standardize on the CDP
// `ci_chrome` session, so any other driver the project declared (often as a
// top-level `goutte: ~` / `selenium2: {...}` under mink) must be removed — Behat
// ALWAYS merges the `default` profile, and Mink eagerly builds every configured
// driver, so a leftover `goutte: ~` whose package isn't installed aborts the run
// ("Install MinkGoutteDriver…") before any test executes.
$legacyMinkDrivers = ['goutte', 'selenium2', 'selenium', 'selenium4', 'sahi', 'zombie', 'browserkit_http', 'webdriver'];

/**
 * Strip legacy top-level driver keys from every *MinkExtension entry in a
 * profile's `extensions` map. Mutates and returns the extensions array.
 */
$stripMinkDrivers = static function (array $extensions) use ($legacyMinkDrivers): array {
    foreach ($extensions as $extKey => $extConfig) {
        if (!preg_match('/MinkExtension$/', $extKey) || !is_array($extConfig)) {
            continue;
        }
        foreach ($legacyMinkDrivers as $driver) {
            unset($extConfig[$driver]);
        }
        $extensions[$extKey] = $extConfig;
    }
    return $extensions;
};

// Clean the `default` profile's Mink drivers in place (it's always merged in).
if (!empty($defaultExtensions)) {
    $config['default']['extensions'] = $stripMinkDrivers($defaultExtensions);
}

// Start from the project's existing circleci profile (preserve suites/filters).
$ci = isset($config['circleci']) && is_array($config['circleci']) ? $config['circleci'] : [];
if (!isset($ci['extensions']) || !is_array($ci['extensions'])) {
    $ci['extensions'] = [];
}

// Collapse any alternate Mink/Drupal extension key variants into the canonical
// key so we don't end up with two entries that resolve to the same config key.
foreach (array_keys($ci['extensions']) as $extKey) {
    if ($extKey !== $minkKey && preg_match('/MinkExtension$/', $extKey)) {
        $ci['extensions'][$minkKey] = array_replace_recursive(
            is_array($ci['extensions'][$minkKey] ?? null) ? $ci['extensions'][$minkKey] : [],
            is_array($ci['extensions'][$extKey] ?? null) ? $ci['extensions'][$extKey] : []
        );
        unset($ci['extensions'][$extKey]);
    }
    if ($extKey !== $drupalKey && preg_match('/DrupalExtension$/', $extKey)) {
        $ci['extensions'][$drupalKey] = array_replace_recursive(
            is_array($ci['extensions'][$drupalKey] ?? null) ? $ci['extensions'][$drupalKey] : [],
            is_array($ci['extensions'][$extKey] ?? null) ? $ci['extensions'][$extKey] : []
        );
        unset($ci['extensions'][$extKey]);
    }
}

// 1) Enable the DMore Chrome extension (registers the `chrome` session driver).
$ci['extensions'][$chromeKey] = null;

// 2) Mink: retarget the deployed URL and drive everything through a dedicated
//    CDP chrome session. A distinct session name ('ci_chrome') avoids colliding
//    with any selenium2/goutte driver the project already defined.
$mink = is_array($ci['extensions'][$minkKey] ?? null) ? $ci['extensions'][$minkKey] : [];
foreach ($legacyMinkDrivers as $driver) {
    unset($mink[$driver]);
}
$mink['base_url']           = $baseUrl;
$mink['browser_name']       = 'chrome';
$mink['default_session']    = 'ci_chrome';
$mink['javascript_session'] = 'ci_chrome';
if (!isset($mink['sessions']) || !is_array($mink['sessions'])) {
    $mink['sessions'] = [];
}
$mink['sessions']['ci_chrome'] = [
    'chrome' => [
        'api_url'              => $chromeApiUrl,
        'validate_certificate' => false,
    ],
];
$ci['extensions'][$minkKey] = $mink;

// 3) Drupal driver: create @api fixtures via remote drush on the Pantheon env.
$drupal = is_array($ci['extensions'][$drupalKey] ?? null) ? $ci['extensions'][$drupalKey] : [];
$drupal['api_driver'] = 'drush';
if (!isset($drupal['drush']) || !is_array($drupal['drush'])) {
    $drupal['drush'] = [];
}
$drupal['drush']['alias'] = $drushAlias;
$ci['extensions'][$drupalKey] = $drupal;

$config['circleci'] = $ci;

// Dump with enough inline depth to keep nested maps readable.
$yaml = Yaml::dump($config, 10, 2, Yaml::DUMP_EMPTY_ARRAY_AS_SEQUENCE);
if (file_put_contents($behatYml, $yaml) === false) {
    fwrite(STDERR, "ERROR: failed to write {$behatYml}\n");
    exit(1);
}

fwrite(STDOUT, "Standardized `circleci` profile in {$behatYml}\n");
fwrite(STDOUT, "  mink key:   {$minkKey}\n");
fwrite(STDOUT, "  drupal key: {$drupalKey}\n");
fwrite(STDOUT, "  base_url:   {$baseUrl}\n");
fwrite(STDOUT, "  drush alias:{$drushAlias}\n");
fwrite(STDOUT, "  chrome CDP: {$chromeApiUrl}\n");
exit(0);
