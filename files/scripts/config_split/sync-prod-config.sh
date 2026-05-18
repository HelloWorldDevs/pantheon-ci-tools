#!/usr/bin/env bash
#
# Sync Drupal config from the Pantheon live environment into the repo's
# config/sync/, preserving any config files modified in the current PR.
#
# Behavior:
#   - Exports config from $TERMINUS_SITE.live and downloads it.
#   - Detects config/sync/ files changed in the PR (vs the base branch).
#   - For every file from prod: write it to config/sync/ UNLESS the file
#     is in the PR-changed list (in which case the PR version wins).
#   - Files that exist only in the repo are left alone (never deleted).
#   - Commits the resulting config/sync/ changes, then pushes the merged
#     config to the multidev and runs `drush config:import`.
#
# Required env vars:
#   TERMINUS_SITE, TERMINUS_ENV
# Optional:
#   CONFIG_BASE_BRANCH (default: main)
#   CONFIG_SYNC_DIR    (default: config/sync)

set -euo pipefail

BASE_BRANCH="${CONFIG_BASE_BRANCH:-main}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
PROD_TMP="$(mktemp -d)"
trap 'rm -rf "$PROD_TMP"' EXIT

echo "==> Exporting config from ${TERMINUS_SITE}.live"
terminus drush "${TERMINUS_SITE}.live" -- \
  config:export --destination=/files/private/config-export -y

echo "==> Downloading exported config to ${PROD_TMP}"
terminus rsync "${TERMINUS_SITE}.live":files/private/config-export/ "${PROD_TMP}/"

mkdir -p "${SYNC_DIR}"

echo "==> Detecting PR-changed config files (base: ${BASE_BRANCH})"
# Make sure we have the base branch locally for the diff.
git fetch --no-tags --depth=200 origin "${BASE_BRANCH}" >/dev/null 2>&1 || true

# Files in config/sync/ touched by this PR (added/modified/renamed).
# Output is relative to repo root; we strip the SYNC_DIR/ prefix below.
mapfile -t PR_CHANGED < <(
  git diff --name-only --diff-filter=AMR \
    "origin/${BASE_BRANCH}...HEAD" -- "${SYNC_DIR}/" 2>/dev/null || true
)

declare -A PROTECTED=()
for f in "${PR_CHANGED[@]}"; do
  rel="${f#${SYNC_DIR}/}"
  PROTECTED["$rel"]=1
done

if [ "${#PROTECTED[@]}" -gt 0 ]; then
  echo "    Protected (PR-modified) files — keeping repo version:"
  for k in "${!PROTECTED[@]}"; do echo "      - $k"; done
else
  echo "    No PR-modified config files detected."
fi

echo "==> Merging prod config into ${SYNC_DIR}/"
WROTE=0
SKIPPED=0
ADDED=0
while IFS= read -r -d '' prod_file; do
  rel="${prod_file#${PROD_TMP}/}"
  dest="${SYNC_DIR}/${rel}"

  if [ -n "${PROTECTED[$rel]:-}" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  if [ ! -f "$dest" ]; then
    ADDED=$((ADDED + 1))
  fi
  cp "$prod_file" "$dest"
  WROTE=$((WROTE + 1))
done < <(find "${PROD_TMP}" -type f -print0)

echo "    wrote: ${WROTE}  (new: ${ADDED})   skipped (PR-protected): ${SKIPPED}"

echo "==> Committing merged config (if changed)"
git add "${SYNC_DIR}"
if git diff --cached --quiet; then
  echo "    No config changes to commit."
else
  git commit -m "Sync config from ${TERMINUS_SITE}.live (PR-modified files preserved)"
fi

echo "==> Uploading merged config to ${TERMINUS_SITE}.${TERMINUS_ENV}"
terminus rsync "./${SYNC_DIR}/" "${TERMINUS_SITE}.${TERMINUS_ENV}":files/config-sync/

echo "==> Importing config on ${TERMINUS_SITE}.${TERMINUS_ENV}"
terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- config:import -y

echo "==> Rebuilding caches"
terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- cache:rebuild

echo "==> Config sync complete."
