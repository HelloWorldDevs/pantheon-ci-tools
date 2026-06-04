#!/usr/bin/env bash

# Pre-deployment config safety check
# Run this before pushing to ensure config sync safety

SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"

# Resolve to a directory that actually contains the sync dir. sync-prod-config.sh
# invokes this from the project root (CWD already has config/sync), so prefer
# the current directory; fall back to the git toplevel. Do NOT derive the root
# from this script's own location — it lives several levels deep under
# .ci/scripts/config_split, and the old `dirname` math landed in .ci/scripts,
# which is why earlier runs reported "config/sync/core.extension.yml: No such
# file or directory" and silently skipped the real checks.
if [ ! -d "$SYNC_DIR" ]; then
  GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$GITROOT" ] && [ -d "$GITROOT/$SYNC_DIR" ]; then
    cd "$GITROOT" || exit
  fi
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Pre-Deployment Config Safety Check${NC}"
echo "==================================="
echo "Working directory: $(pwd)"
echo ""

ERRORS=0

# Check 1: Ensure no dev modules are enabled in main config
echo "1. Checking for dev modules in core.extension.yml..."
if grep -q "devel: 0" "${SYNC_DIR}/core.extension.yml" || grep -q "reroute_email: 0" "${SYNC_DIR}/core.extension.yml"; then
    echo -e "${RED}✗ WARNING: Development modules found in main config${NC}"
    echo "  Development modules should only be in the dev config split"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No dev modules in main config${NC}"
fi

# Check 2: Ensure config split is properly configured
echo "2. Checking config split configuration..."
if [[ -f "${SYNC_DIR}/config_split.config_split.dev.yml" ]]; then
    if grep -q "status: false" "${SYNC_DIR}/config_split.config_split.dev.yml"; then
        echo -e "${GREEN}✓ Dev config split is disabled in main config${NC}"
    else
        echo -e "${RED}✗ ERROR: Dev config split is enabled in main config${NC}"
        echo "  This could enable dev modules on production!"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ No dev config split found${NC}"
fi

# Check 3: Verify environment-specific files aren't in sync (except config_split definitions)
echo "3. Checking for environment-specific config in sync..."
ENV_FILES=$(find "${SYNC_DIR}/" -name "*\.dev\.yml" -o -name "*\.local\.yml" -o -name "*\.staging\.yml" -o -name "*\.prod\.yml" 2>/dev/null | grep -v "config_split.config_split" | head -5)
if [[ -n "$ENV_FILES" ]]; then
    echo -e "${RED}✗ WARNING: Environment-specific config found in sync:${NC}"
    echo "$ENV_FILES"
    echo "  These should be in separate config split directories"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No problematic environment-specific config in main sync${NC}"
fi

# Check 4: Config sync directory is correct
# This relies on `lando drush` and is only meaningful in a local Lando env.
# Skip in CI (the merged config gets imported on the multidev itself).
echo "4. Checking config sync directory setting..."
if [[ -n "${CI:-}" ]]; then
    echo -e "${YELLOW}⚠ Skipping in CI (no Lando)${NC}"
elif cd html && lando drush status --field=config-sync 2>/dev/null | grep -q "../config/sync"; then
    echo -e "${GREEN}✓ Config sync directory correctly set${NC}"
else
    echo -e "${RED}✗ ERROR: Config sync directory not properly configured${NC}"
    echo "  Expected: ../config/sync"
    echo "  Current: $(cd html && lando drush status --field=config-sync 2>/dev/null || echo 'Unable to determine')"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Every module enabled in core.extension.yml must have code present.
# A module listed under `module:` whose <name>.info.yml is nowhere in the web
# root makes `drush config:import` fail with "Unable to install the X module
# since it does not exist" — exactly the cryptic deploy-time failure this
# pre-flight exists to prevent. Catching it here aborts the sync BEFORE the
# config is pushed/imported to the multidev.
echo "5. Checking enabled modules exist in the codebase..."
CORE_EXT="${SYNC_DIR}/core.extension.yml"
if [[ -f "$CORE_EXT" ]]; then
    # Locate the Drupal web root (honor WEB_ROOT from setup_vars.sh, else sniff).
    WEBROOT="${WEB_ROOT:-}"
    if [[ -z "$WEBROOT" || ! -d "${WEBROOT}/core" ]]; then
        for d in web html docroot .; do
            if [[ -d "$d/core" ]]; then WEBROOT="$d"; break; fi
        done
    fi

    if [[ -z "$WEBROOT" || ! -d "${WEBROOT}/core" ]]; then
        echo -e "${YELLOW}⚠ Could not locate Drupal web root — skipping module-existence check${NC}"
    else
        # Modules enabled in config: the indented `name: <weight>` keys in the
        # `module:` block, up to the next top-level key (e.g. `theme:`).
        ENABLED_MODULES=$(awk '
            /^module:/ {inblock=1; next}
            /^[^[:space:]]/ {inblock=0}
            inblock && /^[[:space:]]+[A-Za-z0-9_]+:[[:space:]]*-?[0-9]+[[:space:]]*$/ {
                line=$0; sub(/:.*/, "", line); gsub(/[[:space:]]/, "", line); print line
            }
        ' "$CORE_EXT")

        # Build the set of available module/profile machine names once (the
        # info.yml basename is the machine name). Restrict to Drupal code dirs
        # so we don't scan vendor/ or node_modules.
        SEARCH_DIRS=()
        for sub in core modules profiles; do
            [[ -d "${WEBROOT}/${sub}" ]] && SEARCH_DIRS+=("${WEBROOT}/${sub}")
        done
        AVAIL_FILE="$(mktemp)"
        if [[ ${#SEARCH_DIRS[@]} -gt 0 ]]; then
            find "${SEARCH_DIRS[@]}" -type f -name "*.info.yml" 2>/dev/null \
                | sed 's#.*/##; s/\.info\.yml$//' | sort -u > "$AVAIL_FILE"
        fi

        MISSING=""
        for m in $ENABLED_MODULES; do
            grep -qxF "$m" "$AVAIL_FILE" || MISSING="${MISSING} ${m}"
        done
        rm -f "$AVAIL_FILE"

        if [[ -n "${MISSING// /}" ]]; then
            echo -e "${RED}✗ ERROR: Modules enabled in config but missing from the codebase:${NC}"
            for m in $MISSING; do echo "    - ${m}"; done
            echo "  These will make 'drush config:import' fail. Fix one of:"
            echo "    • add the module to the codebase (e.g. composer require drupal/<module>), or"
            echo "    • uninstall it in production and re-export config, or"
            echo "    • remove it from ${CORE_EXT} (and its dependent config) on this branch."
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${GREEN}✓ All enabled modules are present in the codebase${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ ${CORE_EXT} not found — skipping module-existence check${NC}"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}🎉 All safety checks passed! Safe to deploy.${NC}"
    exit 0
else
    echo -e "${RED}❌ ${ERRORS} safety check(s) failed. Please fix before deploying.${NC}"
    echo ""
    echo "Common fixes:"
    echo "- Run 'lando drush config-split:deactivate dev' if dev split is accidentally active"
    echo "- Run 'lando drush cex -y' to export config after fixing"
    echo "- Ensure dev modules are only in profiles/wavemetrics/config/dev/"
    exit 1
fi
