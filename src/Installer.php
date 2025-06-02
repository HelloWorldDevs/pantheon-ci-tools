<?php

namespace HelloWorldDevs\PantheonCI;

use Composer\Installer\PackageEvent;

class Installer
{
    /**
     * Post package install callback
     *
     * @param PackageEvent $event
     * @return void
     */
    public static function postInstall(PackageEvent $event)
    {
        self::copyFiles();
    }

    /**
     * Post package update callback
     *
     * @param PackageEvent $event
     * @return void
     */
    public static function postUpdate(PackageEvent $event)
    {
        self::copyFiles();
    }

    /**
     * Copy CI files to project root
     *
     * @return void
     */
    protected static function copyFiles()
    {
        $sourceBase = dirname(__DIR__);
        $destBase = dirname(dirname(dirname(__DIR__)));
        
        // Ensure destination directories exist
        self::ensureDirectoryExists($destBase . '/.circleci');
        self::ensureDirectoryExists($destBase . '/.ci/test/visual-regression');
        self::ensureDirectoryExists($destBase . '/.ci/scripts');
        
        // Copy CircleCI config
        self::copyFile(
            $sourceBase . '/files/.circleci/config.yml',
            $destBase . '/.circleci/config.yml'
        );
        
        // Copy environment example if it doesn't exist
        if (!file_exists($destBase . '/.env.example')) {
            self::copyFile(
                $sourceBase . '/.env.example',
                $destBase . '/.env.example'
            );
        }
        
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
