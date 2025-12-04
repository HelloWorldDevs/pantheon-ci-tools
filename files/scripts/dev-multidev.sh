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

# Export the resolved environment name for downstream steps (GitHub Actions, CircleCI, etc.)
echo "TERMINUS_ENV=$TERMINUS_ENV" >> "${GITHUB_OUTPUT:-/tmp/terminus_env.out}"

# Check if the environment exists and push or create accordingly
if [[ "$TERMINUS_ENV" == "dev" ]] || terminus env:list "$TERMINUS_SITE" --field=id | grep -q "$TERMINUS_ENV"; then
  echo "Pushing to existing environment: $TERMINUS_ENV..."
  terminus -n build:env:push "$TERMINUS_SITE.$TERMINUS_ENV" --yes
else
  echo "Creating new Multidev: $TERMINUS_ENV..."
  terminus -n build:env:create "$TERMINUS_SITE.dev" "$TERMINUS_ENV" --yes
fi
# Diagnostic: Get Drush status for debugging
echo "Drush status:"
terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- status -vvv

# Update the Drupal database
echo "Running database updates..."
terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- updatedb -y

# Clear Drupal caches
echo "Clearing Drupal caches..."
terminus -n drush "$TERMINUS_SITE.$TERMINUS_ENV" -- cr

# Clear Pantheon environment cache
echo "Clearing Pantheon caches..."
terminus -n env:clear-cache "$TERMINUS_SITE.$TERMINUS_ENV"

# Set secrets (if needed)
echo "Setting secrets..."
terminus -n secrets:set "$TERMINUS_SITE.$TERMINUS_ENV" token "$GITHUB_TOKEN" --file='github-secrets.json' --clear --skip-if-empty

# Ensure connection mode is set to git
echo "Setting connection mode to git..."
terminus connection:set "$TERMINUS_SITE.$TERMINUS_ENV" git
