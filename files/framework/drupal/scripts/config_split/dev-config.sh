#!/usr/bin/env bash

# Simple dev config management for Lando
# Usage:
#   ./dev-config.sh enable   - Enable dev modules
#   ./dev-config.sh disable  - Disable dev modules

ACTION="${1:-enable}"
FORCE="${2}"

# Colors for output
RED="\033[31m"
GREEN='\033[0;32m'
YELLOW="\033[33m"
NORMAL="\033[0m"

# Only enable dev config in Lando
if [[ -z "${LANDO_INFO}" ]]; then
    echo -e "${RED}ERROR: This script should only be run in Lando environments.${NORMAL}"
    exit 1
fi

wait_for_database() {
    echo -e "${YELLOW}⏳ Waiting for database to be ready...${NORMAL}"
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Test database connectivity by checking if Drupal can connect to DB
        if drush core:status 2>/dev/null | grep -q "Drupal version" ; then
            echo -e "${GREEN}✅ Database is ready${NORMAL}"
            return 0
        fi

        echo "   Attempt $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done

    echo -e "${RED}❌ Database not ready after $max_attempts attempts${NORMAL}"
    return 1
}

# For enable action, always wait for database. For disable, just do a quick check.
if [[ "$ACTION" == "enable" ]]; then
    if ! wait_for_database && [[ "$FORCE" != "-f" ]]; then
        echo -e "${YELLOW}⚠️  Database not ready. Skipping config operation.${NORMAL}"
        echo -e "${YELLOW}   Use '$0 $ACTION -f' to force if needed.${NORMAL}"
        exit 0
    fi
elif [[ "$ACTION" == "disable" ]] && ! drush core:status 2>/dev/null | grep -q "Drupal version" ; then
    if [[ "$FORCE" != "-f" ]]; then
        echo -e "${YELLOW}⚠️  Database not ready. Skipping config operation.${NORMAL}"
        echo -e "${YELLOW}   Use '$0 $ACTION -f' to force if needed.${NORMAL}"
        exit 0
    fi
fi

case "$ACTION" in
    "enable")
        echo -e "${YELLOW}🔧 Enabling dev config split...${NORMAL}"

        # Install git hooks on first enable (simple one-time setup)
        if [[ ! -f "/app/.git/hooks/pre-commit" ]] && [[ -f "/app/.githooks/pre-commit" ]]; then
            cp /app/.githooks/pre-commit /app/.git/hooks/pre-commit
            chmod +x /app/.git/hooks/pre-commit
            echo -e "${GREEN}✅ Git hooks installed for config safety${NORMAL}"
        fi

        # Use settings.local.php override (more persistent across DB pulls)
        echo -e "${YELLOW}Configuring dev split in settings.local.php...${NORMAL}"

        # Ensure settings.local.php exists
        if [[ ! -f "/app/html/sites/default/settings.local.php" ]]; then
            cp /app/html/sites/default/default.settings.local.php /app/html/sites/default/settings.local.php
        fi

        # Use PHP to safely modify the settings file
        php -r "
        \$file = '/app/html/sites/default/settings.local.php';
        \$content = file_get_contents(\$file);

        // Add config split overrides if they don't exist
        if (strpos(\$content, 'config_split.config_split.dev') === false) {
            \$content .= PHP_EOL . '// Enable dev config split' . PHP_EOL;
            \$content .= '\$config[\"config_split.config_split.dev\"][\"status\"] = TRUE;' . PHP_EOL;
        } else {
            // Update existing entries
            \$content = preg_replace('/\\\$config\[.config_split\.config_split\.dev.\]\[.status.\] = FALSE;/', '\$config[\"config_split.config_split.dev\"][\"status\"] = TRUE;', \$content);
        }

        file_put_contents(\$file, \$content);
        echo 'Settings updated successfully';
        "

        # Clear cache and activate
        drush cr

        if drush config-split:activate dev -y 2>/dev/null; then
            echo -e "${GREEN}✅ Dev modules enabled${NORMAL}"
        else
            echo -e "${YELLOW}⚠️  Dev config activation had issues (often missing dependencies)${NORMAL}"
            echo -e "${YELLOW}   Config override is in place, run 'drush cr' after installing dependencies${NORMAL}"
        fi
        ;;

    "disable")
        echo -e "${YELLOW}🔧 Disabling dev config split...${NORMAL}"

        # Remove from settings.local.php
        if [[ -f "/app/html/sites/default/settings.local.php" ]]; then
            php -r "
            \$file = '/app/html/sites/default/settings.local.php';
            \$content = file_get_contents(\$file);
            \$content = preg_replace('/\\\$config\[.config_split\.config_split\.dev.\]\[.status.\] = TRUE;/', '\$config[\"config_split.config_split.dev\"][\"status\"] = FALSE;', \$content);
            file_put_contents(\$file, \$content);
            echo 'Settings updated successfully';
            "
        fi

        drush config-split:deactivate dev -y 2>/dev/null || echo "Config split already inactive"
        drush cr
        echo -e "${GREEN}✅ Dev modules disabled${NORMAL}"
        ;;

    *)
        echo "Usage: $0 {enable|disable} [-f]"
        echo "  enable   - Enable dev modules"
        echo "  disable  - Disable dev modules"
        echo "  -f       - Force action even if database not ready"
        exit 1
        ;;
esac
