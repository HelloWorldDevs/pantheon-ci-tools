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
  protected function modifyLandoFile(): bool
  {
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

    // Standardize tooling commands.
    foreach (self::newLandoCommands() as $cmdName => $definition) {
      $yaml['tooling'][$cmdName] = $definition;
    }

    try {
      $yamlString = $this->dumpYaml($yaml);
    } catch (\RuntimeException $e) {
      $this->io->writeError(sprintf('  - Error: failed to dump YAML for %s: %s', $filePath, $e->getMessage()));
      return false;
    }
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
      ['appserver' => 'bash /app/lando/scripts/dev-config.sh disable'],
      ['appserver' => 'drush cr']
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
      ['appserver' => 'echo "Setting up dev environment..."'],
      ['appserver' => 'bash /app/lando/scripts/dev-config.sh enable']
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
   *
   * @param string $filePath The path to the YAML file to parse
   * @return ?array The parsed YAML data, or null if parsing fails
   */
  private function parseYamlFile(string $filePath): ?array {
    try {
      if (\function_exists('yaml_parse_file')) {
        // ext-yaml is optional; calling via variable avoids static analysis errors
        // while still honoring the runtime function_exists() guard.
        $parser = 'yaml_parse_file';
        $data = $parser($filePath);
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
   *
   * @param array $data The data to dump
   * @return string The YAML dump
   * @throws \RuntimeException If dump fails.
   */
  private function dumpYaml(array $data): string {
    try {
      // Use specific flags to ensure proper Lando formatting:
      // - DUMP_EMPTY_ARRAY_AS_SEQUENCE: ensures empty arrays are formatted as YAML sequences
      // - DUMP_NULL_AS_TILDE: represents null as ~ instead of null
      // - DUMP_MULTI_LINE_LITERAL_BLOCK: creates readable block scalars for multi-line strings
      // - Set inline level to 10 to avoid excessive inline folding
      $flags = Yaml::DUMP_EMPTY_ARRAY_AS_SEQUENCE | Yaml::DUMP_NULL_AS_TILDE | Yaml::DUMP_MULTI_LINE_LITERAL_BLOCK;
      
      $yaml = Yaml::dump($data, 10, 2, $flags);

      $yaml = preg_replace_callback('/^(\s*)-\n(\s+)(?=\w+:)/m', function($matches) {
        $dashIndent = $matches[1];
        $contentIndent = $matches[2];
        
        if (strlen($contentIndent) === strlen($dashIndent) + 2) {
            return $dashIndent . '- ';
        }
        return $matches[0];
      }, $yaml);

      return $yaml;

    } catch (\Throwable $e) {
      throw new \RuntimeException('YAML dump error: ' . $e->getMessage(), 0, $e);
    }
  }

  /**
   * Merge two indexed arrays preserving order & uniqueness.
   * 
   * @param array $existing The existing array configuration events
   * @param array $additions The new array configuration events
   * @return array The merged array configuration events
   */
  private static function mergeUnique(array $existing, array $additions): array {
    $result = [];
    $seen = [];

    foreach (array_merge($existing, $additions) as $item) {
      $sig = self::eventSignature($item);
      if (!isset($seen[$sig])) {
        $result[] = $item;
        $seen[$sig] = true;
      }
    }

    return $result;
  }

  /**
   * Normalize an event entry (string or mapping) to a signature for uniqueness.
   *
   * @param mixed $item The event entry (string or mapping)
   * @return string The normalized event signature
   */
  private static function eventSignature($item): string {
    if (is_array($item)) {
      ksort($item);
      // Normalize common command variants so equivalent steps don't accumulate
      // across tool versions (e.g., emoji vs non-emoji dev setup messages).
      foreach ($item as $k => $v) {
        if (is_string($v)) {
          $item[$k] = self::normalizeEventCommand($v);
        }
      }
      return 'A:'.json_encode($item, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }
    return 'S:'.self::normalizeEventCommand((string) $item);
  }

  /**
   * Normalize command strings to avoid duplicate variants.
   *
   * @param string $cmd The command string to normalize
   * @return string The normalized command string
   */
  private static function normalizeEventCommand(string $cmd): string {
    $cmd = trim($cmd);

    // Treat these as equivalent:
    // - echo "🔧 Setting up dev environment..."
    // - echo "Setting up dev environment..."
    $cmd = preg_replace(
      '/^echo\\s+["\\\']?(?:🔧\\s+)?Setting up dev environment\\.\\.\\.["\\\']?$/u',
      'echo "Setting up dev environment..."',
      $cmd
    ) ?? $cmd;

    return $cmd;
  }
}