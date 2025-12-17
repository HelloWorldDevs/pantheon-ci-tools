<?php

namespace HelloWorldDevs\CI\Detection;

class FrameworkDetector
{
    public const DRUPAL = 'drupal';
    public const WORDPRESS = 'wordpress';
    public const LARAVEL = 'laravel';

    private const DETECTION_RULES = [
        self::DRUPAL => [
            'files' => [
                'web/core/lib/Drupal.php',
                'docroot/core/lib/Drupal.php',
                'core/lib/Drupal.php',
            ],
            'composer_require' => 'drupal/core',
            'confidence' => 1.0,
        ],
        self::WORDPRESS => [
            'files' => [
                'wp-config.php',
                'wp-content/index.php',
                'wp-includes/version.php',
            ],
            'composer_require' => 'johnpbloch/wordpress-core',
            'confidence' => 1.0,
        ],
        self::LARAVEL => [
            'files' => [
                'artisan',
                'app/Http/Kernel.php',
                'bootstrap/app.php',
            ],
            'composer_require' => 'laravel/framework',
            'confidence' => 1.0,
        ],
    ];

    private ?string $detectedFramework = null;
    private float $confidence = 0.0;

    public function detect(string $projectRoot): ?string
    {
        $this->detectedFramework = null;
        $this->confidence = 0.0;

        // First try file-based detection
        foreach (self::DETECTION_RULES as $framework => $rules) {
            if ($this->matchesFramework($projectRoot, $rules)) {
                $this->detectedFramework = $framework;
                $this->confidence = $rules['confidence'];
                return $framework;
            }
        }

        // Fall back to composer.json analysis
        $composerFile = $projectRoot . '/composer.json';
        if (file_exists($composerFile)) {
            $composer = json_decode(file_get_contents($composerFile), true);
            if ($composer) {
                $detected = $this->detectFromComposer($composer);
                if ($detected) {
                    return $detected;
                }
            }
        }

        return null;
    }

    public function getConfidence(): float
    {
        return $this->confidence;
    }

    public function getDetectedFramework(): ?string
    {
        return $this->detectedFramework;
    }

    private function matchesFramework(string $projectRoot, array $rules): bool
    {
        if (isset($rules['files'])) {
            foreach ($rules['files'] as $file) {
                $path = $projectRoot . '/' . $file;
                if (file_exists($path)) {
                    return true;
                }
            }
        }

        return false;
    }

    private function detectFromComposer(array $composer): ?string
    {
        $requires = array_merge(
            $composer['require'] ?? [],
            $composer['require-dev'] ?? []
        );

        foreach (self::DETECTION_RULES as $framework => $rules) {
            if (isset($rules['composer_require'])) {
                if (isset($requires[$rules['composer_require']])) {
                    $this->detectedFramework = $framework;
                    $this->confidence = 0.9; // Slightly lower confidence for composer-only detection
                    return $framework;
                }
            }
        }

        return null;
    }

    public function getWebRoot(string $framework): string
    {
        return match ($framework) {
            self::DRUPAL => 'web',
            self::WORDPRESS => '.',
            self::LARAVEL => 'public',
            default => '.',
        };
    }

    public static function getSupportedFrameworks(): array
    {
        return [self::DRUPAL, self::WORDPRESS, self::LARAVEL];
    }
}
