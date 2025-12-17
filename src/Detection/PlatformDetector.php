<?php

namespace HelloWorldDevs\CI\Detection;

class PlatformDetector
{
    public const PANTHEON = 'pantheon';
    public const UPSUN = 'upsun';
    public const WPENGINE = 'wpengine';

    private const DETECTION_RULES = [
        self::PANTHEON => [
            'files' => ['pantheon.yml', 'pantheon.upstream.yml'],
            'confidence' => 1.0,
        ],
        self::UPSUN => [
            'files' => ['.upsun/config.yaml', '.platform.app.yaml', '.platform/routes.yaml'],
            'directories' => ['.upsun', '.platform'],
            'confidence' => 1.0,
        ],
        self::WPENGINE => [
            'files' => ['.wpengine-marker', 'wp-content/mu-plugins/wpengine-common/plugin.php'],
            'confidence' => 0.8,
        ],
    ];

    private ?string $detectedPlatform = null;
    private float $confidence = 0.0;

    public function detect(string $projectRoot): ?string
    {
        $this->detectedPlatform = null;
        $this->confidence = 0.0;

        // Get all directories to check (project root + parents up to git root)
        $searchPaths = $this->getSearchPaths($projectRoot);

        foreach (self::DETECTION_RULES as $platform => $rules) {
            foreach ($searchPaths as $searchPath) {
                if ($this->matchesPlatform($searchPath, $rules)) {
                    $this->detectedPlatform = $platform;
                    $this->confidence = $rules['confidence'];
                    return $platform;
                }
            }
        }

        return null;
    }

    /**
     * Get paths to search for platform markers.
     * Includes project root and parent directories up to git root.
     */
    private function getSearchPaths(string $projectRoot): array
    {
        $paths = [$projectRoot];
        $dir = $projectRoot;
        $maxIterations = 10;
        $iterations = 0;

        while ($iterations < $maxIterations) {
            $iterations++;

            // Check if we've reached the git root
            if (is_dir($dir . '/.git')) {
                // Include git root if different from project root
                if ($dir !== $projectRoot) {
                    $paths[] = $dir;
                }
                break;
            }

            $parentDir = dirname($dir);
            if ($parentDir === $dir) {
                break; // Reached filesystem root
            }
            $dir = $parentDir;
        }

        return $paths;
    }

    public function getConfidence(): float
    {
        return $this->confidence;
    }

    public function getDetectedPlatform(): ?string
    {
        return $this->detectedPlatform;
    }

    private function matchesPlatform(string $projectRoot, array $rules): bool
    {
        // Check for files
        if (isset($rules['files'])) {
            foreach ($rules['files'] as $file) {
                $path = $projectRoot . '/' . $file;
                if (file_exists($path)) {
                    return true;
                }
            }
        }

        // Check for directories
        if (isset($rules['directories'])) {
            foreach ($rules['directories'] as $dir) {
                $path = $projectRoot . '/' . $dir;
                if (is_dir($path)) {
                    return true;
                }
            }
        }

        return false;
    }

    public static function getSupportedPlatforms(): array
    {
        return [self::PANTHEON, self::UPSUN, self::WPENGINE];
    }
}
