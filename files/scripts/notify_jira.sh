#!/bin/bash

set -euo pipefail

# Required environment variables
REQUIRED_VARS=(
  "JIRA_BASE_URL"
  "JIRA_USER"
  "JIRA_TOKEN"
  "ISSUE_KEY"
  "MESSAGE"
)

# Validate required variables
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Error: $var is not set"
    exit 1
  fi
done

# Optional link variables
LINK_TEXT="${LINK_TEXT:-}"
LINK_URL="${LINK_URL:-}"

echo "Posting to Jira issue ${ISSUE_KEY}..."

# Construct JSON payload (ADF)
# We use jq if available, otherwise manual string construction (risky but standard in minimal envs)
# Here we'll use a simple heredoc approach similar to post_multidev_url.sh

# Build the content array
CONTENT_JSON="[
  {
    \"type\": \"paragraph\",
    \"content\": [
      {
        \"type\": \"text\",
        \"text\": \"${MESSAGE}\"
      }"

if [ -n "$LINK_TEXT" ] && [ -n "$LINK_URL" ]; then
  CONTENT_JSON="${CONTENT_JSON},
      {
        \"type\": \"text\",
        \"text\": \" ${LINK_TEXT}\",
        \"marks\": [
          {
            \"type\": \"link\",
            \"attrs\": {
              \"href\": \"${LINK_URL}\"
            }
          }
        ]
      }"
fi

CONTENT_JSON="${CONTENT_JSON}
    ]
  }
]"

JIRA_PAYLOAD=$(cat <<EOF
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": ${CONTENT_JSON}
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
  echo "✅ Posted to Jira issue ${ISSUE_KEY}"
else
  echo "⚠️ Failed to post to Jira. HTTP Status: ${HTTP_STATUS}"
  exit 1
fi
