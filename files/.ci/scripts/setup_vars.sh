# Set TERMINUS_SITE with fallback to project name
export TERMINUS_SITE="${TERMINUS_SITE:-${DEFAULT_SITE:-$CIRCLE_PROJECT_REPONAME}}"
echo "Using TERMINUS_SITE: $TERMINUS_SITE"

# Initialize JIRA_TICKET_ID and TERMINUS_ENV
JIRA_TICKET_ID="NO_TICKET"

# Extract Jira ticket ID from branch name (e.g., WAV-123)
if [[ "${CIRCLE_BRANCH}" =~ ([A-Z]{1,10}-[0-9]+) ]]; then
    JIRA_TICKET_ID="${BASH_REMATCH[0]}"
    echo "Found Jira ticket in branch name: $JIRA_TICKET_ID"
# Fallback to PR number if available
elif [[ -n "${CIRCLE_PULL_REQUEST}" ]]; then
    PR_NUMBER=$(echo "${CIRCLE_PULL_REQUEST}" | grep -oE '[0-9]+$' || echo "")
    if [[ -n "$PR_NUMBER" ]]; then
        JIRA_TICKET_ID="PR-$PR_NUMBER"
        echo "Using PR number as ticket ID: $JIRA_TICKET_ID"
    fi
fi

# Set environment based on branch type
echo "CIRCLE_BRANCH: $CIRCLE_BRANCH"
echo "JIRA_TICKET_ID: $JIRA_TICKET_ID"
echo "CIRCLE_PULL_REQUEST: $CIRCLE_PULL_REQUEST"

if [[ "$CIRCLE_BRANCH" == "master" ]]; then
    TERMINUS_ENV="dev"
    echo "Setting TERMINUS_ENV to 'dev' (master branch)"
elif [[ "$JIRA_TICKET_ID" != "NO_TICKET" ]]; then
    # Transform ticket ID for environment name (lowercase, max 11 chars)
    TERMINUS_ENV=$(echo "$JIRA_TICKET_ID" | tr '[:upper:]' '[:lower:]' | cut -c -11)
    echo "Setting TERMINUS_ENV to '$TERMINUS_ENV' (from JIRA ticket)"
elif [[ -n "$CIRCLE_PULL_REQUEST" ]]; then
    PR_NUMBER=$(echo "$CIRCLE_PULL_REQUEST" | grep -oE '[0-9]+$' || echo "0")
    echo "Extracted PR_NUMBER: $PR_NUMBER"
    if [[ "$PR_NUMBER" != "0" ]]; then
        TERMINUS_ENV="pr-${PR_NUMBER}"
        TERMINUS_ENV=$(echo "$TERMINUS_ENV" | tr '[:upper:]' '[:lower:]' | cut -c -11)
        echo "Setting TERMINUS_ENV to '$TERMINUS_ENV' (from PR)"
    else
        echo "WARNING: Could not extract PR number from CIRCLE_PULL_REQUEST"
    fi
else
    echo "WARNING: Could not determine TERMINUS_ENV from branch or PR"
fi

# Calculate multidev URL
echo "Calculating MULTIDEV_SITE_URL with JIRA_TICKET_ID: $JIRA_TICKET_ID and TERMINUS_ENV: $TERMINUS_ENV"

if [[ "$JIRA_TICKET_ID" != "NO_TICKET" ]]; then
    MULTIDEV_SITE_URL="https://${JIRA_TICKET_ID}-${TERMINUS_SITE}.pantheonsite.io"
    echo "Set MULTIDEV_SITE_URL from ticket ID: $MULTIDEV_SITE_URL"
else
    # Fallback to using TERMINUS_ENV for URL
    if [[ -z "$TERMINUS_ENV" ]]; then
        echo "WARNING: TERMINUS_ENV is empty, setting default"
        TERMINUS_ENV="dev"
    fi
    MULTIDEV_SITE_URL="https://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"
    echo "Set MULTIDEV_SITE_URL from TERMINUS_ENV: $MULTIDEV_SITE_URL"
fi

# Set dev URL (reference environment)
DEV_SITE_URL="https://dev-${TERMINUS_SITE}.pantheonsite.io"
echo "Set DEV_SITE_URL: $DEV_SITE_URL"

# Get Pantheon site ID from Terminus if not already set
if [ -z "${TERMINUS_SITE_ID}" ]; then
    echo "Getting site ID for $TERMINUS_SITE from Terminus..."
    # Ensure terminus is authenticated
    if terminus auth:whoami &>/dev/null; then
        # Get the site ID from Terminus
        TERMINUS_SITE_ID=$(terminus site:info "$TERMINUS_SITE" --field=id 2>/dev/null || echo "")
        if [ -n "$TERMINUS_SITE_ID" ]; then
            echo "Found Pantheon site ID: $TERMINUS_SITE_ID"
        else
            echo "Warning: Could not get site ID from Terminus. Using fallback value."
            TERMINUS_SITE_ID="56e65a7a-7d01-4e74-81b9-833ac434cea7"  # Fallback ID
        fi
    else
        echo "Warning: Terminus not authenticated. Using fallback site ID."
        TERMINUS_SITE_ID="56e65a7a-7d01-4e74-81b9-833ac434cea7"  # Fallback ID
    fi
fi

# Calculate the codeserver hostname from site ID and environment
CODESERVER_HOST="codeserver.$TERMINUS_ENV.$TERMINUS_SITE_ID.drush.in"
echo "Using codeserver host: $CODESERVER_HOST"

# Export all variables so they're available to other scripts
export TERMINUS_SITE
export TERMINUS_ENV
export TERMINUS_SITE_ID
export CODESERVER_HOST
export JIRA_TICKET_ID
export MULTIDEV_SITE_URL
export DEV_SITE_URL
export PR_NUMBER
