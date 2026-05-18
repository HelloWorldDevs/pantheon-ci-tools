#!/usr/bin/env bash

# Pre-deployment config safety check
# Run this before pushing to ensure config sync safety

# Change to project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT" || exit

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
if grep -q "devel: 0" config/sync/core.extension.yml || grep -q "reroute_email: 0" config/sync/core.extension.yml; then
    echo -e "${RED}✗ WARNING: Development modules found in main config${NC}"
    echo "  Development modules should only be in the dev config split"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No dev modules in main config${NC}"
fi

# Check 2: Ensure config split is properly configured
echo "2. Checking config split configuration..."
if [[ -f "config/sync/config_split.config_split.dev.yml" ]]; then
    if grep -q "status: false" config/sync/config_split.config_split.dev.yml; then
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
ENV_FILES=$(find config/sync/ -name "*\.dev\.yml" -o -name "*\.local\.yml" -o -name "*\.staging\.yml" -o -name "*\.prod\.yml" 2>/dev/null | grep -v "config_split.config_split" | head -5)
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
