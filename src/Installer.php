<?php

namespace HelloWorldDevs\CI;

use Composer\IO\IOInterface;
use HelloWorldDevs\CI\Detection\PlatformDetector;
use HelloWorldDevs\CI\Detection\FrameworkDetector;
use HelloWorldDevs\CI\Detection\DetectionResult;
use HelloWorldDevs\CI\Platform\PlatformHandlerInterface;
use HelloWorldDevs\CI\Platform\PantheonHandler;
use HelloWorldDevs\CI\Platform\UpsunHandler;
use HelloWorldDevs\CI\Platform\WPEngineHandler;
use HelloWorldDevs\CI\Framework\FrameworkHandlerInterface;
use HelloWorldDevs\CI\Framework\DrupalHandler;
use HelloWorldDevs\CI\Framework\WordPressHandler;
use HelloWorldDevs\CI\Framework\LaravelHandler;
use HelloWorldDevs\CI\Config\CIConfig;
use HelloWorldDevs\CI\Config\ConfigLoader;

class Installer
{
    protected IOInterface $io;
    protected string $packageRoot;
    protected PlatformDetector $platformDetector;
    protected FrameworkDetector $frameworkDetector;
    protected ConfigLoader $configLoader;
    protected CIConfig $config;

    /** @var array<string, mixed>|null Config from composer.json extra section */
    protected ?array $composerExtraConfig;

    /** @var int Count of files installed */
    protected int $filesInstalled = 0;

    /** @var int Count of files skipped */
    protected int $filesSkipped = 0;

    /** @var bool Force overwrite existing files */
    protected bool $forceOverwrite = false;

    public function __construct(IOInterface $io, ?array $composerExtraConfig = null, bool $forceOverwrite = false)
    {
        $this->io = $io;
        $this->packageRoot = dirname(__DIR__);
        $this->platformDetector = new PlatformDetector();
        $this->frameworkDetector = new FrameworkDetector();
        $this->configLoader = new ConfigLoader($io);
        $this->composerExtraConfig = $composerExtraConfig;
        $this->forceOverwrite = $forceOverwrite;
    }

    /**
     * Write debug output (only shown when debug mode is enabled)
     */
    protected function debug(string $message): void
    {
        if ($this->config->debug) {
            $this->io->write($message);
        }
    }

    /**
     * Main install method
     */
    public function install(): void
    {
        $composerRoot = $this->findProjectRoot();

        // Load configuration (priority: ci-tools.json > composer.json extra > default)
        $this->config = $this->configLoader->load($composerRoot, $this->composerExtraConfig);

        // Determine actual project root (may be different from composer location)
        $projectRoot = $this->resolveProjectRoot($composerRoot);

        $this->debug('  - Detecting platform and framework...');
        $this->debug(sprintf('  - Composer root: %s', $composerRoot));
        $this->debug(sprintf('  - Project root: %s', $projectRoot));

        // Use config overrides if present, otherwise detect
        $platform = $this->config->hasPlatformOverride()
            ? $this->config->platform
            : $this->platformDetector->detect($projectRoot);

        $framework = $this->config->hasFrameworkOverride()
            ? $this->config->framework
            : $this->frameworkDetector->detect($projectRoot);

        $result = new DetectionResult(
            $platform,
            $this->platformDetector->getConfidence(),
            $framework,
            $this->frameworkDetector->getConfidence()
        );

        $this->reportDetection($result);

        // Get handlers
        $platformHandler = $this->getPlatformHandler($platform);
        $frameworkHandler = $this->getFrameworkHandler($framework);

        // Install files
        $this->debug('  - Installing CI configuration files...');

        // Reset counters
        $this->filesInstalled = 0;
        $this->filesSkipped = 0;

        // 1. Install shared files (always)
        $this->installSharedFiles($projectRoot);

        // 2. Install platform-specific files
        if ($platformHandler) {
            $this->installPlatformFiles($platformHandler, $projectRoot);
        } else {
            $this->io->write('<warning>  No platform detected. Add "platform" to composer.json extra.ci-tools</warning>');
        }

        // 3. Install framework-specific files
        if ($frameworkHandler) {
            $this->installFrameworkFiles($frameworkHandler, $projectRoot);
            $frameworkHandler->postInstall($projectRoot);
        }

        // Show summary
        $this->io->write(sprintf('  Installed %d files, skipped %d', $this->filesInstalled, $this->filesSkipped));

        // Set up Git LFS if VRT is in LFS mode
        if ($this->config->isVrtLfsMode()) {
            $this->setupGitLfs($projectRoot);
        }
    }

    /**
     * Detect and set up Git LFS for VRT baselines
     */
    protected function setupGitLfs(string $projectRoot): void
    {
        // Skip LFS setup in container environments (Lando, Docker, CI)
        // LFS should be set up on the host machine where the repo is cloned
        if ($this->isRunningInContainer()) {
            $this->debug('  - Skipping Git LFS setup (running in container)');
            return;
        }

        $this->debug('  - Checking Git LFS setup...');

        // Check if git lfs is installed
        $lfsVersion = $this->execCommand('git lfs version 2>/dev/null');

        if ($lfsVersion === null || $lfsVersion === '') {
            // LFS not installed - provide installation instructions
            $this->io->write('<warning>  Git LFS is not installed. Install with: brew install git-lfs</warning>');
            return;
        }

        $this->debug(sprintf('  - Git LFS detected: %s', trim($lfsVersion)));

        // Check if LFS is initialized in this repo
        $lfsInstalled = $this->execCommand('git config --get filter.lfs.clean 2>/dev/null', $projectRoot);

        if ($lfsInstalled === null || $lfsInstalled === '') {
            $this->debug('  - Initializing Git LFS in repository...');
            $result = $this->execCommand('git lfs install 2>&1', $projectRoot);
            if ($result !== null) {
                $this->debug('<info>  - Git LFS initialized successfully</info>');
            } else {
                $this->io->write('<warning>  Failed to initialize Git LFS</warning>');
            }
        } else {
            $this->debug('  - Git LFS already initialized in repository');
        }

        // Check if .gitattributes has LFS tracking
        $gitattributes = $projectRoot . '/.gitattributes';
        $lfsTrackingLine = "**/playwright-tests.spec.js-snapshots/*.png filter=lfs diff=lfs merge=lfs -text";

        if (file_exists($gitattributes)) {
            $content = file_get_contents($gitattributes);
            if (str_contains($content, 'playwright-tests.spec.js-snapshots')) {
                $this->debug('  - LFS tracking already configured for VRT baselines');
            } else {
                $this->debug('  - Adding VRT baseline tracking to .gitattributes...');
                $lfsLine = "\n# VRT baseline images stored in Git LFS\n" . $lfsTrackingLine . "\n";
                file_put_contents($gitattributes, $content . $lfsLine);
                $this->debug('<info>  - LFS tracking configured for VRT baselines</info>');
            }
        } else {
            // Create .gitattributes with LFS tracking
            $this->debug('  - Creating .gitattributes with VRT LFS tracking...');
            $content = "# Git LFS Configuration for VRT Baselines\n";
            $content .= "# Generated by ci-tools\n\n";
            $content .= "# VRT baseline images stored in Git LFS\n";
            $content .= $lfsTrackingLine . "\n";
            file_put_contents($gitattributes, $content);
            $this->debug('<info>  - Created .gitattributes with LFS tracking</info>');
        }
    }

    /**
     * Execute a shell command and return the output
     */
    protected function execCommand(string $command, ?string $cwd = null): ?string
    {
        $originalDir = getcwd();

        if ($cwd !== null) {
            chdir($cwd);
        }

        $output = @shell_exec($command);

        if ($cwd !== null) {
            chdir($originalDir);
        }

        return $output !== false ? $output : null;
    }

    /**
     * Detect if running inside a container (Docker, Lando, CI, etc.)
     */
    protected function isRunningInContainer(): bool
    {
        // Lando
        if (getenv('LANDO') === 'ON' || getenv('LANDO_INFO')) {
            return true;
        }

        // Docker (check for .dockerenv or cgroup)
        if (file_exists('/.dockerenv')) {
            return true;
        }

        // Check cgroup for docker/container indicators
        if (file_exists('/proc/1/cgroup')) {
            $cgroup = @file_get_contents('/proc/1/cgroup');
            if ($cgroup && (str_contains($cgroup, 'docker') || str_contains($cgroup, 'lxc') || str_contains($cgroup, 'containerd'))) {
                return true;
            }
        }

        // CI environments (GitHub Actions, CircleCI, etc.)
        if (getenv('CI') || getenv('GITHUB_ACTIONS') || getenv('CIRCLECI')) {
            return true;
        }

        // Platform.sh / Upsun
        if (getenv('PLATFORM_APPLICATION') || getenv('PLATFORM_ENVIRONMENT')) {
            return true;
        }

        // Pantheon
        if (getenv('PANTHEON_ENVIRONMENT')) {
            return true;
        }

        return false;
    }

    protected function reportDetection(DetectionResult $result): void
    {
        $platformName = 'unknown';
        $frameworkName = 'unknown';

        if ($result->hasPlatform()) {
            $handler = $this->getPlatformHandler($result->platform);
            $platformName = $handler ? $handler->getDisplayName() : $result->platform;
            $this->debug(sprintf('  - Detected platform: %s (%d%% confidence)', $platformName, round($result->platformConfidence * 100)));
        } else {
            $this->debug('  - Platform: Not detected');
        }

        if ($result->hasFramework()) {
            $handler = $this->getFrameworkHandler($result->framework);
            $frameworkName = $handler ? $handler->getDisplayName() : $result->framework;
            $this->debug(sprintf('  - Detected framework: %s (%d%% confidence)', $frameworkName, round($result->frameworkConfidence * 100)));
        } else {
            $this->debug('  - Framework: Not detected');
        }

        // Always show concise summary
        $this->io->write(sprintf('  Platform: <info>%s</info>, Framework: <info>%s</info>',
            $result->hasPlatform() ? $platformName : '<comment>not detected</comment>',
            $result->hasFramework() ? $frameworkName : '<comment>not detected</comment>'
        ));
    }

    protected function getPlatformHandler(?string $platform): ?PlatformHandlerInterface
    {
        if ($platform === null) {
            return null;
        }

        return match ($platform) {
            PlatformDetector::PANTHEON => new PantheonHandler($this->io, $this->packageRoot),
            PlatformDetector::UPSUN => new UpsunHandler($this->io, $this->packageRoot),
            PlatformDetector::WPENGINE => new WPEngineHandler($this->io, $this->packageRoot),
            default => null,
        };
    }

    protected function getFrameworkHandler(?string $framework): ?FrameworkHandlerInterface
    {
        if ($framework === null) {
            return null;
        }

        return match ($framework) {
            FrameworkDetector::DRUPAL => new DrupalHandler($this->io, $this->packageRoot),
            FrameworkDetector::WORDPRESS => new WordPressHandler($this->io, $this->packageRoot),
            FrameworkDetector::LARAVEL => new LaravelHandler($this->io, $this->packageRoot),
            default => null,
        };
    }

    protected function installSharedFiles(string $projectRoot): void
    {
        $sharedBase = $this->packageRoot . '/files/shared';
        $allFiles = [];

        // VRT files (unless skipped)
        if ($this->config->isVrtEnabled()) {
            $vrtFiles = [
                $sharedBase . '/.ci/test/visual-regression/playwright.config.js' => '.ci/test/visual-regression/playwright.config.js',
                $sharedBase . '/.ci/test/visual-regression/playwright-tests.spec.js' => '.ci/test/visual-regression/playwright-tests.spec.js',
                $sharedBase . '/.ci/test/visual-regression/run-playwright' => '.ci/test/visual-regression/run-playwright',
                $sharedBase . '/.ci/test/visual-regression/update-baselines' => '.ci/test/visual-regression/update-baselines',
                $sharedBase . '/.ci/test/visual-regression/package.json' => '.ci/test/visual-regression/package.json',
                $sharedBase . '/.ci/test/visual-regression/package-lock.json' => '.ci/test/visual-regression/package-lock.json',
                $sharedBase . '/.ci/test/visual-regression/.gitignore' => '.ci/test/visual-regression/.gitignore',
            ];
            $allFiles = array_merge($allFiles, $vrtFiles);

            // VRT GitHub Actions workflow
            $allFiles[$sharedBase . '/github/vrt.yml'] = '.github/workflows/vrt.yml';

            // VRT runner script (legacy location)
            if (file_exists($sharedBase . '/.ci/scripts/run_vrt.sh')) {
                $allFiles[$sharedBase . '/.ci/scripts/run_vrt.sh'] = '.ci/scripts/run_vrt.sh';
            }

            // Test routes (skip if exists)
            $testRoutesSource = $sharedBase . '/test_routes.json';
            $testRoutesDest = $projectRoot . '/test_routes.json';
            if (!file_exists($testRoutesDest) && file_exists($testRoutesSource)) {
                $this->copyFile($testRoutesSource, $testRoutesDest);
            } elseif (file_exists($testRoutesDest)) {
                $this->debug('  - Skipped: test_routes.json (already exists)');
                $this->filesSkipped++;
            }

            // Note: .gitattributes LFS setup is handled by setupGitLfs() after all files are installed

            // Write VRT config file with default URLs if configured
            $this->writeVrtConfig($projectRoot);
        } else {
            $this->debug('  - Skipped VRT files (disabled in config)');
        }

        // Jira integration (unless skipped)
        if (!$this->config->skipJiraIntegration) {
            $allFiles[$sharedBase . '/.ci/scripts/notify_jira.sh'] = '.ci/scripts/notify_jira.sh';
            $allFiles[$sharedBase . '/github/pr-comments-to-jira.yml'] = '.github/workflows/pr-comments-to-jira.yml';
        } else {
            $this->debug('  - Skipped Jira integration files (disabled in config)');
        }

        foreach ($allFiles as $source => $dest) {
            // Check exclude list
            if ($this->config->shouldExcludeFile(basename($dest)) || $this->config->shouldExcludeFile($dest)) {
                $this->debug(sprintf('  - Skipped: %s (excluded in config)', $dest));
                $this->filesSkipped++;
                continue;
            }

            if (file_exists($source)) {
                $this->copyFile($source, $projectRoot . '/' . $dest, $this->forceOverwrite);
            }
        }
    }

    protected function installPlatformFiles(PlatformHandlerInterface $handler, string $projectRoot): void
    {
        $files = $handler->getFilesToInstall();

        foreach ($files as $source => $dest) {
            // Skip files that don't exist yet (placeholder for future implementation)
            if (!file_exists($source)) {
                $this->debug(sprintf('  - Skipped (not found): %s', basename($source)));
                $this->filesSkipped++;
                continue;
            }

            // Some files should only be copied if they don't exist (user may have customized)
            $skipIfExists = [
                'env_vars.sh',
            ];

            $destPath = $projectRoot . '/' . $dest;
            if (in_array(basename($dest), $skipIfExists) && file_exists($destPath)) {
                $this->debug(sprintf('  - Skipped: %s (already exists)', $dest));
                $this->filesSkipped++;
                continue;
            }

            $this->copyFile($source, $destPath, $this->forceOverwrite);
        }
    }

    protected function installFrameworkFiles(FrameworkHandlerInterface $handler, string $projectRoot): void
    {
        $files = $handler->getFilesToInstall();

        foreach ($files as $source => $dest) {
            if (!file_exists($source)) {
                $this->debug(sprintf('  - Skipped (not found): %s', basename($source)));
                $this->filesSkipped++;
                continue;
            }

            $this->copyFile($source, $projectRoot . '/' . $dest, $this->forceOverwrite);
        }
    }

    protected function ensureDirectoryExists(string $dir): void
    {
        if (!is_dir($dir)) {
            if (!@mkdir($dir, 0755, true) && !is_dir($dir)) {
                throw new \RuntimeException(sprintf('Directory "%s" was not created', $dir));
            }
            $this->debug(sprintf('  - Created directory: %s', $dir));
        }
    }

    protected function copyFile(string $source, string $dest, bool $overwrite = false): void
    {
        // Never touch snapshot directories (created by Playwright, tracked by Git LFS)
        if (str_contains($dest, '-snapshots')) {
            $this->debug(sprintf('  - Protected: %s (snapshot directory)', $this->relativePath($dest)));
            return;
        }

        if (!file_exists($source)) {
            throw new \RuntimeException(sprintf('Source file not found: %s', $source));
        }

        // Skip if destination exists and we're not forcing overwrite
        if (file_exists($dest) && !$overwrite) {
            $this->debug(sprintf('  - Skipped: %s (already exists)', $this->relativePath($dest)));
            $this->filesSkipped++;
            return;
        }

        $destDir = dirname($dest);
        if (!is_dir($destDir)) {
            $this->ensureDirectoryExists($destDir);
        }

        if (!copy($source, $dest)) {
            throw new \RuntimeException(sprintf('Failed to copy %s to %s', $source, $dest));
        }

        // Make scripts executable
        $filename = basename($dest);
        if (
            str_contains($filename, '.sh') ||
            str_starts_with($filename, 'run-') ||
            str_starts_with($filename, 'update-') ||
            $filename === 'run-playwright'
        ) {
            chmod($dest, 0755);
            $this->debug(sprintf('  - Made executable: %s', $this->relativePath($dest)));
        }

        $this->debug(sprintf('  - Copied: %s', $this->relativePath($dest)));
        $this->filesInstalled++;
    }

    protected function relativePath(string $path): string
    {
        $cwd = getcwd();
        if (str_starts_with($path, $cwd)) {
            return substr($path, strlen($cwd) + 1);
        }
        return $path;
    }

    /**
     * Write VRT config file with default URLs if configured
     */
    protected function writeVrtConfig(string $projectRoot): void
    {
        $testingUrl = $this->config->testingUrl;
        $updateUrl = $this->config->updateUrl;

        // Only write config if at least one URL is configured
        if ($testingUrl === null && $updateUrl === null) {
            return;
        }

        $configPath = $projectRoot . '/.ci/test/visual-regression/vrt-config.sh';
        $this->ensureDirectoryExists(dirname($configPath));

        $content = "#!/bin/bash\n";
        $content .= "# VRT Configuration - Generated by ci-tools\n";
        $content .= "# These are default URLs used when environment variables are not set\n\n";

        if ($testingUrl !== null) {
            $content .= "# Default URL for running VRT tests\n";
            $content .= sprintf("DEFAULT_TESTING_URL=\"%s\"\n\n", $testingUrl);
        }

        if ($updateUrl !== null) {
            $content .= "# Default URL for updating baselines\n";
            $content .= sprintf("DEFAULT_UPDATE_URL=\"%s\"\n", $updateUrl);
        }

        file_put_contents($configPath, $content);
        chmod($configPath, 0644);
        $this->debug('  - Created: .ci/test/visual-regression/vrt-config.sh');
        $this->filesInstalled++;
    }

    /**
     * Resolve the actual project root from config or default.
     * Supports relative paths (resolved from composer root) or absolute paths.
     */
    protected function resolveProjectRoot(string $composerRoot): string
    {
        if ($this->config->projectRoot === null) {
            return $composerRoot;
        }

        $configuredRoot = $this->config->projectRoot;

        // Handle relative paths (e.g., ".." or "../")
        if (!str_starts_with($configuredRoot, '/')) {
            $resolved = realpath($composerRoot . '/' . $configuredRoot);
            if ($resolved === false) {
                $this->io->writeError(sprintf('<warning>  Invalid projectRoot path: %s</warning>', $configuredRoot));
                return $composerRoot;
            }
            return $resolved;
        }

        // Absolute path
        if (!is_dir($configuredRoot)) {
            $this->io->writeError(sprintf('<warning>  projectRoot directory not found: %s</warning>', $configuredRoot));
            return $composerRoot;
        }

        return $configuredRoot;
    }

    protected function findProjectRoot(): string
    {
        $dir = getcwd();
        $maxIterations = 10;
        $iterations = 0;

        while ($iterations < $maxIterations) {
            $iterations++;
            $composerFile = $dir . '/composer.json';

            if (file_exists($composerFile)) {
                $composerJson = json_decode(file_get_contents($composerFile), true);

                // Skip our own package and look for the root project
                $name = $composerJson['name'] ?? '';
                if (!in_array($name, ['helloworlddevs/pantheon-ci-tools', 'helloworlddevs/ci-tools'])) {
                    return $dir;
                }
            }

            $parentDir = dirname($dir);
            if ($parentDir === $dir) {
                break;
            }
            $dir = $parentDir;
        }

        $this->debug('  - Warning: Could not determine project root, using current directory');
        return getcwd();
    }
}
