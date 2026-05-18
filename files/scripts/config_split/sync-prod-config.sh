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
#   - Writes a markdown summary of applied/added/protected files to
#     $CONFIG_SYNC_REPORT for downstream PR/Jira commenting.
#
# Required env vars:
#   TERMINUS_SITE, TERMINUS_ENV
# Optional:
#   CONFIG_BASE_BRANCH (default: main)
#   CONFIG_SYNC_DIR    (default: config/sync)
#   CONFIG_SYNC_REPORT (default: /tmp/config-sync-report.md)

set -euo pipefail

BASE_BRANCH="${CONFIG_BASE_BRANCH:-main}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
REPORT_FILE="${CONFIG_SYNC_REPORT:-/tmp/config-sync-report.md}"
PROD_TMP="$(mktemp -d)"
trap 'rm -rf "$PROD_TMP"' EXIT

echo "==> Exporting config from ${TERMINUS_SITE}.live"
terminus drush "${TERMINUS_SITE}.live" -- \
  config:export --destination=/files/private/config-export -y

echo "==> Downloading exported config to ${PROD_TMP}"
terminus rsync "${TERMINUS_SITE}.live":files/private/config-export/ "${PROD_TMP}/"

mkdir -p "${SYNC_DIR}"

echo "==> Detecting PR-changed config files (base: ${BASE_BRANCH})"
git fetch --no-tags --depth=200 origin "${BASE_BRANCH}" >/dev/null 2>&1 || true

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
ADDED_FILES=()
UPDATED_FILES=()
SKIPPED_FILES=()
UNCHANGED=0

while IFS= read -r -d '' prod_file; do
  rel="${prod_file#${PROD_TMP}/}"
  dest="${SYNC_DIR}/${rel}"

  if [ -n "${PROTECTED[$rel]:-}" ]; then
    SKIPPED_FILES+=("$rel")
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  if [ ! -f "$dest" ]; then
    ADDED_FILES+=("$rel")
    cp "$prod_file" "$dest"
  elif ! cmp -s "$prod_file" "$dest"; then
    UPDATED_FILES+=("$rel")
    cp "$prod_file" "$dest"
  else
    UNCHANGED=$((UNCHANGED + 1))
  fi
done < <(find "${PROD_TMP}" -type f -print0)

echo "    added: ${#ADDED_FILES[@]}   updated: ${#UPDATED_FILES[@]}   unchanged: ${UNCHANGED}   skipped (PR-protected): ${#SKIPPED_FILES[@]}"

echo "==> Writing sync report to ${REPORT_FILE}"
{
  echo "### 🔧 Drupal config sync from \`${TERMINUS_SITE}.live\`"
  echo
  if [ "${#ADDED_FILES[@]}" -eq 0 ] && [ "${#UPDATED_FILES[@]}" -eq 0 ] && [ "${#SKIPPED_FILES[@]}" -eq 0 ]; then
    echo "_No config changes — repo already in sync with prod._"
  else
    if [ "${#UPDATED_FILES[@]}" -gt 0 ]; then
      echo "**Updated from prod (${#UPDATED_FILES[@]}):**"
      for f in "${UPDATED_FILES[@]}"; do echo "- \`${f}\`"; done
      echo
    fi
    if [ "${#ADDED_FILES[@]}" -gt 0 ]; then
      echo "**Added from prod (${#ADDED_FILES[@]}):**"
      for f in "${ADDED_FILES[@]}"; do echo "- \`${f}\`"; done
      echo
    fi
    if [ "${#SKIPPED_FILES[@]}" -gt 0 ]; then
      echo "**Preserved from PR (${#SKIPPED_FILES[@]}) — not overwritten:**"
      for f in "${SKIPPED_FILES[@]}"; do echo "- \`${f}\`"; done
      echo
    fi
  fi
} > "${REPORT_FILE}"

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
