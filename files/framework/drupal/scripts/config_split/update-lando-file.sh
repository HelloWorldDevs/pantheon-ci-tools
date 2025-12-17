#!/usr/bin/env bash

set -euo pipefail

# This script updates the .lando.yml file with the following changes
# - Adds three new commands in tooling section:
#   - dev-config [enable|disable]
#   - safe-export
#   - config-check
#
# - Adds the following commands to pre-start event:
#   - appserver: echo "🔧 Setting up dev environment..."
#   - appserver: bash /app/lando/scripts/dev-config.sh enable
#
# - Adds the following commands to the post-pull event:
#   - appserver: bash /app/lando/scripts/dev-config.sh disable
#   - appserver: drush cr