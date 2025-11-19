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

# Detect webroot directory (html or web) by checking which contains Drupal
if [[ -d "/app/web/sites/default" ]]; then
    WEBROOT="/app/web"
elif [[ -d "/app/html/sites/default" ]]; then
    WEBROOT="/app/html"
elif [[ -d "/app/web" ]]; then
    # Fallback to web if directory exists (even without sites/default yet)
    WEBROOT="/app/web"
elif [[ -d "/app/html" ]]; then
    # Fallback to html if directory exists (even without sites/default yet)
    WEBROOT="/app/html"
else
    echo -e "${RED}ERROR: Could not find webroot directory (tried /app/web and /app/html).${NORMAL}"
    exit 1
fi

# Detect Drupal version from composer.json
detect_drupal_version() {
    if [[ -f "/app/composer.json" ]]; then
        local version=$(php -r "
            \$json = json_decode(file_get_contents('/app/composer.json'), true);
            if (isset(\$json['require']['drupal/core'])) {
                echo \$json['require']['drupal/core'];
            } elseif (isset(\$json['require']['drupal/core-recommended'])) {
                echo \$json['require']['drupal/core-recommended'];
            }
        ")
        
        # Extract major version number (e.g., "^10.2" or "~11.0" -> "10" or "11")
        if [[ $version =~ ([0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            echo "10"  # Default to 10 if can't detect
        fi
    else
        echo "10"  # Default to 10 if no composer.json
    fi
}

DRUPAL_VERSION=$(detect_drupal_version)

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
        if [[ ! -f "${WEBROOT}/sites/default/settings.local.php" ]]; then
            if [[ -f "${WEBROOT}/sites/default/default.settings.local.php" ]]; then
                cp ${WEBROOT}/sites/default/default.settings.local.php ${WEBROOT}/sites/default/settings.local.php
            else
                # Create a minimal settings.local.php if default doesn't exist
                echo -e "${YELLOW}Creating settings.local.php for Drupal ${DRUPAL_VERSION}...${NORMAL}"
                
                cat > ${WEBROOT}/sites/default/settings.local.php << 'EOFSTART'
<?php

/**
 * @file
 * Local development override configuration.
 *
 * To activate this feature, copy this file to settings.local.php
 */

// Disable CSS and JS aggregation.
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;

EOFSTART

                # Only add cache.backend.null settings for Drupal 10 and below
                if [[ $DRUPAL_VERSION -lt 11 ]]; then
                    cat >> ${WEBROOT}/sites/default/settings.local.php << 'EOFCACHE'
// Disable the render cache.
$settings['cache']['bins']['render'] = 'cache.backend.null';

// Disable caching for migrations.
$settings['cache']['bins']['discovery_migration'] = 'cache.backend.memory';

// Disable Internal Page Cache.
$settings['cache']['bins']['page'] = 'cache.backend.null';

// Disable Dynamic Page Cache.
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

EOFCACHE
                fi

                cat >> ${WEBROOT}/sites/default/settings.local.php << 'EOFEND'
// Allow test modules and themes to be installed.
$settings['extension_discovery_scan_tests'] = TRUE;

// Enable access to rebuild.php.
$settings['rebuild_access'] = TRUE;

// Skip file system permissions hardening.
$settings['skip_permissions_hardening'] = TRUE;
EOFEND
                echo -e "${GREEN}✅ Created new settings.local.php (Drupal ${DRUPAL_VERSION})${NORMAL}"
            fi
        fi

        # Remove cache.backend.null settings for Drupal 11+
        if [[ $DRUPAL_VERSION -ge 11 ]]; then
            echo -e "${YELLOW}Removing deprecated cache.backend.null settings for Drupal ${DRUPAL_VERSION}...${NORMAL}"
            php -r "
            \$file = '${WEBROOT}/sites/default/settings.local.php';
            if (file_exists(\$file)) {
                \$content = file_get_contents(\$file);
                
                // Remove the cache.backend.null lines
                \$content = preg_replace('/\/\/ Disable the render cache\.\s*\n\s*\\\$settings\[.cache.\]\[.bins.\]\[.render.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                \$content = preg_replace('/\/\/ Disable Internal Page Cache\.\s*\n\s*\\\$settings\[.cache.\]\[.bins.\]\[.page.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                \$content = preg_replace('/\/\/ Disable Dynamic Page Cache\.\s*\n\s*\\\$settings\[.cache.\]\[.bins.\]\[.dynamic_page_cache.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                
                // Also remove any standalone lines without comments
                \$content = preg_replace('/\\\$settings\[.cache.\]\[.bins.\]\[.render.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                \$content = preg_replace('/\\\$settings\[.cache.\]\[.bins.\]\[.page.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                \$content = preg_replace('/\\\$settings\[.cache.\]\[.bins.\]\[.dynamic_page_cache.\]\s*=\s*.cache\.backend\.null.;\s*\n/', '', \$content);
                
                file_put_contents(\$file, \$content);
                echo 'Removed deprecated cache settings';
            }
            "
        fi

        # Use PHP to safely modify the settings file
        php -r "
        \$file = '${WEBROOT}/sites/default/settings.local.php';
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
        if [[ -f "${WEBROOT}/sites/default/settings.local.php" ]]; then
            php -r "
            \$file = '${WEBROOT}/sites/default/settings.local.php';
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
