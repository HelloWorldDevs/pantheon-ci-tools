#!/bin/bash

set -euo pipefail

# Exit immediately if this is the master branch
if [ "${CIRCLE_BRANCH:-}" = "master" ]; then
  echo "This is the master branch - skipping PR comment"
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
  echo "✅ Multidev URL was already posted to PR #${PR_NUMBER}. Skipping."
  exit 0
fi

# Post the comment to GitHub
curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "{\"body\": \"${COMMENT_BODY}\"}" \
  "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments"

echo "✅ Posted Multidev URL to PR #${PR_NUMBER}"
exit 0
