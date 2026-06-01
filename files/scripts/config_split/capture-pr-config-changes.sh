#!/usr/bin/env bash
#
# Capture the list of config/sync files changed in this PR, BEFORE the
# deploy/build steps rewrite git state.
#
# Why this exists:
#   sync-prod-config.sh needs to know which config files the developer
#   changed in the PR so it can (a) protect them from being overwritten by
#   prod config and (b) report them as "Updated in this PR". It used to
#   compute that diff itself, but by the time it runs the working tree has
#   already been mutated by "Preparing code for Pantheon" (git add/commit)
#   and `terminus build:env:push` (artifact build + branch rewrite), so the
#   diff is no longer reliable. This script snapshots the list while the
#   checkout is still pristine; sync-prod-config.sh then reads it.
#
# Run this EARLY in the job — after `checkout` but before the
# "Preparing code for Pantheon" and "Deploying to Pantheon" steps.
#
# Env vars (all optional):
#   CONFIG_BASE_BRANCH (default: main)
#   CONFIG_SYNC_DIR    (default: config/sync)
#   PR_CHANGED_FILE    (default: /tmp/pr-changed-config.txt)
#   PR_BASE_DIR        (default: /tmp/pr-base-config) — base-branch copy of
#                      each PR-changed file, so the sync step can tell whether
#                      prod ALSO diverged (a conflict) vs. the dev simply
#                      editing a file prod left untouched. Files newly added in
#                      the PR have no base version and are skipped here.
#   CIRCLE_BRANCH      (used to skip on the default branch)

set -euo pipefail

BASE_BRANCH="${CONFIG_BASE_BRANCH:-main}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
OUT_FILE="${PR_CHANGED_FILE:-/tmp/pr-changed-config.txt}"
BASE_DIR="${PR_BASE_DIR:-/tmp/pr-base-config}"

# Always create the file so downstream steps can rely on it existing
# (an empty file means "no PR-changed config").
: > "${OUT_FILE}"

if [ "${CIRCLE_BRANCH:-}" = "${BASE_BRANCH}" ] || \
   [ "${CIRCLE_BRANCH:-}" = "master" ] || \
   [ "${CIRCLE_BRANCH:-}" = "main" ]; then
  echo "On default branch (${CIRCLE_BRANCH:-}); no PR config changes to capture."
  exit 0
fi

echo "==> Fetching ${BASE_BRANCH} to diff PR-changed config in ${SYNC_DIR}/"
git fetch --no-tags --depth=200 origin "${BASE_BRANCH}" >/dev/null 2>&1 || true

# Paths are emitted repo-relative (e.g. config/sync/system.site.yml), the
# same shape sync-prod-config.sh expects.
git diff --name-only --diff-filter=AMR \
  "origin/${BASE_BRANCH}...HEAD" -- "${SYNC_DIR}/" 2>/dev/null > "${OUT_FILE}" || true

COUNT="$(grep -c . "${OUT_FILE}" 2>/dev/null || echo 0)"
echo "==> Captured ${COUNT} PR-changed config file(s) to ${OUT_FILE}"
if [ "${COUNT}" -gt 0 ]; then
  sed 's/^/      - /' "${OUT_FILE}"
fi

# Snapshot the base-branch version of each PR-changed file (keyed by the same
# repo-relative path) so sync-prod-config.sh can detect prod conflicts. A file
# that's new in the PR has no base version and is simply absent here.
rm -rf "${BASE_DIR}"
mkdir -p "${BASE_DIR}"
BASE_SAVED=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if git cat-file -e "origin/${BASE_BRANCH}:${path}" 2>/dev/null; then
    mkdir -p "${BASE_DIR}/$(dirname "$path")"
    if git show "origin/${BASE_BRANCH}:${path}" > "${BASE_DIR}/${path}" 2>/dev/null; then
      BASE_SAVED=$((BASE_SAVED + 1))
    fi
  fi
done < "${OUT_FILE}"
echo "==> Saved ${BASE_SAVED} base-branch version(s) to ${BASE_DIR} (for conflict detection)"
