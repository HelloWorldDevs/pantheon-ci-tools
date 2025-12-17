<?php

namespace HelloWorldDevs\CI\Platform;

class UpsunHandler extends AbstractPlatformHandler
{
    public function getName(): string
    {
        return 'upsun';
    }

    public function getDisplayName(): string
    {
        return 'Upsun (Platform.sh)';
    }

    public function getFilesToInstall(): array
    {
        $basePath = $this->getFilesBasePath();

        return [
            // GitHub Actions
            $basePath . '/github/pr-environment.yml' => '.github/workflows/pr-environment.yml',
            $basePath . '/github/delete-environment.yml' => '.github/workflows/delete-environment.yml',

            // Scripts
            $basePath . '/scripts/deploy.sh' => '.ci/scripts/deploy.sh',
            $basePath . '/scripts/setup_vars.sh' => '.ci/scripts/setup_vars.sh',
        ];
    }

    public function getEnvironmentUrlPattern(): string
    {
        return 'https://{env}-{project}.{region}.platformsh.site';
    }

    public function getEnvironmentNameConstraints(): array
    {
        return [
            'max_length' => 63,
            'pattern' => '/^[a-z][a-z0-9-]*$/',
            'must_start_with_letter' => true,
        ];
    }

    public function getCLITool(): string
    {
        return 'platform';
    }

    public function getCLIInstallInstructions(): string
    {
        return 'curl -fsSL https://raw.githubusercontent.com/platformsh/cli/main/installer.sh | bash';
    }
}
