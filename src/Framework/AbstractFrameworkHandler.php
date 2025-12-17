<?php

namespace HelloWorldDevs\CI\Framework;

use Composer\IO\IOInterface;

abstract class AbstractFrameworkHandler implements FrameworkHandlerInterface
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
        return $this->packageRoot . '/files/framework/' . $this->getName();
    }

    public function postInstall(string $projectRoot): void
    {
        // Default: no post-install actions
    }

    public function getConfigImportCommands(): array
    {
        // Default: no config import commands
        return [];
    }

    /**
     * Build file list from framework directory
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
