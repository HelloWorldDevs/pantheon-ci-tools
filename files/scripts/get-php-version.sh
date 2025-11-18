#!/bin/bash
set -euo pipefail

# Ensure jq is installed
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed. Please install jq to continue." >&2
  exit 1
fi

# Ensure composer.json exists
if [ ! -f composer.json ]; then
  echo "Error: composer.json not found in the current directory." >&2
  exit 1
fi
# Read PHP version from composer.json and select the corresponding Docker image tag.
# Defaults to 8.1 if not specified.
PHP_VERSION=$(jq -r '.require.php' composer.json | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -n 1)

if [ -z "$PHP_VERSION" ]; then
  echo "Warning: Could not determine PHP version from composer.json. Defaulting to PHP 8.1." >&2
fi
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
