<?php

namespace HelloWorldDevs\PantheonCI;

use Composer\Composer;
use Composer\EventDispatcher\EventSubscriberInterface;
use Composer\IO\IOInterface;
use Composer\Plugin\PluginInterface;
use Composer\Script\Event;
use Composer\Script\ScriptEvents;

class Plugin implements PluginInterface, EventSubscriberInterface
{
    /**
     * @var Composer
     */
    protected $composer;

    /**
     * @var IOInterface
     */
    protected $io;

    /**
     * {@inheritDoc}
     */
    public function activate(Composer $composer, IOInterface $io)
    {
        $this->composer = $composer;
        $this->io = $io;
    }

    /**
     * {@inheritDoc}
     */
    public function deactivate(Composer $composer, IOInterface $io)
    {
        // Nothing to do here
    }

    /**
     * {@inheritDoc}
     */
    public function uninstall(Composer $composer, IOInterface $io)
    {
        $io->write('<info>Pantheon CI Tools: Cleaning up installed files...</info>');
        
        try {
            $this->cleanupInstalledFiles($io);
            $io->write('<info>✓ Pantheon CI Tools: Cleanup complete!</info>');
            $io->write('<comment>Note: .lando.yml modifications were preserved. You may want to manually remove the tooling commands and events.</comment>');
        } catch (\Exception $e) {
            $io->writeError(sprintf(
                '<error>Error during Pantheon CI Tools cleanup: %s</error>',
                $e->getMessage()
            ));
        }
    }

    /**
     * {@inheritDoc}
     */
    public static function getSubscribedEvents()
    {
        return [
            ScriptEvents::POST_INSTALL_CMD => 'onPostInstallUpdate',
            ScriptEvents::POST_UPDATE_CMD => 'onPostInstallUpdate',
        ];
    }

    /**
     * Handle post install/update events
     *
     * @param Event $event
     */
    public function onPostInstallUpdate(Event $event)
    {
        $this->io->write('<info>Pantheon CI Tools: Installing CI configuration files...</info>');
        
        try {
            $installer = new Installer($this->io);
            $installer->install();
            
            $this->io->write('<info>✓ Pantheon CI Tools: Installation complete!</info>');
        } catch (\Exception $e) {
            $this->io->writeError(sprintf(
                '<error>Error installing Pantheon CI Tools: %s</error>',
                $e->getMessage()
            ));
            throw $e;
        }
    }

    /**
     * Clean up files installed by this package
     *
     * @param IOInterface $io
     */
    protected function cleanupInstalledFiles(IOInterface $io)
    {
        $projectRoot = $this->findProjectRoot();
        
        $filesToRemove = [
            // Lando scripts
            'lando/scripts/dev-config.sh',
            'lando/scripts/config-safety-check.sh',
            // CI scripts
            '.ci/scripts/dev-multidev.sh',
            '.ci/scripts/post_multidev_url.sh',
            '.ci/scripts/setup_vars.sh',
            // CircleCI files
            '.circleci/config.yml',
            '.circleci/env_vars.sh',
            // GitHub workflows
            '.github/workflows/delete-multidev-on-merge.yml',
            '.github/workflows/pr-comments-to-jira.yml',
            // Test files
            '.ci/test/visual-regression/playwright.config.js',
            '.ci/test/visual-regression/playwright-tests.spec.js',
            '.ci/test/visual-regression/run-playwright',
            '.ci/test/visual-regression/package.json',
            '.ci/test/visual-regression/package-lock.json',
            // Test routes (only if not customized)
            'test_routes.json',
        ];
        
        $removedCount = 0;
        foreach ($filesToRemove as $file) {
            $fullPath = $projectRoot . '/' . $file;
            if (file_exists($fullPath)) {
                if (@unlink($fullPath)) {
                    $io->write(sprintf('  - Removed: %s', $file));
                    $removedCount++;
                } else {
                    $io->writeError(sprintf('  - Could not remove: %s', $file));
                }
            }
        }
        
        // Remove empty directories
        $dirsToRemove = [
            '.ci/test/visual-regression',
            '.ci/test',
            '.ci/scripts',
            '.ci',
            'lando/scripts',
        ];
        
        foreach ($dirsToRemove as $dir) {
            $fullPath = $projectRoot . '/' . $dir;
            if (is_dir($fullPath) && $this->isDirEmpty($fullPath)) {
                if (@rmdir($fullPath)) {
                    $io->write(sprintf('  - Removed empty directory: %s', $dir));
                }
            }
        }
        
        if ($removedCount > 0) {
            $io->write(sprintf('  - Removed %d file(s)', $removedCount));
        } else {
            $io->write('  - No files to remove (already cleaned up)');
        }
    }

    /**
     * Find the project root directory
     *
     * @return string Project root path
     */
    protected function findProjectRoot()
    {
        $dir = getcwd();
        $maxIterations = 10;
        $iterations = 0;
        
        while ($iterations < $maxIterations) {
            $iterations++;
            
            $composerFile = $dir . '/composer.json';
            if (file_exists($composerFile)) {
                $composerJson = json_decode(file_get_contents($composerFile), true);
                if (!isset($composerJson['name']) || $composerJson['name'] !== 'helloworlddevs/pantheon-ci-tools') {
                    return $dir;
                }
            }
            
            $parentDir = dirname($dir);
            if ($parentDir === $dir) {
                break;
            }
            $dir = $parentDir;
        }
        
        return getcwd();
    }

    /**
     * Check if directory is empty
     *
     * @param string $dir
     * @return bool
     */
    protected function isDirEmpty($dir)
    {
        if (!is_dir($dir)) {
            return false;
        }
        
        $handle = opendir($dir);
        while (false !== ($entry = readdir($handle))) {
            if ($entry != '.' && $entry != '..') {
                closedir($handle);
                return false;
            }
        }
        closedir($handle);
        return true;
    }
}
