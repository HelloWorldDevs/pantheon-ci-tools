#!/bin/bash

set -euo pipefail

# Read PHP version from composer.json and select the corresponding Docker image tag.
# Defaults to 8.1 if not specified.
PHP_VERSION=$(jq -r '.require.php' composer.json | grep -oE '[0-9]+\.[0-9]+' | head -n 1)

case "$PHP_VERSION" in
  "8.0")
    echo "8.x-php8.0"
    ;;
  "7.4")
    echo "8.x-php7.4"
    ;;
  *)
    echo "8.x-php8.1"
    ;;
esac
