<?php

namespace HelloWorldDevs\CI\Framework;

interface FrameworkHandlerInterface
{
    /**
     * Get the framework identifier
     */
    public function getName(): string;

    /**
     * Get the display name for the framework
     */
    public function getDisplayName(): string;

    /**
     * Get the list of files to install for this framework
     * Returns an associative array: source path => destination path
     */
    public function getFilesToInstall(): array;

    /**
     * Get the web root directory for this framework
     */
    public function getWebRoot(): string;

    /**
     * Get cache clear commands for this framework
     */
    public function getCacheClearCommands(): array;

    /**
     * Get database migration commands for this framework
     */
    public function getDatabaseMigrateCommands(): array;

    /**
     * Get configuration import commands (if applicable)
     */
    public function getConfigImportCommands(): array;

    /**
     * Perform any post-installation steps
     */
    public function postInstall(string $projectRoot): void;

    /**
     * Get the base path for framework files within the package
     */
    public function getFilesBasePath(): string;
}
