#!/bin/bash

set -eo pipefail

# Validate required deploy variables early.
if [[ -z "${TERMINUS_TOKEN:-}" ]]; then
  echo "TERMINUS_TOKEN is required."
  exit 1
fi

if [[ -z "${TERMINUS_SITE:-}" ]]; then
  echo "TERMINUS_SITE is required."
  exit 1
fi

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
  if ! terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- cli info; then
    echo "Failed to run WP-CLI in ${TERMINUS_SITE}.${TERMINUS_ENV}. Verify WordPress is installed and environment is healthy."
    exit 1
  fi

  # Update the WordPress database
  echo "Running database updates..."
  if ! terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- core update-db; then
    echo "WordPress database update failed in ${TERMINUS_SITE}.${TERMINUS_ENV}."
    exit 1
  fi

  # Clear WordPress caches
  echo "Clearing WordPress caches..."
  if ! terminus -n wp "$TERMINUS_SITE.$TERMINUS_ENV" -- cache flush; then
    echo "WordPress cache flush failed in ${TERMINUS_SITE}.${TERMINUS_ENV}."
    exit 1
  fi
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
