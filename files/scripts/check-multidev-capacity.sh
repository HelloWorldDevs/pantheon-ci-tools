#!/bin/bash
#
# check-multidev-capacity.sh — pre-flight guard for Pantheon's multidev cap.
#
# Pantheon accounts have a hard limit on concurrent multidev environments
# (10 by default). When that cap is hit, `terminus build:env:create` fails
# deep inside the deploy — after we've already spent minutes building. This
# guard runs FIRST and aborts the pipeline early when there's no free slot,
# so the failure is fast and obvious instead of buried in a half-finished
# deploy.
#
# It is intentionally project-agnostic and mirrors the same ticket/PR →
# environment-name mapping that setup_vars.sh uses, so the slot it checks for
# is the slot the deploy would actually create.
#
# No-ops (exit 0, build proceeds) when:
#   - On the default branch (deploys to dev — consumes no multidev slot).
#   - No Jira ticket key or PR number maps to a multidev.
#   - This PR's multidev already exists (deploy reuses it — no new slot).
#   - TERMINUS_TOKEN is absent (can't query; don't block the build).
#
# Aborts (exit 1) only when a NEW slot is needed and the cap is full.
#
# Tunables (env):
#   MAX_MULTIDEVS    cap to enforce               (default 10)
#   DEFAULT_BRANCH   branch that deploys to dev   (auto-discovered from the
#                    remote; override here; falls back to master)
#   TERMINUS_SITE    Pantheon site machine name   (default: DEFAULT_SITE or repo name)
#   TERMINUS_TOKEN   Pantheon machine token       (required to query)
#
# Optional Jira comment when blocked (all three required, else skipped):
#   JIRA_BASE_URL, JIRA_USER, and JIRA_API_TOKEN (or JIRA_TOKEN)

set -eo pipefail

MAX_MULTIDEVS="${MAX_MULTIDEVS:-10}"
TERMINUS_SITE="${TERMINUS_SITE:-${DEFAULT_SITE:-$CIRCLE_PROJECT_REPONAME}}"

# Determine the repository's default branch (the one that deploys to dev and
# therefore consumes no multidev slot). Resolution order:
#   1. Explicit DEFAULT_BRANCH env var (configurable escape hatch).
#   2. Discovered from the remote — origin/HEAD if known locally, else asking
#      the remote directly. This keeps the tool correct on repos that use
#      `main`, `production`, etc. without any per-project configuration.
#   3. Fall back to "master".
detect_default_branch() {
  if [ -n "${DEFAULT_BRANCH:-}" ]; then
    printf '%s\n' "$DEFAULT_BRANCH"
    return
  fi
  local b=""
  b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  if [ -z "$b" ]; then
    b="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
  fi
  printf '%s\n' "${b:-master}"
}
DEFAULT_BRANCH="$(detect_default_branch)"
echo "Default branch: $DEFAULT_BRANCH"

# Default-branch builds deploy to dev — no multidev slot consumed.
if [[ "$CIRCLE_BRANCH" == "$DEFAULT_BRANCH" ]]; then
  echo "On default branch ($DEFAULT_BRANCH) — deploy targets dev, skipping multidev capacity check."
  exit 0
fi

if [ -z "${TERMINUS_TOKEN:-}" ]; then
  echo "TERMINUS_TOKEN is not set — cannot query Pantheon. Skipping capacity check (not blocking)."
  exit 0
fi

# Derive this PR's multidev name the same way setup_vars.sh / dev-multidev do:
# a Jira-style ticket key in the branch wins, else the PR number, both
# lowercased and clipped to Pantheon's 11-char environment-name limit.
JIRA_TICKET_ID=""
if [[ "$CIRCLE_BRANCH" =~ ([A-Z]{1,10}-[0-9]+) ]]; then
  JIRA_TICKET_ID="${BASH_REMATCH[0]}"
fi
PR_NUMBER=$(echo "${CIRCLE_PULL_REQUEST:-}" | grep -oE '[0-9]+$' || echo "")

if [[ -n "$JIRA_TICKET_ID" ]]; then
  TARGET_ENV=$(echo "$JIRA_TICKET_ID" | tr '[:upper:]' '[:lower:]' | cut -c -11)
elif [[ -n "$PR_NUMBER" ]]; then
  TARGET_ENV=$(echo "pr-${PR_NUMBER}" | cut -c -11)
else
  echo "No Jira ticket key or PR number — deploy won't create a multidev. Skipping capacity check."
  exit 0
fi

terminus -n auth:login --machine-token="$TERMINUS_TOKEN"

MULTIDEVS=$(terminus multidev:list "$TERMINUS_SITE" --format=list)
COUNT=$(printf '%s\n' "$MULTIDEVS" | grep -c . || true)
echo "Found $COUNT multidev(s) on $TERMINUS_SITE:"
printf '%s\n' "$MULTIDEVS"
echo "Target multidev for this build: $TARGET_ENV"

# If this PR's multidev already exists, the deploy reuses it — no new slot.
if printf '%s\n' "$MULTIDEVS" | grep -qx "$TARGET_ENV"; then
  echo "Multidev '$TARGET_ENV' already exists — will be reused. Proceeding."
  exit 0
fi

if [ "$COUNT" -lt "$MAX_MULTIDEVS" ]; then
  echo "Capacity OK ($COUNT/$MAX_MULTIDEVS). Proceeding."
  exit 0
fi

echo "Pantheon multidev cap reached ($COUNT/$MAX_MULTIDEVS). Aborting before build."

# Optional: leave a breadcrumb on the Jira ticket so the dev knows why the
# build stopped. Self-skips unless a real ticket key and all creds are present.
JIRA_API_TOKEN="${JIRA_API_TOKEN:-${JIRA_TOKEN:-}}"
if [[ -z "$JIRA_TICKET_ID" ]]; then
  echo "No Jira ticket key in branch name — skipping Jira comment."
elif [[ -n "$JIRA_BASE_URL" && -n "$JIRA_USER" && -n "$JIRA_API_TOKEN" ]]; then
  # Strip stray whitespace/newlines that can sneak in via the CircleCI UI.
  JIRA_BASE_URL=$(printf '%s' "$JIRA_BASE_URL" | tr -d '[:space:]')
  JIRA_USER=$(printf '%s' "$JIRA_USER" | tr -d '[:space:]')
  JIRA_API_TOKEN=$(printf '%s' "$JIRA_API_TOKEN" | tr -d '[:space:]')
  MSG="Build halted: Pantheon multidev capacity reached ($COUNT/$MAX_MULTIDEVS). Free up a multidev (or merge/close an open PR) and re-run the pipeline."
  echo "Posting comment to Jira issue $JIRA_TICKET_ID"
  HTTP_CODE=$(curl -sS -o /tmp/jira_resp.txt -w "%{http_code}" -u "$JIRA_USER:$JIRA_API_TOKEN" \
    -X POST \
    -H "Content-Type: application/json" \
    --data "{\"body\":\"${MSG}\"}" \
    "${JIRA_BASE_URL%/}/rest/api/2/issue/${JIRA_TICKET_ID}/comment") || HTTP_CODE="000"
  echo "Jira REST HTTP $HTTP_CODE"
  cat /tmp/jira_resp.txt 2>/dev/null || true
  echo
  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "Jira comment failed (continuing to abort)."
  fi
else
  echo "Skipping Jira comment (need JIRA_BASE_URL, JIRA_USER, and JIRA_API_TOKEN/JIRA_TOKEN)."
fi

exit 1
