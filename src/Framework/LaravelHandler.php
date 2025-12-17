<?php

namespace HelloWorldDevs\CI\Framework;

class LaravelHandler extends AbstractFrameworkHandler
{
    public function getName(): string
    {
        return 'laravel';
    }

    public function getDisplayName(): string
    {
        return 'Laravel';
    }

    public function getFilesToInstall(): array
    {
        // Laravel-specific files will be added here
        // For now, return empty array as we don't have Laravel-specific CI files yet
        return [];
    }

    public function getWebRoot(): string
    {
        return 'public';
    }

    public function getCacheClearCommands(): array
    {
        return [
            'php artisan cache:clear',
            'php artisan config:clear',
            'php artisan route:clear',
            'php artisan view:clear',
        ];
    }

    public function getDatabaseMigrateCommands(): array
    {
        return [
            'php artisan migrate --force',
        ];
    }

    public function getConfigImportCommands(): array
    {
        return [
            'php artisan config:cache',
            'php artisan route:cache',
        ];
    }
}
