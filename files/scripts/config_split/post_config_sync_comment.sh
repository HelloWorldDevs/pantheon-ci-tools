#!/usr/bin/env bash
#
# Post the config-sync report as a comment on the current PR.
#
# The existing `.github/workflows/pr-comments-to-jira.yml` workflow will
# mirror this comment onto the Jira ticket referenced in the PR.
#
# Required env vars:
#   GITHUB_TOKEN, PR_NUMBER, CIRCLE_PROJECT_USERNAME, CIRCLE_PROJECT_REPONAME
# Optional:
#   CONFIG_SYNC_REPORT (default: /tmp/config-sync-report.md)

set -euo pipefail

REPORT_FILE="${CONFIG_SYNC_REPORT:-/tmp/config-sync-report.md}"

if [ "${CIRCLE_BRANCH:-}" = "master" ] || [ "${CIRCLE_BRANCH:-}" = "main" ]; then
  echo "On default branch — skipping PR comment."
  exit 0
fi

if [ -z "${PR_NUMBER:-}" ]; then
  echo "PR_NUMBER not set — skipping PR comment."
  exit 0
fi

if [ ! -s "${REPORT_FILE}" ]; then
  echo "No report file at ${REPORT_FILE} — skipping PR comment."
  exit 0
fi

for var in GITHUB_TOKEN CIRCLE_PROJECT_USERNAME CIRCLE_PROJECT_REPONAME; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Error: $var is not set"
    exit 1
  fi
done

REPO="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"

# JSON-encode the markdown body safely.
BODY_JSON="$(python3 -c '
import json, os, sys
with open(os.environ["REPORT_FILE"]) as f:
    print(json.dumps({"body": f.read()}))
')"

echo "Posting config-sync report to PR #${PR_NUMBER}..."
HTTP_CODE=$(curl -s -o /tmp/pr-comment-response.json -w "%{http_code}" -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "${BODY_JSON}" \
  "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/comments")

if [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Posted config-sync report to PR #${PR_NUMBER}"
else
  echo "❌ Failed to post comment (HTTP ${HTTP_CODE})"
  cat /tmp/pr-comment-response.json
  exit 1
fi
