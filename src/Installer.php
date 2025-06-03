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
        
        // Get the correct source base (this package)
        $sourceBase = dirname(__DIR__);
        
        // Get the correct project root (find composer.json)
        $destBase = self::findProjectRoot();
        
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

        self::copyFile(
            $sourceBase . '/files/.ci/test/visual-regression/run-playwright',
            $destBase . '/.ci/test/visual-regression/run-playwright'
        );
        
        // Copy script files
        self::copyFile(
            $sourceBase . '/files/.ci/test/visual-regression/package.json',
            $destBase . '/.ci/test/visual-regression/package.json'
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
    
    /**
     * Find the project root directory
     * 
     * This searches for composer.json going up directories until it finds
     * a non-package composer.json (the root project)
     * 
     * @return string Project root path
     */
    protected static function findProjectRoot()
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
        
        // If we couldn't find the project root, default to current directory
        $fallbackDir = getcwd();
        file_put_contents('php://stderr', "[PANTHEON-CI-DEBUG] Could not determine project root, using fallback: {$fallbackDir}\n");
        return $fallbackDir;
    }
}
