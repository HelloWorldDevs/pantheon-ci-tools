#!/usr/bin/env bash
#
# Tests for files/github/prod-config-drift.yml.
#
# The workflow checks out the default branch (that's the config it compares
# with prod), but the drift script must come from the ref the run was started
# on. Otherwise `gh workflow run prod-config-drift.yml --ref some-branch` runs
# the default branch's copy of the script and never tests the branch's fix.
#
# Run: bash tests/prod-config-drift-workflow.test.sh  (needs `composer install`)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

php -d display_errors=stderr -- "${ROOT}" <<'PHP'
<?php
require $argv[1] . '/vendor/autoload.php';

$wf = Symfony\Component\Yaml\Yaml::parseFile($argv[1] . '/files/github/prod-config-drift.yml');
$job = $wf['jobs']['drift'];
$steps = $job['steps'];
$fails = 0;
$check = function (bool $ok, string $label) use (&$fails) {
  echo ($ok ? 'ok   - ' : 'FAIL - ') . $label . "\n";
  if (!$ok) { $fails++; }
};
$isCheckout = fn ($s) => strpos($s['uses'] ?? '', 'actions/checkout@') === 0;
$runOf = fn ($s) => $s['run'] ?? '';

$defaultIdx = $toolsIdx = null;
foreach ($steps as $i => $s) {
  if (!$isCheckout($s)) { continue; }
  $ref = $s['with']['ref'] ?? '';
  if (strpos($ref, 'default_branch') !== false && empty($s['with']['path'])) { $defaultIdx = $i; }
  if ($ref === '${{ github.sha }}' && !empty($s['with']['path'])) { $toolsIdx = $i; }
}
$check($defaultIdx !== null, 'checks out the default branch at the workspace root');
$check($toolsIdx !== null, 'checks out the triggering ref (github.sha) into its own path');
$check($defaultIdx !== null && $toolsIdx !== null && $toolsIdx > $defaultIdx,
  'tooling checkout runs after the root checkout (which would clean it away)');

$toolsPath = $toolsIdx !== null ? rtrim($steps[$toolsIdx]['with']['path'], '/') : '<none>';
$script = $job['env']['DRIFT_SCRIPT'] ?? '';
$check($script === $toolsPath . '/.ci/scripts/config_split/prod-config-drift.sh',
  "DRIFT_SCRIPT points into the tooling checkout (got '{$script}')");

$gate = $drift = null;
foreach ($steps as $s) {
  if (($s['id'] ?? '') === 'gate') { $gate = $s; }
  if (($s['id'] ?? '') === 'drift') { $drift = $s; }
}
$check($gate && strpos($runOf($gate), '${DRIFT_SCRIPT}') !== false, 'gate looks for ${DRIFT_SCRIPT}');
$check($drift && trim($runOf($drift)) === 'bash "${DRIFT_SCRIPT}"', 'drift step runs ${DRIFT_SCRIPT}');

echo "\n" . ($fails ? "{$fails} test(s) failed.\n" : "All tests passed.\n");
exit($fails ? 1 : 0);
PHP
