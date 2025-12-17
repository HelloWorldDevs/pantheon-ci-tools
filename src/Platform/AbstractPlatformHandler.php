<?php

namespace HelloWorldDevs\CI\Platform;

use Composer\IO\IOInterface;

abstract class AbstractPlatformHandler implements PlatformHandlerInterface
{
    protected IOInterface $io;
    protected string $packageRoot;

    public function __construct(IOInterface $io, string $packageRoot)
    {
        $this->io = $io;
        $this->packageRoot = $packageRoot;
    }

    public function getFilesBasePath(): string
    {
        return $this->packageRoot . '/files/' . $this->getName();
    }

    public function formatEnvironmentName(string $name): string
    {
        $constraints = $this->getEnvironmentNameConstraints();

        // Convert to lowercase and replace invalid characters
        $formatted = strtolower($name);
        $formatted = preg_replace('/[^a-z0-9-]/', '-', $formatted);
        $formatted = preg_replace('/-+/', '-', $formatted);
        $formatted = trim($formatted, '-');

        // Ensure starts with letter if required
        if ($constraints['must_start_with_letter'] && !preg_match('/^[a-z]/', $formatted)) {
            $formatted = 'env-' . $formatted;
        }

        // Truncate to max length
        if (isset($constraints['max_length']) && strlen($formatted) > $constraints['max_length']) {
            $formatted = substr($formatted, 0, $constraints['max_length']);
            $formatted = rtrim($formatted, '-');
        }

        return $formatted;
    }

    /**
     * Build file list from platform directory
     */
    protected function buildFileList(): array
    {
        $basePath = $this->getFilesBasePath();
        $files = [];

        if (!is_dir($basePath)) {
            return $files;
        }

        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($basePath, \RecursiveDirectoryIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::SELF_FIRST
        );

        foreach ($iterator as $file) {
            if ($file->isFile()) {
                $relativePath = str_replace($basePath . '/', '', $file->getPathname());
                $files[$file->getPathname()] = $relativePath;
            }
        }

        return $files;
    }
}
