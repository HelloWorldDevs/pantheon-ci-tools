<?php

namespace HelloWorldDevs\CI\Platform;

class WPEngineHandler extends AbstractPlatformHandler
{
    public function getName(): string
    {
        return 'wpengine';
    }

    public function getDisplayName(): string
    {
        return 'WP Engine';
    }

    public function getFilesToInstall(): array
    {
        $basePath = $this->getFilesBasePath();

        return [
            // GitHub Actions
            $basePath . '/github/pr-deploy.yml' => '.github/workflows/pr-deploy.yml',
            $basePath . '/github/deploy-staging.yml' => '.github/workflows/deploy-staging.yml',

            // Scripts
            $basePath . '/scripts/deploy.sh' => '.ci/scripts/deploy.sh',
            $basePath . '/scripts/setup_vars.sh' => '.ci/scripts/setup_vars.sh',
        ];
    }

    public function getEnvironmentUrlPattern(): string
    {
        return 'https://{install}.wpengine.com';
    }

    public function getEnvironmentNameConstraints(): array
    {
        // WPEngine uses fixed environment names
        return [
            'max_length' => null,
            'pattern' => '/^(development|staging|production)$/',
            'must_start_with_letter' => false,
            'fixed_environments' => ['development', 'staging', 'production'],
        ];
    }

    public function getCLITool(): string
    {
        return 'git';
    }

    public function getCLIInstallInstructions(): string
    {
        return 'WP Engine uses git push for deployments. Configure your WP Engine git remote.';
    }

    public function formatEnvironmentName(string $name): string
    {
        // WPEngine has fixed environment names
        $name = strtolower($name);

        // Map common branch names to WPEngine environments
        $mappings = [
            'main' => 'production',
            'master' => 'production',
            'develop' => 'development',
            'dev' => 'development',
            'staging' => 'staging',
            'stage' => 'staging',
        ];

        if (isset($mappings[$name])) {
            return $mappings[$name];
        }

        // Default to development for feature branches
        return 'development';
    }
}
