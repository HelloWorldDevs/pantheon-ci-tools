<?php

namespace HelloWorldDevs\CI\Config;

class CIConfig
{
    public const VRT_MODE_LFS = 'lfs';
    public const VRT_MODE_LIVE = 'live';
    public const VRT_MODE_DISABLED = 'disabled';

    public function __construct(
        public readonly ?string $platform = null,
        public readonly ?string $framework = null,
        public readonly bool $skipVRT = false,
        public readonly bool $skipJiraIntegration = false,
        public readonly bool $skipCircleCI = false,
        public readonly string $vrtMode = self::VRT_MODE_LFS,
        public readonly string $baselineBranch = 'main',
        public readonly array $excludeFiles = [],
        public readonly array $includeFiles = [],
        public readonly array $variables = [],
        public readonly bool $debug = false,
        public readonly ?string $projectRoot = null,
        public readonly ?string $testingUrl = null,
        public readonly ?string $updateUrl = null
    ) {}

    public static function fromArray(array $data): self
    {
        // Parse VRT options from nested structure
        $vrtOptions = $data['options']['vrt'] ?? [];
        $vrtMode = $vrtOptions['mode'] ?? self::VRT_MODE_LFS;
        $baselineBranch = $vrtOptions['baselineBranch'] ?? 'main';

        // If skipVRT is true, override vrtMode to disabled
        if ($data['options']['skipVRT'] ?? false) {
            $vrtMode = self::VRT_MODE_DISABLED;
        }

        return new self(
            platform: $data['platform'] ?? null,
            framework: $data['framework'] ?? null,
            skipVRT: $data['options']['skipVRT'] ?? false,
            skipJiraIntegration: $data['options']['skipJiraIntegration'] ?? false,
            skipCircleCI: $data['options']['skipCircleCI'] ?? false,
            vrtMode: $vrtMode,
            baselineBranch: $baselineBranch,
            excludeFiles: $data['excludeFiles'] ?? [],
            includeFiles: $data['includeFiles'] ?? [],
            variables: $data['variables'] ?? [],
            debug: $data['options']['debug'] ?? $data['debug'] ?? false,
            projectRoot: $data['projectRoot'] ?? null,
            testingUrl: $vrtOptions['testingUrl'] ?? $data['testingUrl'] ?? null,
            updateUrl: $vrtOptions['updateUrl'] ?? $data['updateUrl'] ?? null
        );
    }

    public static function default(): self
    {
        return new self();
    }

    public function hasPlatformOverride(): bool
    {
        return $this->platform !== null;
    }

    public function hasFrameworkOverride(): bool
    {
        return $this->framework !== null;
    }

    public function shouldExcludeFile(string $filename): bool
    {
        return in_array($filename, $this->excludeFiles, true);
    }

    public function toArray(): array
    {
        return [
            'platform' => $this->platform,
            'framework' => $this->framework,
            'options' => [
                'skipVRT' => $this->skipVRT,
                'skipJiraIntegration' => $this->skipJiraIntegration,
                'skipCircleCI' => $this->skipCircleCI,
                'vrt' => [
                    'mode' => $this->vrtMode,
                    'baselineBranch' => $this->baselineBranch,
                    'testingUrl' => $this->testingUrl,
                    'updateUrl' => $this->updateUrl,
                ],
            ],
            'excludeFiles' => $this->excludeFiles,
            'includeFiles' => $this->includeFiles,
            'variables' => $this->variables,
        ];
    }

    public function isVrtEnabled(): bool
    {
        return $this->vrtMode !== self::VRT_MODE_DISABLED && !$this->skipVRT;
    }

    public function isVrtLfsMode(): bool
    {
        return $this->vrtMode === self::VRT_MODE_LFS;
    }

    public function isVrtLiveMode(): bool
    {
        return $this->vrtMode === self::VRT_MODE_LIVE;
    }
}
