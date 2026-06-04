#!/bin/bash

set -eo pipefail

# Authenticate with Terminus
terminus -n auth:login --machine-token="$TERMINUS_TOKEN"

# Default branch check
if [[ "$CI_BRANCH" == "$DEFAULT_BRANCH" ]]; then
  TERMINUS_ENV=dev
  echo "Deploying to Dev environment..."
else
  # JIRA_TICKET_ID and PR_NUMBER are expected to be set by a previous step (e.g., setup_vars.sh)

  # Determine environment name based on JIRA_TICKET_ID or PR_NUMBER
  if [[ -n "${JIRA_TICKET_ID:-}" ]]; then
    # Sanitize JIRA_TICKET_ID to ensure it's lowercase and meets Pantheon's requirements
    TERMINUS_ENV=$(echo "$JIRA_TICKET_ID" | tr '[:upper:]' '[:lower:]' | cut -c -11)
    echo "Using Jira Ticket ID for Multidev Environment: $TERMINUS_ENV"
  elif [[ -n "${PR_NUMBER:-}" && "$PR_NUMBER" != "0" ]]; then
    # Use PR number with prefix, ensuring it's lowercase and meets Pantheon's requirements
    TERMINUS_ENV="pr-${PR_NUMBER}"
    TERMINUS_ENV=$(echo "$TERMINUS_ENV" | tr '[:upper:]' '[:lower:]' | cut -c -11)
    echo "Using PR Number for Multidev Environment: $TERMINUS_ENV"
  else
    echo "Neither Jira Ticket ID nor valid PR Number found. Cannot determine Multidev Environment name."
    exit 1
  fi
fi

# Strip nested .git directories left by Composer "source" installs. Dev/@dev
# branch versions (e.g. drupal/pdf:^1.0@dev) are git-cloned into place, not
# dist-unzipped, so they carry their own .git. The build:env:push below runs
# `git add` over the contrib/vendor tree and records any package with a nested
# .git as a gitlink (embedded repo) instead of committing its files — so that
# package's code never reaches the Pantheon artifact and `drush config:import`
# later fails with "Unable to install the <module> module since it does not
# exist". -mindepth 2 protects the project's own top-level .git while removing
# every nested one. Framework-agnostic (covers vendor/, web/, html/, etc.).
echo "Stripping nested .git directories so source-installed packages commit their files..."
NESTED_GIT=$(find . -mindepth 2 -name .git -prune 2>/dev/null || true)
if [ -n "$NESTED_GIT" ]; then
  echo "$NESTED_GIT" | sed 's/^/  removing: /'
  find . -mindepth 2 -name .git -prune -exec rm -rf {} + 2>/dev/null || true
else
  echo "  none found."
fi

# Check if the environment exists and push or create accordingly
if [[ "$TERMINUS_ENV" == "dev" ]] || terminus env:list "$TERMINUS_SITE" --field=id | grep -q "$TERMINUS_ENV"; then
  echo "Pushing to existing environment: $TERMINUS_ENV..."
  terminus -n build:env:push "$TERMINUS_SITE.$TERMINUS_ENV" --yes
else
  echo "Creating new Multidev: $TERMINUS_ENV..."
  terminus -n build:env:create "$TERMINUS_SITE.dev" "$TERMINUS_ENV" --yes
fi

# Detect Framework
FRAMEWORK="drupal"
if [ -f "wp-config.php" ] || [ -f "web/wp-config.php" ]; then
  FRAMEWORK="wordpress"
fi

if [ "$FRAMEWORK" == "drupal" ]; then
  # Diagnostic: Get Drush status for debugging
  echo "Drush status:"
  terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- status -vvv

  # Update the Drupal database
  echo "Running database updates..."
  terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- updatedb -y

  # Clear Drupal caches
  echo "Clearing Drupal caches..."
  terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- cr
elif [ "$FRAMEWORK" == "wordpress" ]; then
  # Diagnostic: Get WP-CLI info
  echo "WP-CLI info:"
  terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- cli info

  # Update the WordPress database
  echo "Running database updates..."
  terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- core update-db

  # Clear WordPress caches
  echo "Clearing WordPress caches..."
  terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- cache flush
fi

# Clear Pantheon environment cache
echo "Clearing Pantheon caches..."
terminus -n env:clear-cache "$TERMINUS_SITE.$TERMINUS_ENV"

# Set secrets (if needed)
echo "Setting secrets..."
terminus -n secrets:set "$TERMINUS_SITE.$TERMINUS_ENV" token "$GITHUB_TOKEN" --file='github-secrets.json' --clear --skip-if-empty

# Ensure connection mode is set to git
echo "Setting connection mode to git..."
terminus connection:set "$TERMINUS_SITE.$TERMINUS_ENV" git
