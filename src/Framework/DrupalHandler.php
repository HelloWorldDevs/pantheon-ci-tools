<?php

namespace HelloWorldDevs\CI\Framework;

class DrupalHandler extends AbstractFrameworkHandler
{
    public function getName(): string
    {
        return 'drupal';
    }

    public function getDisplayName(): string
    {
        return 'Drupal';
    }

    public function getFilesToInstall(): array
    {
        $basePath = $this->getFilesBasePath();

        return [
            // Config split scripts for Lando
            $basePath . '/scripts/config_split/dev-config.sh' => 'lando/scripts/dev-config.sh',
            $basePath . '/scripts/config_split/config-safety-check.sh' => 'lando/scripts/config-safety-check.sh',
            $basePath . '/scripts/config_split/update-lando-file.sh' => 'lando/scripts/update-lando-file.sh',
        ];
    }

    public function getWebRoot(): string
    {
        return 'web';
    }

    public function getCacheClearCommands(): array
    {
        return [
            'drush cr',
            'drush cache:rebuild',
        ];
    }

    public function getDatabaseMigrateCommands(): array
    {
        return [
            'drush updatedb -y',
            'drush updb -y',
        ];
    }

    public function getConfigImportCommands(): array
    {
        return [
            'drush config:import -y',
            'drush cim -y',
        ];
    }

    public function postInstall(string $projectRoot): void
    {
        // Check if config_split should be added to composer.json
        $composerFile = $projectRoot . '/composer.json';
        if (file_exists($composerFile)) {
            $composer = json_decode(file_get_contents($composerFile), true);

            $requireDev = $composer['require-dev'] ?? [];
            if (!isset($requireDev['drupal/config_split'])) {
                $this->io->write('  - Note: Consider adding drupal/config_split to your require-dev');
            }
        }
    }
}
