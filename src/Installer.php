<?php

namespace HelloWorldDevs\PantheonCI;

use Composer\Script\Event;

class Installer
{
    /**
     * Post package install callback
     *
     * @param Event $event
     * @return void
     */
    public static function postInstall(Event $event)
    {
        // Debug output to confirm this method is being called
        file_put_contents('php://stderr', "\n\n[PANTHEON-CI-DEBUG] postInstall() method called!\n");
        echo "\n\n[PANTHEON-CI] Starting installation...\n";
        self::copyFiles();
        echo "[PANTHEON-CI] Installation complete\n\n";
    }

    /**
     * Post package update callback
     *
     * @param Event $event
     * @return void
     */
    public static function postUpdate(Event $event)
    {
        // Debug output to confirm this method is being called
        file_put_contents('php://stderr', "\n\n[PANTHEON-CI-DEBUG] postUpdate() method called!\n");
        echo "\n\n[PANTHEON-CI] Starting update...\n";
        self::copyFiles();
        echo "[PANTHEON-CI] Update complete\n\n";
    }

    /**
     * Copy CI files to project root
     *
     * @return void
     */
    protected static function copyFiles()
    {
        file_put_contents('php://stderr', "\n[PANTHEON-CI-DEBUG] copyFiles() method started!\n");
        $sourceBase = dirname(__DIR__);
        $destBase = dirname(dirname(dirname(__DIR__)));
        
        file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Source base: {$sourceBase}\n");
        file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Destination base: {$destBase}\n");
        
        // Ensure destination directories exist
        self::ensureDirectoryExists($destBase . '/.circleci');
        self::ensureDirectoryExists($destBase . '/.ci/test/visual-regression');
        self::ensureDirectoryExists($destBase . '/.ci/scripts');
        
        // Copy CircleCI config
        self::copyFile(
            $sourceBase . '/files/.circleci/config.yml',
            $destBase . '/.circleci/config.yml'
        );
        
        // Skip .env.example copying for now
        // File will be added in a future version if needed
        
        // Copy test files
        self::copyFile(
            $sourceBase . '/files/.ci/test/visual-regression/playwright.config.js',
            $destBase . '/.ci/test/visual-regression/playwright.config.js'
        );
        
        self::copyFile(
            $sourceBase . '/files/.ci/test/visual-regression/playwright-tests.spec.js',
            $destBase . '/.ci/test/visual-regression/playwright-tests.spec.js'
        );
        
        // Copy script files
        self::copyFile(
            $sourceBase . '/files/.ci/scripts/setup_vars.sh',
            $destBase . '/.ci/scripts/setup_vars.sh'
        );
        
        echo "Pantheon CI files installed to project root!\n";
    }
    
    /**
     * Ensure a directory exists
     *
     * @param string $dir Directory path
     * @return void
     */
    protected static function ensureDirectoryExists($dir)
    {
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
            echo "Created directory: {$dir}\n";
        }
    }
    
    /**
     * Copy a file with path checking
     *
     * @param string $source Source file path
     * @param string $dest Destination file path
     * @return void
     */
    protected static function copyFile($source, $dest)
    {
        if (file_exists($source)) {
            copy($source, $dest);
            echo "Copied: {$source} → {$dest}\n";
        } else {
            echo "Warning: Source file not found: {$source}\n";
        }
    }
}
