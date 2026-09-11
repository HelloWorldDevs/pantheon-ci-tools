#!/usr/bin/env bash
# Build (and optionally push) the optional pre-baked Behat image for one PHP
# minor. Only needed if you decide to publish; see README.md.
#
#   ./build.sh 8.2            # local build, tagged ghcr.io/helloworlddevs/behat-php:8.2
#   ./build.sh 8.3 --push     # multi-arch build pushed to GHCR (needs `docker login ghcr.io`)
set -euo pipefail
PHP_VERSION="${1:?usage: build.sh <php-minor e.g. 8.2> [--push]}"
IMAGE="ghcr.io/helloworlddevs/behat-php:${PHP_VERSION}"
cd "$(dirname "$0")"
if [ "${2:-}" = "--push" ]; then
  docker buildx build --platform linux/amd64,linux/arm64 \
    --build-arg "PHP_VERSION=${PHP_VERSION}" -t "${IMAGE}" --push .
else
  docker buildx build --platform linux/amd64 \
    --build-arg "PHP_VERSION=${PHP_VERSION}" -t "${IMAGE}" --load .
fi
echo "Built ${IMAGE}"
