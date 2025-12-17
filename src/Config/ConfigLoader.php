<?php

namespace HelloWorldDevs\CI\Config;

use Composer\IO\IOInterface;

class ConfigLoader
{
    private const CONFIG_FILE = 'ci-tools.json';
    private const COMPOSER_EXTRA_KEY = 'ci-tools';

    private IOInterface $io;

    public function __construct(IOInterface $io)
    {
        $this->io = $io;
    }

    /**
     * Load configuration from ci-tools.json or composer.json extra section.
     * Priority: ci-tools.json > composer.json extra (via API) > default
     *
     * @param string $projectRoot Project root directory
     * @param array<string, mixed>|null $composerExtraConfig Config from Composer API (extra.ci-tools)
     */
    public function load(string $projectRoot, ?array $composerExtraConfig = null): CIConfig
    {
        // First, try ci-tools.json (allows override without touching composer.json)
        $configPath = $projectRoot . '/' . self::CONFIG_FILE;
        if (file_exists($configPath)) {
            $contents = file_get_contents($configPath);
            if ($contents !== false) {
                $data = json_decode($contents, true);
                if (is_array($data)) {
                    return CIConfig::fromArray($data);
                }
                $this->io->writeError(sprintf('<warning>  Invalid JSON in %s</warning>', self::CONFIG_FILE));
            } else {
                $this->io->writeError(sprintf('<warning>  Could not read %s</warning>', self::CONFIG_FILE));
            }
        }

        // Use config from Composer API if provided (the proper Composer way)
        if ($composerExtraConfig !== null) {
            return CIConfig::fromArray($composerExtraConfig);
        }

        return CIConfig::default();
    }

    public function hasConfigFile(string $projectRoot): bool
    {
        // Check ci-tools.json
        if (file_exists($projectRoot . '/' . self::CONFIG_FILE)) {
            return true;
        }

        // Check composer.json extra section
        $composerPath = $projectRoot . '/composer.json';
        if (file_exists($composerPath)) {
            $contents = file_get_contents($composerPath);
            if ($contents !== false) {
                $composerData = json_decode($contents, true);
                if (is_array($composerData) && isset($composerData['extra'][self::COMPOSER_EXTRA_KEY])) {
                    return true;
                }
            }
        }

        return false;
    }

    public function getConfigFilePath(string $projectRoot): string
    {
        return $projectRoot . '/' . self::CONFIG_FILE;
    }
}
