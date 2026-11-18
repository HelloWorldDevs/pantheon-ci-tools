#!/usr/bin/env bash
# Print the Pantheon multidev environment name for a git branch.
#
# Usage: multidev-env-name.sh <branch> [pr-number]
#
# Uses the same rules as setup_vars.sh / dev-multidev.sh, which create the
# multidev, so the cleanup workflow deletes the environment CI made:
#   1. A Jira key anywhere in the branch (feature/ADS-706-security-updates)
#      -> the key, lowercased, max 11 chars (ads-706).
#   2. Otherwise, a PR number -> pr-<number>.
#   3. Otherwise (or on master/main, which deploy to dev) -> prints nothing.
set -euo pipefail

BRANCH="${1:-}"
PR_NUMBER="${2:-}"

case "$BRANCH" in
  master|main) exit 0 ;;
esac

if [[ "$BRANCH" =~ ([A-Z]{1,10}-[0-9]+) ]]; then
  NAME="${BASH_REMATCH[1]}"
elif [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  NAME="pr-${PR_NUMBER}"
else
  exit 0
fi

echo "$NAME" | tr '[:upper:]' '[:lower:]' | cut -c -11
