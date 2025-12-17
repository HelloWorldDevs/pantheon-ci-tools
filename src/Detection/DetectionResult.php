<?php

namespace HelloWorldDevs\CI\Detection;

class DetectionResult
{
    public function __construct(
        public readonly ?string $platform,
        public readonly float $platformConfidence,
        public readonly ?string $framework,
        public readonly float $frameworkConfidence
    ) {}

    public function isComplete(): bool
    {
        return $this->platform !== null && $this->framework !== null;
    }

    public function needsManualConfig(): bool
    {
        return $this->platform === null || $this->platformConfidence < 0.8;
    }

    public function hasPlatform(): bool
    {
        return $this->platform !== null;
    }

    public function hasFramework(): bool
    {
        return $this->framework !== null;
    }
}
