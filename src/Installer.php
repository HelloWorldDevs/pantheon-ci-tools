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
        // NOTE: Behat support is config-only. The behat_setup/behat_test jobs in
        // config.yml self-skip (circleci-agent step halt) unless the project
        // ships a tests/behat directory, and they call PROJECT-SUPPLIED scripts
        // under .ci/test/behat/ (configure-site, install-drupal, chrome.sh,
        // run-tests-circle). Those are inherently project-specific (Drupal
        // install steps, theme build, enabled modules), so the tool does not
        // ship generic copies — projects that want Behat provide their own.

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
            $filename === 'run-playwright') {
            chmod($dest, 0755);
            $this->io->write(sprintf('  - Made executable: %s', str_replace(getcwd() . '/', '', $dest)));
        }
        
        $this->io->write(sprintf('  - Copied: %s', str_replace(getcwd() . '/', '', $dest)));
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
