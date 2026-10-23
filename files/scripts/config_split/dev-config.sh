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

# Resolve the Drupal web root. Projects use either web/ or html/ (composer
# drupal-scaffold web-root), so never hardcode one. Lando exports
# LANDO_WEBROOT for the appserver; fall back to probing for sites/default.
WEBROOT="${LANDO_WEBROOT:-}"
if [[ -z "${WEBROOT}" || ! -d "${WEBROOT}/sites/default" ]]; then
    WEBROOT=""
    for candidate in /app/web /app/html; do
        if [[ -d "${candidate}/sites/default" ]]; then
            WEBROOT="${candidate}"
            break
        fi
    done
fi
if [[ -z "${WEBROOT}" ]]; then
    echo -e "${RED}ERROR: could not find the Drupal web root (tried \$LANDO_WEBROOT, /app/web, /app/html).${NORMAL}"
    exit 1
fi
SETTINGS_LOCAL="${WEBROOT}/sites/default/settings.local.php"

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

        # Ensure settings.local.php exists (seed from Drupal's default if present).
        if [[ ! -f "${SETTINGS_LOCAL}" ]]; then
            if [[ -f "${WEBROOT}/sites/default/default.settings.local.php" ]]; then
                cp "${WEBROOT}/sites/default/default.settings.local.php" "${SETTINGS_LOCAL}"
            else
                printf '<?php\n' > "${SETTINGS_LOCAL}"
            fi
        fi
        echo "Using ${SETTINGS_LOCAL}"

        # Use PHP to safely modify the settings file. Path comes in via env so
        # the PHP snippet stays single-quoted (no bash escaping of $).
        SETTINGS_LOCAL="${SETTINGS_LOCAL}" php -r '
        $file = getenv("SETTINGS_LOCAL");
        $content = file_get_contents($file);
        $on  = "\$config[\"config_split.config_split.dev\"][\"status\"] = TRUE;";
        $re  = "/\\\$config\\[.config_split\\.config_split\\.dev.\\]\\[.status.\\] = (TRUE|FALSE);/";
        if (preg_match($re, $content)) {
            $content = preg_replace($re, $on, $content);
        } else {
            $content .= PHP_EOL . "// Enable dev config split" . PHP_EOL . $on . PHP_EOL;
        }
        file_put_contents($file, $content);
        echo "Settings updated successfully", PHP_EOL;
        '

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

        # Flip the override off in settings.local.php (if present).
        if [[ -f "${SETTINGS_LOCAL}" ]]; then
            SETTINGS_LOCAL="${SETTINGS_LOCAL}" php -r '
            $file = getenv("SETTINGS_LOCAL");
            $content = file_get_contents($file);
            $off = "\$config[\"config_split.config_split.dev\"][\"status\"] = FALSE;";
            $re  = "/\\\$config\\[.config_split\\.config_split\\.dev.\\]\\[.status.\\] = TRUE;/";
            $content = preg_replace($re, $off, $content);
            file_put_contents($file, $content);
            echo "Settings updated successfully", PHP_EOL;
            '
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
