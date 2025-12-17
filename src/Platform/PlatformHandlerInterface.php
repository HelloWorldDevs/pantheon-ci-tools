<?php

namespace HelloWorldDevs\CI\Platform;

interface PlatformHandlerInterface
{
    /**
     * Get the platform identifier
     */
    public function getName(): string;

    /**
     * Get the display name for the platform
     */
    public function getDisplayName(): string;

    /**
     * Get the list of files to install for this platform
     * Returns an associative array: source path => destination path
     */
    public function getFilesToInstall(): array;

    /**
     * Get the URL pattern for environments
     * Placeholders: {env}, {site}, {project}, {region}
     */
    public function getEnvironmentUrlPattern(): string;

    /**
     * Get constraints for environment names
     * Returns: ['max_length' => int, 'pattern' => string, 'must_start_with_letter' => bool]
     */
    public function getEnvironmentNameConstraints(): array;

    /**
     * Get the CLI tool used for this platform
     */
    public function getCLITool(): string;

    /**
     * Get the CLI tool installation instructions
     */
    public function getCLIInstallInstructions(): string;

    /**
     * Format an environment name according to platform constraints
     */
    public function formatEnvironmentName(string $name): string;

    /**
     * Get the base path for platform files within the package
     */
    public function getFilesBasePath(): string;
}
