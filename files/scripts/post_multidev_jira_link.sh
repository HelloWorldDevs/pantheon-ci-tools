#!/usr/bin/env bash
#
# Add the multidev preview URL to the linked Jira issue as a REMOTE LINK,
# so it shows in the issue sidebar (under "Links") as "Multidev preview".
#
# Idempotent: the link is keyed on a stable globalId (site + env), so
# re-deploys of the same multidev UPDATE the existing link instead of
# piling up duplicates (Jira returns 200 for update, 201 for create).
#
# Required env vars:
#   JIRA_BASE_URL      - e.g. https://yourorg.atlassian.net
#   JIRA_USER          - Jira account email used for API auth
#   JIRA_TOKEN         - Jira API token
#   JIRA_TICKET_ID     - Set by setup_vars.sh from the branch name (e.g. WAV-123)
#   MULTIDEV_SITE_URL  - Set by setup_vars.sh
#   TERMINUS_SITE / TERMINUS_ENV - used to build the stable globalId
#
# This step is intentionally non-fatal: if credentials aren't configured or
# the Jira API call fails, we log and exit 0 so we never break the deploy
# over a Jira hiccup.

set -euo pipefail

# Master deploys to Pantheon dev, not a multidev — nothing to link.
if [ "${CIRCLE_BRANCH:-}" = "master" ]; then
  echo "Master branch — no multidev to link, skipping."
  exit 0
fi

# JIRA_TICKET_ID is set by setup_vars.sh. Skip placeholder values and the
# PR-derived fallback ("PR-123") since those aren't real Jira issue keys.
case "${JIRA_TICKET_ID:-}" in
  ""|NO_TICKET|PR-*)
    echo "JIRA_TICKET_ID='${JIRA_TICKET_ID:-}' is not a Jira issue key — skipping remote link."
    exit 0
    ;;
esac

if [ -z "${MULTIDEV_SITE_URL:-}" ]; then
  echo "MULTIDEV_SITE_URL is not set — skipping remote link."
  exit 0
fi

missing=0
for var in JIRA_BASE_URL JIRA_USER JIRA_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "⚠️  ${var} is not set — add it to a CircleCI context to enable Jira remote links."
    missing=1
  fi
done
if [ "${missing}" -eq 1 ]; then
  exit 0
fi

AUTH="$(printf '%s' "${JIRA_USER}:${JIRA_TOKEN}" | base64 | tr -d '\n')"
URL="${JIRA_BASE_URL%/}/rest/api/3/issue/${JIRA_TICKET_ID}/remotelink"

# Stable per-environment key: re-deploys of the same multidev update the
# existing sidebar link rather than creating a new one each build.
GLOBAL_ID="multidev:${TERMINUS_SITE:-site}:${TERMINUS_ENV:-env}"

PAYLOAD="$(jq -n \
  --arg globalId "${GLOBAL_ID}" \
  --arg url "${MULTIDEV_SITE_URL}" \
  --arg title "Multidev preview (${TERMINUS_ENV:-multidev})" \
  --arg summary "Pantheon multidev environment deployed by CircleCI for ${JIRA_TICKET_ID}" \
  '{
    globalId: $globalId,
    relationship: "deployed to",
    object: {
      url: $url,
      title: $title,
      summary: $summary,
      icon: {
        url16x16: "https://pantheon.io/favicon.ico",
        title: "Pantheon multidev"
      }
    }
  }')"

echo "Linking ${MULTIDEV_SITE_URL} on Jira ${JIRA_TICKET_ID}..."
# `|| true` so a transport-level curl failure (DNS, connect, TLS) doesn't
# abort the deploy under `set -e`; we still inspect the http code below.
HTTP_CODE="$(curl -sS -o /tmp/jira-remotelink-response.json -w '%{http_code}' -X POST \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data "${PAYLOAD}" \
  "${URL}" || true)"

case "${HTTP_CODE}" in
  201) echo "✅ Created multidev remote link on ${JIRA_TICKET_ID}" ;;
  200) echo "✅ Updated existing multidev remote link on ${JIRA_TICKET_ID}" ;;
  *)
    echo "❌ Failed to add Jira remote link (HTTP '${HTTP_CODE:-none}')"
    cat /tmp/jira-remotelink-response.json 2>/dev/null || true
    echo
    # Non-fatal: don't break the build over a Jira API hiccup.
    exit 0
    ;;
esac
