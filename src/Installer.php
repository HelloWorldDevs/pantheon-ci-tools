<?php

namespace HelloWorldDevs\PantheonCI;

use Composer\IO\IOInterface;

class Installer
{
    /**
     * @var IOInterface
     */
    protected $io;

    /**
     * @param IOInterface $io
     */
    public function __construct(IOInterface $io)
    {
        $this->io = $io;
    }

    /**
     * Main install method
     */
    public function install()
    {
        $this->io->write('  - Copying CI configuration files...');
        $this->copyFiles();

        // For projects using the local-install ("box") Behat model, make sure
        // the CI settings.local.php that configure-site copies actually exists
        // and is tracked (it's commonly gitignored, which breaks CI).
        $this->ensureBehatCiLocalSettings();

        if ($this->isDrupalProject()) {
            $configSplitInstaller = new InstallConfigSplit($this->io, $this->findProjectRoot());
            $configSplitInstaller->install();
        } else {
            $this->io->write('  - Skipping Config Split installation (not a Drupal project)');
        }
    }

    /**
     * Copy CI files to project root
     *
     * @return void
     */
    protected function copyFiles()
    {
        // Get the correct source base (this package)
        $sourceBase = dirname(__DIR__) . '/files';
        $this->io->write(sprintf('  - Source directory: %s', $sourceBase));
        
        // Get the correct project root (find composer.json)
        $destBase = $this->findProjectRoot();
        $this->io->write(sprintf('  - Destination directory: %s', $destBase));
        
        // Ensure destination directories exist
        $this->ensureDirectoryExists($destBase . '/.circleci');
        $this->ensureDirectoryExists($destBase . '/.ci/test/visual-regression');
        $this->ensureDirectoryExists($destBase . '/.ci/test/behat');
        $this->ensureDirectoryExists($destBase . '/.ci/scripts');
        
        // Copy CircleCI config
        $this->copyFile(
            $sourceBase . '/.circleci/config.yml',
            $destBase . '/.circleci/config.yml'
        );

        // Skip .env.example copying for now
        // File will be added in a future version if needed

        $this->copyFile(
            $sourceBase . '/github/delete-multidev-on-merge.yml',
            $destBase . '/.github/workflows/delete-multidev-on-merge.yml'
        );

        // Copy test_routes.json only if it doesn't already exist in the destination
        $testRoutesDest = $destBase . '/test_routes.json';
        if (!file_exists($testRoutesDest)) {
            $this->copyFile(
                $sourceBase . '/test_routes.json',
                $testRoutesDest
            );
        } else {
            $this->io->write(sprintf('  - Skipped copying test_routes.json, file already exists at: %s', str_replace(getcwd() . '/', '', $testRoutesDest)));
        }
        // Copy env_vars.sh only if it doesn't already exist in the destination
        $envVarsDest = $destBase . '/.circleci/env_vars.sh';
        if (!file_exists($envVarsDest)) {
            $this->copyFile(
                $sourceBase . '/.circleci/env_vars.sh',
                $envVarsDest
            );
        } else {
            $this->io->write(sprintf('  - Skipped copying env_vars.sh, file already exists at: %s', str_replace(getcwd() . '/', '', $envVarsDest)));
        }

        $this->copyFile(
            $sourceBase . '/github/pr-comments-to-jira.yml',
            $destBase . '/.github/workflows/pr-comments-to-jira.yml'
        );
        $this->copyFile(
            $sourceBase . '/scripts/dev-multidev.sh',
            $destBase . '/.ci/scripts/dev-multidev.sh'
        );
        $this->copyFile(
            $sourceBase . '/scripts/post_multidev_url.sh',
            $destBase . '/.ci/scripts/post_multidev_url.sh'
        );
        // Adds the multidev URL to the Jira issue sidebar as a remote link
        // (called by build_and_deploy after the deploy).
        $this->copyFile(
            $sourceBase . '/scripts/post_multidev_jira_link.sh',
            $destBase . '/.ci/scripts/post_multidev_jira_link.sh'
        );
        $this->copyFile(
            $sourceBase . '/scripts/setup_vars.sh',
            $destBase . '/.ci/scripts/setup_vars.sh'
        );
        // detect_web_root.sh is sourced by setup_vars.sh AND appended to
        // BASH_ENV so every subsequent step re-runs the THEME_PATH
        // normalization after the project's env_vars.sh (which can
        // otherwise overwrite the corrected value).
        $this->copyFile(
            $sourceBase . '/scripts/detect_web_root.sh',
            $destBase . '/.ci/scripts/detect_web_root.sh'
        );
        // Shared "wait until the multidev is serving" guard. Run first in
        // the test jobs (playwright, behat) so cold-start spin-up doesn't
        // leak into per-test flake.
        $this->copyFile(
            $sourceBase . '/scripts/check-multidev.sh',
            $destBase . '/.ci/scripts/check-multidev.sh'
        );
        // Pre-flight guard that aborts the pipeline early when Pantheon's
        // multidev cap is reached (runs before build_and_deploy), instead of
        // failing deep inside the deploy after a full build.
        $this->copyFile(
            $sourceBase . '/scripts/check-multidev-capacity.sh',
            $destBase . '/.ci/scripts/check-multidev-capacity.sh'
        );
        // Behat: the behat_setup/behat_test jobs in config.yml self-skip
        // (circleci-agent step halt) unless the project ships a tests/behat
        // directory. We DO ship a canonical install-drupal because the install
        // step is standardizable and the old per-project copies were subtly
        // broken (installing a generic profile then config-import, which fails
        // and loops forever on sites with a custom install profile). It
        // auto-detects the profile and installs via --existing-config. The
        // remaining behat scripts (configure-site, run-tests/run-tests-circle,
        // chrome.sh) stay PROJECT-SUPPLIED — they're inherently project-specific
        // (theme build, file ownership, enabled modules, test globbing).
        $this->copyFile(
            $sourceBase . '/.ci/test/behat/install-drupal',
            $destBase . '/.ci/test/behat/install-drupal'
        );

        // Copy test files
        $this->copyFile(
            $sourceBase . '/.ci/test/visual-regression/playwright.config.js',
            $destBase . '/.ci/test/visual-regression/playwright.config.js'
        );

        $this->copyFile(
            $sourceBase . '/.ci/test/visual-regression/playwright-tests.spec.js',
            $destBase . '/.ci/test/visual-regression/playwright-tests.spec.js'
        );

        $this->copyFile(
            $sourceBase . '/.ci/test/visual-regression/run-playwright',
            $destBase . '/.ci/test/visual-regression/run-playwright'
        );

        // Copy script files
        $this->copyFile(
            $sourceBase . '/.ci/test/visual-regression/package.json',
            $destBase . '/.ci/test/visual-regression/package.json'
        );
        // Copy script files
        $this->copyFile(
            $sourceBase . '/.ci/test/visual-regression/package-lock.json',
            $destBase . '/.ci/test/visual-regression/package-lock.json'
        );
        
        $this->io->write('  - All files have been copied successfully!');
        
        echo "Pantheon CI files installed to project root!\n";
    }
    
    /**
     * Ensure a directory exists
     *
     * @param string $dir Directory path
     * @return void
     */
    protected function ensureDirectoryExists($dir)
    {
        if (!is_dir($dir)) {
            if (!@mkdir($dir, 0755, true) && !is_dir($dir)) {
                throw new \RuntimeException(sprintf('Directory "%s" was not created', $dir));
            }
            $this->io->write(sprintf('  - Created directory: %s', $dir));
        }
    }
    
    /**
     * Copy a file with path checking
     *
     * @param string $source Source file path
     * @param string $dest Destination file path
     * @return void
     * @throws \RuntimeException If source file doesn't exist or copy fails
     */
    protected function copyFile($source, $dest)
    {
        if (!file_exists($source)) {
            throw new \RuntimeException(sprintf('Source file not found: %s', $source));
        }

        $destDir = dirname($dest);
        if (!is_dir($destDir)) {
            $this->ensureDirectoryExists($destDir);
        }

        if (!copy($source, $dest)) {
            throw new \RuntimeException(sprintf('Failed to copy %s to %s', $source, $dest));
        }
        
        // Make scripts executable
        $filename = basename($dest);
        if (strpos($filename, '.sh') !== false || 
            strpos($filename, 'run-') === 0 || 
            strpos($filename, 'dev-multidev') === 0 || 
            $filename === 'run-playwright' ||
            $filename === 'install-drupal') {
            chmod($dest, 0755);
            $this->io->write(sprintf('  - Made executable: %s', str_replace(getcwd() . '/', '', $dest)));
        }
        
        $this->io->write(sprintf('  - Copied: %s', str_replace(getcwd() . '/', '', $dest)));
    }
    
    /**
     * Ensure the local-install ("box") Behat CI settings.local.php exists and is
     * tracked by git.
     *
     * The project-supplied .ci/test/behat/configure-site copies
     * .ci/test/behat/env/settings.local.php into web/sites/default/ before
     * installing Drupal. That file is almost always matched by a bare
     * `settings.local.php` rule in the project's .gitignore, so it never gets
     * committed and CI fails with "cp: cannot stat .../settings.local.php". We
     * generate a sane CI default (circle_test DB, the project's site UUID so
     * `drush config:import` doesn't fail on a UUID mismatch) and add a targeted
     * negation to .gitignore so it's tracked.
     *
     * No-op for projects that don't use the box model (no configure-site that
     * references settings.local.php), e.g. those running Behat against a
     * deployed multidev.
     *
     * @return void
     */
    protected function ensureBehatCiLocalSettings()
    {
        $root = $this->findProjectRoot();
        $configureSite = $root . '/.ci/test/behat/configure-site';

        if (!is_file($configureSite)) {
            return;
        }
        $configureContents = (string) @file_get_contents($configureSite);
        if (strpos($configureContents, 'settings.local.php') === false) {
            return;
        }

        $relPath = '.ci/test/behat/env/settings.local.php';
        $settingsFile = $root . '/' . $relPath;

        if (!is_file($settingsFile)) {
            $this->ensureDirectoryExists(dirname($settingsFile));
            $uuid = $this->detectSiteUuid($root);
            $syncDir = $this->detectConfigSyncDir($root);
            file_put_contents($settingsFile, $this->renderBehatLocalSettings($uuid, $syncDir));
            if ($uuid === '') {
                $this->io->write('  - WARNING: could not detect site UUID; set $settings[\'site_uuid\'] in ' . $relPath . ' or config:import will fail.');
            }
            $this->io->write(sprintf('  - Created Behat CI settings.local.php: %s', $relPath));
        } else {
            $this->io->write('  - Behat CI settings.local.php already present');
        }

        $this->ensurePathTracked($root, $relPath);
    }

    /**
     * Read the Drupal site UUID from the project's exported config.
     *
     * @param string $root Project root
     * @return string UUID, or '' if not found
     */
    protected function detectSiteUuid($root)
    {
        $candidates = [
            $root . '/config/sync/system.site.yml',
            $root . '/config/default/system.site.yml',
            $root . '/config/system.site.yml',
        ];
        foreach (glob($root . '/config/*/system.site.yml') ?: [] as $extra) {
            $candidates[] = $extra;
        }
        foreach ($candidates as $file) {
            if (!is_file($file)) {
                continue;
            }
            try {
                $data = \Symfony\Component\Yaml\Yaml::parseFile($file);
                if (is_array($data) && !empty($data['uuid'])) {
                    return (string) $data['uuid'];
                }
            } catch (\Throwable $e) {
                // Ignore and try the next candidate.
            }
        }
        return '';
    }

    /**
     * Determine the config sync directory for settings.local.php.
     *
     * Prefers an explicit value from settings.php; falls back to the common
     * Pantheon layout (config/ as a sibling of the web root).
     *
     * @param string $root Project root
     * @return string
     */
    protected function detectConfigSyncDir($root)
    {
        foreach (['web/sites/default/settings.php', 'sites/default/settings.php'] as $rel) {
            $file = $root . '/' . $rel;
            if (is_file($file)) {
                $contents = (string) @file_get_contents($file);
                if (preg_match('/config_sync_directory[\'"\]\s]*=\s*[\'"]([^\'"]+)[\'"]/', $contents, $m)) {
                    return $m[1];
                }
            }
        }
        return '../config/sync';
    }

    /**
     * Render the CI settings.local.php contents.
     *
     * @param string $uuid    Site UUID ('' to omit)
     * @param string $syncDir config_sync_directory value
     * @return string
     */
    protected function renderBehatLocalSettings($uuid, $syncDir)
    {
        $uuidLine = $uuid !== ''
            ? "\$settings['site_uuid'] = '" . $uuid . "';"
            : "// NOTE: site UUID not auto-detected. Set \$settings['site_uuid'] to match\n// config/sync/system.site.yml or `drush config:import` will fail.";

        $lines = [
            '<?php',
            '',
            '// @codingStandardsIgnoreFile',
            '',
            '/**',
            ' * @file',
            ' * Configuration overrides for the site when running Behat in CircleCI.',
            ' *',
            ' * Generated by helloworlddevs/pantheon-ci-tools so configure-site can copy',
            ' * it into web/sites/default/ in CI. Tracked intentionally (see the negation',
            ' * added to .gitignore).',
            ' */',
            '',
            "\$databases['default']['default'] = [",
            "  'database'  => 'circle_test',",
            "  'username'  => 'root',",
            "  'password'  => 'root',",
            "  'prefix'    => '',",
            "  'host'      => '127.0.0.1',",
            "  'port'      => '3306',",
            "  'namespace' => 'Drupal\\\\Core\\\\Database\\\\Driver\\\\mysql',",
            "  'driver'    => 'mysql',",
            '];',
            '',
            "\$settings['hash_salt'] = 'lorem-ipsum-123';",
            '',
            "\$settings['trusted_host_patterns'] = [",
            "  '^drupal-circleci-behat\\.localhost\$',",
            '];',
            '',
            '// Some tests check for a Pantheon environment.',
            "\$_ENV['PANTHEON_ENVIRONMENT'] = 'lando';",
            '',
            '// Disable CSS/JS aggregation.',
            "\$config['system.performance']['css']['preprocess'] = FALSE;",
            "\$config['system.performance']['js']['preprocess'] = FALSE;",
            '',
            "\$settings['file_temp_path'] = sys_get_temp_dir();",
            "\$settings['config_sync_directory'] = '" . $syncDir . "';",
            $uuidLine,
            '',
        ];

        return implode("\n", $lines);
    }

    /**
     * Ensure a path is not gitignored, by appending a targeted negation to the
     * project's root .gitignore when an existing pattern would ignore it.
     *
     * @param string $root    Project root
     * @param string $relPath Project-relative path to keep tracked
     * @return void
     */
    protected function ensurePathTracked($root, $relPath)
    {
        $gitignore = $root . '/.gitignore';
        $negation = '!/' . $relPath;
        $existing = is_file($gitignore) ? (string) file_get_contents($gitignore) : '';
        $lines = preg_split('/\R/', $existing) ?: [];

        foreach ($lines as $line) {
            $trimmed = trim($line);
            if ($trimmed === $negation || $trimmed === '!' . $relPath) {
                return; // Already un-ignored.
            }
        }

        if (!$this->isIgnoredByPatterns($lines, $relPath)) {
            return; // Nothing ignores it; leave .gitignore untouched.
        }

        $prefix = ($existing === '' || substr($existing, -1) === "\n") ? '' : "\n";
        $append = $prefix
            . "\n# Keep the Behat CI settings.local.php tracked (configure-site copies it in CI).\n"
            . $negation . "\n";

        file_put_contents($gitignore, $existing . $append);
        $this->io->write(sprintf('  - Un-ignored %s in .gitignore', $relPath));
    }

    /**
     * Heuristic check of whether .gitignore lines would ignore a relative path.
     *
     * Handles the common cases (bare basename rules like `settings.local.php`,
     * and slash-anchored path globs), honoring later-line precedence and `!`
     * negations the way git does.
     *
     * @param array  $lines   .gitignore lines
     * @param string $relPath Project-relative path
     * @return bool
     */
    protected function isIgnoredByPatterns(array $lines, $relPath)
    {
        $base = basename($relPath);
        $ignored = false;

        foreach ($lines as $line) {
            $pattern = trim($line);
            if ($pattern === '' || $pattern[0] === '#') {
                continue;
            }
            $negated = false;
            if ($pattern[0] === '!') {
                $negated = true;
                $pattern = ltrim(substr($pattern, 1));
            }
            $pattern = rtrim($pattern, '/');
            if ($pattern === '') {
                continue;
            }

            $matches = false;
            if (strpos($pattern, '/') !== false) {
                $anchored = ltrim($pattern, '/');
                $matches = fnmatch($anchored, $relPath, FNM_PATHNAME) || fnmatch($anchored, $relPath);
            } else {
                $matches = fnmatch($pattern, $base);
            }

            if ($matches) {
                $ignored = !$negated;
            }
        }

        return $ignored;
    }

    /**
     * Find the project root directory
     * 
     * This searches for composer.json going up directories until it finds
     * a non-package composer.json (the root project)
     * 
     * @return string Project root path
     * @throws \RuntimeException If project root cannot be determined
     */
    protected function findProjectRoot()
    {
        // Start with the current directory
        $dir = getcwd();
        
        // Output for debugging
        file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Starting directory search from: {$dir}\n");
        
        // Safety counter to prevent infinite loop
        $maxIterations = 10;
        $iterations = 0;
        
        while ($iterations < $maxIterations) {
            $iterations++;
            
            // Check if composer.json exists in this directory
            $composerFile = $dir . '/composer.json';
            file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Checking for composer.json at: {$composerFile}\n");
            
            if (file_exists($composerFile)) {
                $composerJson = json_decode(file_get_contents($composerFile), true);
                
                // If this is not our package and has no parent, it's likely the root project
                if (!isset($composerJson['name']) || $composerJson['name'] !== 'helloworlddevs/pantheon-ci-tools') {
                    file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Found project root: {$dir}\n");
                    return $dir;
                }
            }
            
            // Go up one directory
            $parentDir = dirname($dir);
            
            // If we've reached the filesystem root, stop
            if ($parentDir === $dir) {
                break;
            }
            
            $dir = $parentDir;
        }
        
        // If we couldn't find the project root, use the current working directory
        $fallbackDir = getcwd();
        $this->io->write(sprintf('  - Warning: Could not determine project root, using: %s', $fallbackDir));
        return $fallbackDir;
    }

    /**
     * Check if the project is a Drupal project
     * 
     * @return bool
     */
    protected function isDrupalProject()
    {
        $root = $this->findProjectRoot();
        
        // Check for composer.json dependencies
        if (file_exists($root . '/composer.json')) {
            $composerJson = json_decode(file_get_contents($root . '/composer.json'), true);
            if (isset($composerJson['require']['drupal/core']) || 
                isset($composerJson['require']['drupal/core-recommended']) ||
                isset($composerJson['require']['pantheon-systems/drupal-integrations'])) {
                return true;
            }
        }
        
        // Check for common Drupal files/directories if composer check fails or doesn't exist
        if (file_exists($root . '/web/core') || file_exists($root . '/core') || file_exists($root . '/sites')) {
            return true;
        }
        
        return false;
    }
}
