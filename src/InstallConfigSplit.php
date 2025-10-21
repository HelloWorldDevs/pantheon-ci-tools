<?php
declare(strict_types=1);

namespace HelloWorldDevs\PantheonCI;

use Composer\IO\IOInterface;
use Composer\Json\JsonManipulator;
use Symfony\Component\Yaml\Yaml;

class InstallConfigSplit {

  /**
   * @var IOInterface
   */
  private $io;

  /**
   * @var string
   */
  private $projectRoot;

  /**
   * @var string
   */
  private $configSplitPackage = 'drupal/config_split';

  /**
   * @var string
   */
  private $configSplitVersion = '^2.0';

  /**
   * @var string
   */
  private $scriptDir = __DIR__ . '/../files/scripts/config_split';

  private $landoScripts = [
    'config-safety-check.sh',
    'dev-config.sh'
  ];

  public function __construct(IOInterface $io, $projectRoot) {
    $this->io = $io;
    $this->projectRoot = $projectRoot;
  }

  /**
   * Installs the necessary configuration for the config split.
   */
  public function install() : void {

    $this->io->write('  - Installing Config Split setup...');
    if (!$this->require_package()) {
      $this->io->writeError('  - Error: could not ensure Config Split is a dev requirement; aborting config split installation.');
      $this->io->write(sprintf("  - Please install manually via composer require --dev '%s:%s'.", $this->configSplitPackage, $this->configSplitVersion));
      $this->io->write(sprintf('  - Please run "composer update %s --with-all-dependencies" to install it.', $this->configSplitPackage));
      return;
    }
    
    if (!$this->installLandoScripts()) {
      $this->io->writeError('  - Error: could not install Lando scripts; aborting config split installation.');
      return;
    }
    if (!$this->modifyLandoFile()) {
      $this->io->writeError('  - Error: could not modify .lando.yml; aborting config split installation.');
      return;
    }
  }

  /**
   * Modifies the .lando.yml file to include necessary configurations.
   * Parses YAML and updates it with new events and commands.
   *
   * @return bool True if successful, false if not.
   */
  protected function modifyLandoFile() : bool {
    // testing to see if I broke deploys on other projects -RA
    return true;

    
    $filePath = rtrim($this->projectRoot, '/'). '/.lando.yml';
    $backupFile = $filePath . '.bak';

    if (!file_exists($filePath)) {
      $this->io->writeError(sprintf('  - Warning: .lando.yml not found at %s; skipping Lando modification.', $filePath));
      return false;
    }

    if (!copy($filePath, $backupFile)) {
      $this->io->writeError(sprintf('  - Error: failed to create backup copy of %s', $filePath));
      return false;
    }

    $yaml = $this->parseYamlFile($filePath);
    if (!\is_array($yaml)) {
      $this->io->writeError(sprintf('  - Error: failed to parse YAML from %s', $filePath));
      return false;
    }

    // Ensure structure.
    $yaml['events'] = $yaml['events'] ?? [];
    $yaml['events']['post-start'] = $yaml['events']['post-start'] ?? [];
    $yaml['events']['post-pull'] = $yaml['events']['post-pull'] ?? [];
    $yaml['tooling'] = $yaml['tooling'] ?? [];

    // Merge events uniquely.
    $yaml['events']['post-start'] = self::mergeUnique($yaml['events']['post-start'], self::postStartEvents());
    $yaml['events']['post-pull'] = self::mergeUnique($yaml['events']['post-pull'], self::postPullEvents());

    // Tooling: overwrite existing command definitions with new ones (safer for updates).
    foreach (self::newLandoCommands() as $cmdName => $definition) {
      $yaml['tooling'][$cmdName] = $definition;
    }

    $yamlString = $this->dumpYaml($yaml);
    if (file_put_contents($filePath, $yamlString) === false) {
      $this->io->writeError(sprintf('  - Error: failed to write changes to %s', $filePath));
      if (!\file_put_contents($filePath, file_get_contents($backupFile))) {
        $this->io->writeError(sprintf('  - Error: failed to restore backup copy to %s', $filePath));
        $this->io->writeError(sprintf("  - Manually copy contents of %s to %s", $backupFile, $filePath));
      }
      $this->io->writeError(sprintf('  - Restored %s from to original state', $filePath));
      return false;
    }

    $this->io->write('  - Added dev environment setup commands to .lando.yml post-start events');

    $this->io->write('  - Successfully parsed .lando.yml file');

    return true;

  }

  /**
   * Returns the post-pull events to write to Lando configuration
   * as an integer-indexed array.
   *
   * @return array
   */
  protected static function postPullEvents() : array {
    return [
      'appserver: bash /app/lando/scripts/dev-config.sh disable',
      'appserver: drush cr'
    ];
  }

  /**
   * Returns the post-start events to write to Lando configuration as
   * an integer-indexed array.
   *
   * @return array
   */
  protected static function postStartEvents() : array {
    return [
      'appserver: echo "🔧 Setting up dev environment..."',
      'appserver: bash /app/lando/scripts/dev-config.sh enable'
    ];
  }

  /**
   * Returns the new Lando commands to write to Lando configuration
   * as multidimensional array.
   *
   * @return array
   */
  protected static function newLandoCommands() : array {
    return [
      'dev-config' => [
        'service' => 'appserver',
        'description' => 'Enable/disable dev config split (usage - dev-config enable|disable)',
        'cmd' => 'bash /app/lando/scripts/dev-config.sh'
      ],
      'config-check' => [
        'service' => 'appserver',
        'description' => 'Check the configuration split (usage - config-check)',
        'cmd' => 'bash /app/lando/scripts/config-safety-check.sh'
      ],
      'safe-export' => [
        'service' => 'appserver',
        'description' => 'Export the configuration split (usage - safe-export)',
        'cmd' => [
          'echo "🔍 Preparing safe config export..."',
          'bash /app/lando/scripts/dev-config.sh disable',
          'bash /app/lando/scripts/config-safety-check.sh',
          'drush cex -y',
          'echo "✅ Config exported safely"'
        ]
      ]
    ];
  }

  /**
   * Copies the necessary Lando scripts to the project directory.
   * Scripts installed defined in `$this->landoScripts`.
   *
   * @return bool True if successful, false if not.
   */
  protected function installLandoScripts() : bool {
    $landoScriptsDir = rtrim($this->projectRoot, '/'). '/lando/scripts';

    if (!\is_dir($landoScriptsDir) && !\mkdir($landoScriptsDir, 0755, true) && !\is_dir($landoScriptsDir)) {
      $this->io->writeError(sprintf('  - Error: failed to create Lando scripts directory %s', $landoScriptsDir));
      return false;
    }
    if (!\is_dir($landoScriptsDir)) {
      $this->io->writeError(sprintf('  - Error: Lando scripts directory %s is not a directory', $landoScriptsDir));
      return false;
    }

    foreach ($this->landoScripts as $script) {
      $tarPath = $landoScriptsDir . '/' . $script;
      if (file_exists($tarPath)) {
        $this->io->write(sprintf('  - Lando script %s already exists; skipping.', $script));
        continue;
      }
      if (!copy($this->scriptDir . '/' . $script, $tarPath)) {
        $this->io->writeError(sprintf('  - Error: failed to copy %s to %s', $script, $tarPath));
        return false;
      }
      if (!chmod($tarPath, 0755)) {
        $this->io->writeError(sprintf('  - Error: failed to make executable: %s', $script));
        return false;
      }
      $this->io->write(sprintf('  - Copied and made executable: %s', $script));
    }

    $this->io->write('  - All Lando scripts have been copied successfully!');

    return true;
  }
  
  /**
   * Ensure a dev requirement exists in composer.json.
   *
   * This only mutates composer.json; it does NOT run Composer. Safer for scripts.
   *
   * @param string $package     e.g. 'drupal/config_split'
   * @param string $constraint  e.g. '^2.0'
   * @param string $projectRoot Absolute path to the project root containing composer.json
   * @return bool True if package is installed or already exists, false if not
   */
  protected function require_package(): bool
  {
    $this->io->write("  - Checking for Config Split...");
      $composerFile = rtrim($this->projectRoot, '/').'/composer.json';
      if (!file_exists($composerFile)) {
          $this->io->write(sprintf('  - Warning: composer.json not found at %s; skipping dev requirement check.', $composerFile));
          return false;
      }

      $contents = file_get_contents($composerFile);
      if ($contents === false) {
          $this->io->writeError(sprintf('  - Error: could not read %s', $composerFile));
          return false;
      }

      $decoded = json_decode($contents, true);
      if (!is_array($decoded)) {
          $this->io->writeError(sprintf('  - Error: %s is not valid JSON', $composerFile));
          return false;
      }

      $alreadyPresent = (
        isset($decoded['require-dev']) && is_array($decoded['require-dev']) &&
        array_key_exists($this->configSplitPackage, $decoded['require-dev'])
      );
      if ($alreadyPresent) {
          $this->io->write(sprintf('  - %s already present in require-dev.', $this->configSplitPackage));
          return true;
      }

      $manip = new JsonManipulator($contents);
      if (!$manip->addLink('require-dev', $this->configSplitPackage, $this->configSplitVersion, /* sort */ true)) {
          $this->io->writeError(sprintf('  - Error: failed to add %s:%s to require-dev.', $this->configSplitPackage, $this->configSplitVersion));
          return false;
      }

      if (file_put_contents($composerFile, $manip->getContents()) === false) {
          $this->io->writeError(sprintf('  - Error: failed writing changes to %s', $composerFile));
          return false;
      }

      $this->io->write(sprintf('  - Added %s:%s to require-dev.', $this->configSplitPackage, $this->configSplitVersion));
      $this->io->write('    Next step: run "composer update '.$this->configSplitPackage.' --with-all-dependencies" to install it.');

      return true;
  }

  /**
   * Parse YAML file with PECL yaml or Symfony Yaml as fallback.
   */
  private function parseYamlFile(string $filePath): ?array {
    try {
      if (\function_exists('yaml_parse_file')) {
        $data = \yaml_parse_file($filePath);
        return \is_array($data) ? $data : null;
      }
      return Yaml::parseFile($filePath);
    } catch (\Throwable $e) {
      $this->io->writeError('  - YAML parse error: '.$e->getMessage());
      return null;
    }
  }

  /**
   * Dump YAML using available implementation.
   */
  private function dumpYaml(array $data): string {
    try {
      if (\function_exists('yaml_emit')) {
        return (string) \yaml_emit($data);
      }

      // Use specific flags to ensure proper Lando formatting:
      // - DUMP_EMPTY_ARRAY_AS_SEQUENCE: ensures arrays are formatted as YAML sequences  
      // - DUMP_NULL_AS_TILDE: represents null as ~ instead of null
      // - Set inline level to 6 and use proper indentation
      $flags = Yaml::DUMP_EMPTY_ARRAY_AS_SEQUENCE | Yaml::DUMP_NULL_AS_TILDE;
      $yamlOutput = Yaml::dump($data, 6, 2, $flags);

      // Post-process to remove quotes around Lando command strings
      // Remove quotes from any string that looks like "service: command" in array items
      $yamlOutput = preg_replace("/^(\s+- )['\"]([a-zA-Z0-9_-]+:\s*[^'\"]*)['\"]$/m", '$1$2', $yamlOutput);
      // Handle cmd values that are quoted (both single values and in arrays)
      $yamlOutput = preg_replace("/^(\s+cmd:\s*)['\"]([a-zA-Z0-9_-]+:\s*[^'\"]*)['\"]$/m", '$1$2', $yamlOutput);
      // Handle multiline array formatting issues - remove extra newlines before array items
      $yamlOutput = preg_replace("/(\s+- )\n(\s+)([a-zA-Z0-9_-]+:)/m", '$1$3', $yamlOutput);

      return $yamlOutput;
    } catch (\Throwable $e) {
      $this->io->writeError('  - YAML dump error: '.$e->getMessage());
      return "# YAML dump failed; JSON fallback\n".json_encode($data, JSON_PRETTY_PRINT);
    }
  }

  /**
   * Merge two indexed arrays preserving order & uniqueness.
   */
  private static function mergeUnique(array $existing, array $additions): array {
    $result = $existing;
    $signatures = [];

    // Build signature list from existing.
    foreach ($existing as $item) {
      $signatures[] = self::eventSignature($item);
    }

    foreach ($additions as $item) {
      $sig = self::eventSignature($item);
      if (!in_array($sig, $signatures, true)) {
        $result[] = $item;
        $signatures[] = $sig;
      }
    }
    return $result;
  }

  /**
   * Normalize an event entry (string or mapping) to a signature for uniqueness.
   *
   * @param mixed $item
   */
  private static function eventSignature($item): string {
    if (is_array($item)) {
      // Sort keys for stable signature.
      ksort($item);
      return 'A:'.json_encode($item, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }
    return 'S:'.(string)$item;
  }
}