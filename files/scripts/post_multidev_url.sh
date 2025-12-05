#!/bin/bash

set -euo pipefail

# Detect CI Environment and normalize variables
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "Detected GitHub Actions environment"
  : "${CIRCLE_BRANCH:=${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}}"
  : "${CIRCLE_PROJECT_USERNAME:=${GITHUB_REPOSITORY_OWNER}}"
  # GITHUB_REPOSITORY is "owner/repo"
  : "${CIRCLE_PROJECT_REPONAME:=${GITHUB_REPOSITORY#*/}}"
fi

# Exit immediately if this is the master branch
if [ "${CIRCLE_BRANCH:-}" = "master" ] || [ "${CIRCLE_BRANCH:-}" = "main" ]; then
  echo "This is the main/master branch - skipping PR comment"
  exit 0
fi


# Required environment variables
REQUIRED_VARS=(
  "GITHUB_TOKEN"
  "CIRCLE_PROJECT_USERNAME"
  "CIRCLE_PROJECT_REPONAME"
  "PR_NUMBER"
  "MULTIDEV_SITE_URL"
)

# Validate required variables
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Error: $var is not set"
    exit 1
  fi
done

REPO="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"

# Check if this is a PR from a Jira ticket branch
ISSUE_KEY=""
if [[ "${CIRCLE_BRANCH:-}" =~ ([A-Z]{2,10}-[0-9]+) ]]; then
  ISSUE_KEY="${BASH_REMATCH[1]}"
  COMMENT_BODY="🔗 Multidev for ${ISSUE_KEY}: ${MULTIDEV_SITE_URL}"
else
  COMMENT_BODY="🔗 Multidev: ${MULTIDEV_SITE_URL}"
fi

# Check if a comment with this Multidev URL has already been posted
echo "Checking for existing comments with the Multidev URL..."
COMMENTS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments")

# Extract the comment body content and check if our Multidev URL is already there
if echo "${COMMENTS}" | grep -q "${MULTIDEV_SITE_URL}"; then
  echo "✅ Multidev URL was already posted to PR #${PR_NUMBER}. Skipping GitHub post."
else
  # Post the comment to GitHub
  curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "{\"body\": \"${COMMENT_BODY}\"}" \
    "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments"

  echo "✅ Posted Multidev URL to PR #${PR_NUMBER}"
fi

# Jira Integration
if [ -n "${ISSUE_KEY:-}" ] && [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_USER:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  echo "Checking for existing comments on Jira issue ${ISSUE_KEY}..."
  
  # Fetch existing comments from Jira
  JIRA_COMMENTS=$(curl -s -u "${JIRA_USER}:${JIRA_TOKEN}" \
    -H "Accept: application/json" \
    "${JIRA_BASE_URL}/rest/api/3/issue/${ISSUE_KEY}/comment")

  # Check if the Multidev URL is already in the comments
  if echo "${JIRA_COMMENTS}" | grep -q "${MULTIDEV_SITE_URL}"; then
    echo "✅ Multidev URL was already posted to Jira issue ${ISSUE_KEY}. Skipping."
  else
    echo "Posting Multidev URL to Jira issue ${ISSUE_KEY}..."
    
    # Construct JSON payload (ADF)
    JIRA_PAYLOAD=$(cat <<EOF
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "paragraph",
        "content": [
          {
            "type": "text",
            "text": "Multidev environment created: "
          },
          {
            "type": "text",
            "text": "${MULTIDEV_SITE_URL}",
            "marks": [
              {
                "type": "link",
                "attrs": {
                  "href": "${MULTIDEV_SITE_URL}"
                }
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF
)

    # Post to Jira
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      -u "${JIRA_USER}:${JIRA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${JIRA_PAYLOAD}" \
      "${JIRA_BASE_URL}/rest/api/3/issue/${ISSUE_KEY}/comment")

    if [ "$HTTP_STATUS" -eq 201 ]; then
      echo "✅ Posted Multidev URL to Jira issue ${ISSUE_KEY}"
    else
      echo "⚠️ Failed to post to Jira. HTTP Status: ${HTTP_STATUS}"
    fi
  fi
else
  echo "Skipping Jira comment (missing credentials or issue key)"
fi

exit 0
