<?php

namespace HelloWorldDevs\CI\Framework;

class WordPressHandler extends AbstractFrameworkHandler
{
    public function getName(): string
    {
        return 'wordpress';
    }

    public function getDisplayName(): string
    {
        return 'WordPress';
    }

    public function getFilesToInstall(): array
    {
        // WordPress-specific files will be added here
        // For now, return empty array as we don't have WP-specific CI files yet
        return [];
    }

    public function getWebRoot(): string
    {
        return '.';
    }

    public function getCacheClearCommands(): array
    {
        return [
            'wp cache flush',
        ];
    }

    public function getDatabaseMigrateCommands(): array
    {
        return [
            'wp core update-db',
        ];
    }

    public function getConfigImportCommands(): array
    {
        // WordPress doesn't have a standard config import mechanism
        return [];
    }
}
