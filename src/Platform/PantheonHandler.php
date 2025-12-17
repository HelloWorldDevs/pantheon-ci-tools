<?php

namespace HelloWorldDevs\CI\Platform;

class PantheonHandler extends AbstractPlatformHandler
{
    public function getName(): string
    {
        return 'pantheon';
    }

    public function getDisplayName(): string
    {
        return 'Pantheon';
    }

    public function getFilesToInstall(): array
    {
        $basePath = $this->getFilesBasePath();

        return [
            // CircleCI
            $basePath . '/.circleci/config.yml' => '.circleci/config.yml',
            $basePath . '/.circleci/env_vars.sh' => '.circleci/env_vars.sh',

            // GitHub Actions
            $basePath . '/github/pr-multidev.yml' => '.github/workflows/pr-multidev.yml',
            $basePath . '/github/delete-multidev-on-merge.yml' => '.github/workflows/delete-multidev-on-merge.yml',

            // Scripts
            $basePath . '/scripts/dev-multidev.sh' => '.ci/scripts/dev-multidev.sh',
            $basePath . '/scripts/post_multidev_url.sh' => '.ci/scripts/post_multidev_url.sh',
            $basePath . '/scripts/setup_vars.sh' => '.ci/scripts/setup_vars.sh',
        ];
    }

    public function getEnvironmentUrlPattern(): string
    {
        return 'https://{env}-{site}.pantheonsite.io';
    }

    public function getEnvironmentNameConstraints(): array
    {
        return [
            'max_length' => 11,
            'pattern' => '/^[a-z0-9][a-z0-9-]*$/',
            'must_start_with_letter' => false,
        ];
    }

    public function getCLITool(): string
    {
        return 'terminus';
    }

    public function getCLIInstallInstructions(): string
    {
        return 'composer global require pantheon-systems/terminus';
    }
}
