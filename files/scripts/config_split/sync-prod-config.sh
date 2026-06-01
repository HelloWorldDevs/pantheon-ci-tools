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
#   - Flags conflicts: a PR-changed file where prod ALSO diverged from the
#     base. By default this BLOCKS the deploy (exit 1) before any commit/
#     push/import, so a divergent prod change can't be silently dropped.
#     The report is still written first so the PR/Jira comment shows what to
#     reconcile. Set CONFIG_CONFLICT_FAIL=false to downgrade to a warning.
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
#   PR_CHANGED_FILE    (default: /tmp/pr-changed-config.txt) — list of
#                      PR-changed config files captured by
#                      capture-pr-config-changes.sh in an earlier step,
#                      before the build rewrote git state. If present it is
#                      used verbatim; otherwise we fall back to computing the
#                      diff here (fine for local/manual runs).
#   PR_BASE_DIR        (default: /tmp/pr-base-config) — base-branch copies of
#                      PR-changed files (also written by the capture step),
#                      used to flag conflicts: a PR-changed file where prod
#                      diverged from the same base. Falls back to `git show`
#                      for local/manual runs.
#   CONFIG_CONFLICT_FAIL (default: true) — when true, conflicts block the
#                      deploy (exit 1). Set to "false" to only warn and
#                      continue with the PR version.

set -euo pipefail

BASE_BRANCH="${CONFIG_BASE_BRANCH:-main}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
REPORT_FILE="${CONFIG_SYNC_REPORT:-/tmp/config-sync-report.md}"
PR_BASE_DIR="${PR_BASE_DIR:-/tmp/pr-base-config}"
PROD_TMP="$(mktemp -d)"
trap 'rm -rf "$PROD_TMP"' EXIT

# Decide whether prod diverged from the PR's base for a PR-changed file —
# i.e. a genuine conflict the dev should reconcile (both sides changed it),
# as opposed to the dev simply editing a file prod left untouched.
#
# Args: $1 rel (path under SYNC_DIR)  $2 prod_file  $3 dest (PR version)
# Returns 0 (true) when it's a conflict, non-zero otherwise.
prod_conflicts_with_pr() {
  local rel="$1" prodf="$2" destf="$3"
  local basef="${PR_BASE_DIR}/${SYNC_DIR}/${rel}"
  local tmpbase="" rc=1

  if [ ! -f "$basef" ]; then
    # No pre-captured base (local/manual run). Try to read it from git.
    tmpbase="$(mktemp)"
    if git show "origin/${BASE_BRANCH}:${SYNC_DIR}/${rel}" > "$tmpbase" 2>/dev/null; then
      basef="$tmpbase"
    else
      basef=""
    fi
  fi

  if [ -n "$basef" ] && [ -f "$basef" ]; then
    # Base exists: conflict only when prod changed it from base AND prod's
    # version differs from the PR's. If prod matches base (dev-only edit) or
    # prod matches the PR (they agree), there's nothing to reconcile.
    if ! cmp -s "$prodf" "$basef" && ! cmp -s "$prodf" "$destf"; then
      rc=0
    fi
  else
    # File is new in the PR (no base): conflict iff prod also has it with
    # different content than the dev's added version.
    [ -f "$destf" ] && { cmp -s "$prodf" "$destf" || rc=0; }
  fi

  [ -n "$tmpbase" ] && rm -f "$tmpbase"
  return $rc
}

echo "==> Exporting config from ${TERMINUS_SITE}.live"
terminus drush "${TERMINUS_SITE}.live" -- \
  config:export --destination=/files/private/config-export -y

echo "==> Downloading exported config to ${PROD_TMP}"
terminus rsync "${TERMINUS_SITE}.live":files/private/config-export/ "${PROD_TMP}/"

mkdir -p "${SYNC_DIR}"

echo "==> Detecting PR-changed config files (base: ${BASE_BRANCH})"
PR_CHANGED_FILE="${PR_CHANGED_FILE:-/tmp/pr-changed-config.txt}"

if [ -f "${PR_CHANGED_FILE}" ]; then
  # Pre-captured (before the build rewrote git state) — the reliable source.
  echo "    Using pre-captured PR-changed list from ${PR_CHANGED_FILE}"
  mapfile -t PR_CHANGED < <(grep -v '^[[:space:]]*$' "${PR_CHANGED_FILE}" 2>/dev/null || true)
else
  # Fallback for local/manual runs where no capture step ran.
  echo "    No pre-captured list found; computing diff from origin/${BASE_BRANCH}...HEAD"
  git fetch --no-tags --depth=200 origin "${BASE_BRANCH}" >/dev/null 2>&1 || true
  mapfile -t PR_CHANGED < <(
    git diff --name-only --diff-filter=AMR \
      "origin/${BASE_BRANCH}...HEAD" -- "${SYNC_DIR}/" 2>/dev/null || true
  )
fi

# PROTECTED: lookup used by the merge to keep the PR version.
# PR_CHANGED_REL: ordered, repo-relative-stripped list used in the report.
declare -A PROTECTED=()
PR_CHANGED_REL=()
for f in "${PR_CHANGED[@]}"; do
  [ -n "$f" ] || continue
  rel="${f#${SYNC_DIR}/}"
  if [ -z "${PROTECTED[$rel]:-}" ]; then
    PR_CHANGED_REL+=("$rel")
  fi
  PROTECTED["$rel"]=1
done

if [ "${#PR_CHANGED_REL[@]}" -gt 0 ]; then
  echo "    PR-modified config files (protected from prod overwrite):"
  for k in "${PR_CHANGED_REL[@]}"; do echo "      - $k"; done
else
  echo "    No PR-modified config files detected."
fi

echo "==> Merging prod config into ${SYNC_DIR}/"
ADDED_FILES=()
UPDATED_FILES=()
SKIPPED_FILES=()
declare -A CONFLICT=()
UNCHANGED=0

while IFS= read -r -d '' prod_file; do
  rel="${prod_file#${PROD_TMP}/}"
  dest="${SYNC_DIR}/${rel}"

  if [ -n "${PROTECTED[$rel]:-}" ]; then
    # PR owns this file (keep the PR version), but flag it if prod also
    # diverged from the base — that's a conflict to reconcile by hand.
    SKIPPED_FILES+=("$rel")
    if prod_conflicts_with_pr "$rel" "$prod_file" "$dest"; then
      CONFLICT["$rel"]=1
    fi
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

# Split the PR-changed list into conflicts (prod diverged too) and PR-only,
# preserving capture order, so each file appears in exactly one report section.
CONFLICT_REL=()
PR_ONLY_REL=()
for rel in "${PR_CHANGED_REL[@]}"; do
  if [ -n "${CONFLICT[$rel]:-}" ]; then
    CONFLICT_REL+=("$rel")
  else
    PR_ONLY_REL+=("$rel")
  fi
done

echo "    added: ${#ADDED_FILES[@]}   updated: ${#UPDATED_FILES[@]}   unchanged: ${UNCHANGED}   skipped (PR-protected): ${#SKIPPED_FILES[@]}   conflicts: ${#CONFLICT_REL[@]}"

echo "==> Writing sync report to ${REPORT_FILE}"
{
  echo "### 🔧 Drupal config sync from \`${TERMINUS_SITE}.live\`"
  echo
  if [ "${#CONFLICT_REL[@]}" -eq 0 ] && [ "${#PR_ONLY_REL[@]}" -eq 0 ] && [ "${#UPDATED_FILES[@]}" -eq 0 ] && [ "${#ADDED_FILES[@]}" -eq 0 ]; then
    echo "_No config changes — repo already in sync with prod._"
  else
    if [ "${#CONFLICT_REL[@]}" -gt 0 ]; then
      echo "**⚠️ Changed in both this PR and prod (${#CONFLICT_REL[@]}) — review before merge:**"
      for f in "${CONFLICT_REL[@]}"; do echo "- \`${f}\`"; done
      echo
      echo "_Kept the PR version; prod's differing version was not applied. Reconcile these manually._"
      echo
    fi
    if [ "${#PR_ONLY_REL[@]}" -gt 0 ]; then
      echo "**Updated in this PR (${#PR_ONLY_REL[@]}):**"
      for f in "${PR_ONLY_REL[@]}"; do echo "- \`${f}\`"; done
      echo
    fi
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
  fi
} > "${REPORT_FILE}"

# Hard-stop on conflicts (a file changed in both this PR and prod) BEFORE we
# commit/push/import, so a divergent prod change can't be silently dropped.
# The report (written above) still gets posted to the PR/Jira by the later
# `when: always` steps, so the dev sees exactly what to reconcile.
# Set CONFIG_CONFLICT_FAIL=false to downgrade to a warning (legacy behavior).
CONFLICT_FAIL="${CONFIG_CONFLICT_FAIL:-true}"
if [ "${#CONFLICT_REL[@]}" -gt 0 ] && [ "${CONFLICT_FAIL}" != "false" ]; then
  echo "❌ ${#CONFLICT_REL[@]} config file(s) changed in BOTH this PR and prod — blocking deploy before multidev import:" >&2
  for f in "${CONFLICT_REL[@]}"; do echo "     - ${f}" >&2; done
  {
    echo "_⛔ Deploy blocked: resolve the conflicting config above, then re-run."
    echo "(Set \`CONFIG_CONFLICT_FAIL=false\` to override and keep the PR version.)_"
  } >> "${REPORT_FILE}"
  exit 1
fi

echo "==> Running config safety checks on merged result"
SAFETY_CHECK="$(dirname "$0")/config-safety-check.sh"
if [ -f "${SAFETY_CHECK}" ]; then
  # Invoke explicitly via bash so we don't depend on the executable bit
  # and so the script always runs under bash regardless of how it's called.
  if ! bash "${SAFETY_CHECK}"; then
    echo "❌ Config safety check failed. Aborting sync before push to multidev." >&2
    echo "_⚠️ Config safety check failed — sync aborted before multidev push._" >> "${REPORT_FILE}"
    exit 1
  fi
else
  echo "    config-safety-check.sh not present at ${SAFETY_CHECK} — skipping."
fi

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
