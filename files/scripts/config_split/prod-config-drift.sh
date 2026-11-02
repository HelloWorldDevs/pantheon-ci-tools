#!/usr/bin/env bash
#
# Compare the Pantheon LIVE environment's active (exported) config against the
# repo's config sync directory and, by default, apply prod's version into the
# working tree so the caller can commit it and open a PR.
#
# Driven nightly by .github/workflows/prod-config-drift.yml (installed by
# helloworlddevs/pantheon-ci-tools). Safe to run locally from the project root
# with Terminus authenticated.
#
# Env (all optional unless noted):
#   TERMINUS_SITE     Pantheon site machine name. REQUIRED unless PROD_CONFIG_DIR.
#   TERMINUS_ENV_SRC  Environment to export from (default: live).
#   CONFIG_SYNC_DIR   Repo config sync dir (default: config/sync).
#   PROD_CONFIG_DIR   Already-exported prod config dir. Skips Terminus entirely
#                     (local runs / tests).
#   APPLY             "true" (default) rsyncs prod -> CONFIG_SYNC_DIR with
#                     --delete. "false" = report only, working tree untouched.
#   REPORT_FILE       Markdown report path (default: /tmp/prod-config-drift.md).
#   GITHUB_OUTPUT     When set (GitHub Actions), appends:
#                       drift=true|false  added=N updated=N removed=N
#                       safety=passed|failed|skipped
#
# Exit codes: 0 = ran fine (drift or not — read the outputs); non-zero = the
# export/compare itself failed.

set -euo pipefail

SRC_ENV="${TERMINUS_ENV_SRC:-live}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
SYNC_DIR="${SYNC_DIR%/}"
APPLY="${APPLY:-true}"
REPORT_FILE="${REPORT_FILE:-/tmp/prod-config-drift.md}"
MAX_LIST=60   # per-section cap in the report

emit() {  # emit key value  -> GITHUB_OUTPUT (if any) + stdout
  echo "    ${1}=${2}"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "${1}=${2}" >> "${GITHUB_OUTPUT}"; fi
}

# Run from the repo root so CONFIG_SYNC_DIR resolves the same everywhere.
if GITROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then cd "${GITROOT}"; fi

if [ ! -d "${SYNC_DIR}" ]; then
  echo "No ${SYNC_DIR}/ in this project — nothing to compare (not a Drupal config-managed site)."
  printf '_No %s directory — config drift check skipped._\n' "${SYNC_DIR}" > "${REPORT_FILE}"
  emit drift false; emit added 0; emit updated 0; emit removed 0; emit safety skipped
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Get prod's config.
# ---------------------------------------------------------------------------
CLEANUP=""
if [ -n "${PROD_CONFIG_DIR:-}" ]; then
  PROD="${PROD_CONFIG_DIR%/}"
  [ -d "${PROD}" ] || { echo "ERROR: PROD_CONFIG_DIR=${PROD} does not exist" >&2; exit 2; }
  echo "==> Using pre-exported prod config at ${PROD}"
else
  : "${TERMINUS_SITE:?TERMINUS_SITE is required (or set PROD_CONFIG_DIR)}"
  command -v terminus >/dev/null || { echo "ERROR: terminus not on PATH" >&2; exit 2; }
  PROD="$(mktemp -d)"; CLEANUP="${PROD}"
  echo "==> Exporting active config from ${TERMINUS_SITE}.${SRC_ENV}"
  terminus drush "${TERMINUS_SITE}.${SRC_ENV}" -- \
    config:export --destination=/files/private/config-export -y
  echo "==> Downloading it to ${PROD}"
  terminus rsync "${TERMINUS_SITE}.${SRC_ENV}":files/private/config-export/ "${PROD}/"
fi
trap '[ -n "${CLEANUP}" ] && rm -rf "${CLEANUP}"' EXIT

# ---------------------------------------------------------------------------
# 2. Compare. .htaccess is written by Drupal into any export dir and is not
#    config, so it is ignored in both directions.
# ---------------------------------------------------------------------------
echo "==> Comparing ${PROD} against ${SYNC_DIR}/"
set +e
DIFF_OUT="$(diff -rq --exclude=.htaccess "${PROD}" "${SYNC_DIR}" 2>&1)"
DIFF_RC=$?
set -e
if [ "${DIFF_RC}" -gt 1 ]; then
  echo "ERROR: diff failed:" >&2; echo "${DIFF_OUT}" >&2; exit 2
fi

ADDED=(); UPDATED=(); REMOVED=()
while IFS= read -r line; do
  [ -n "${line}" ] || continue
  case "${line}" in
    "Only in ${PROD}"*)
      dir="${line#Only in }"; dir="${dir%%: *}"; name="${line##*: }"
      rel="${dir#"${PROD}"}"; rel="${rel#/}"
      ADDED+=("${rel:+${rel}/}${name}")
      ;;
    "Only in ${SYNC_DIR}"*)
      dir="${line#Only in }"; dir="${dir%%: *}"; name="${line##*: }"
      rel="${dir#"${SYNC_DIR}"}"; rel="${rel#/}"
      REMOVED+=("${rel:+${rel}/}${name}")
      ;;
    "Files ${PROD}/"*)
      p="${line#Files }"; p="${p%% and *}"
      UPDATED+=("${p#"${PROD}"/}")
      ;;
  esac
done <<< "${DIFF_OUT}"

N_ADDED=${#ADDED[@]}; N_UPDATED=${#UPDATED[@]}; N_REMOVED=${#REMOVED[@]}
TOTAL=$((N_ADDED + N_UPDATED + N_REMOVED))
echo "    added: ${N_ADDED}   updated: ${N_UPDATED}   removed: ${N_REMOVED}"

SITE_LABEL="${TERMINUS_SITE:-prod}.${SRC_ENV}"
NOW="$(date -u '+%Y-%m-%d %H:%M UTC')"

if [ "${TOTAL}" -eq 0 ]; then
  echo "==> No drift: ${SYNC_DIR}/ already matches ${SITE_LABEL}."
  printf '### ✅ Prod config in sync — `%s` (%s)\n\n_%s matches the repo. Nothing to do._\n' \
    "${SITE_LABEL}" "${NOW}" "${SITE_LABEL}" > "${REPORT_FILE}"
  emit drift false; emit added 0; emit updated 0; emit removed 0; emit safety skipped
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Apply prod's version into the working tree (mirror, including deletions,
#    so a config object uninstalled on prod doesn't get recreated by the next
#    deploy's config import).
# ---------------------------------------------------------------------------
if [ "${APPLY}" = "true" ]; then
  echo "==> Applying ${SITE_LABEL} config into ${SYNC_DIR}/ (mirror, keeping .htaccess)"
  # -rc (recursive, checksum) and NOT -a: preserving prod's mtimes can leave a
  # changed file with the same size+mtime git has in its index, so git trusts
  # the index and never sees the edit — and the commit would miss it. Writing
  # with a fresh mtime makes git re-hash every touched file.
  rsync -rc --delete --exclude='.htaccess' "${PROD}/" "${SYNC_DIR}/"
else
  echo "==> APPLY=false — report only, ${SYNC_DIR}/ left untouched."
fi

# ---------------------------------------------------------------------------
# 4. Safety check on the result (dev modules / dev split enabled in main
#    config). Non-fatal: the PR still opens, but the report flags it loudly.
# ---------------------------------------------------------------------------
SAFETY="skipped"; SAFETY_LOG=""
SAFETY_CHECK="$(dirname "${BASH_SOURCE[0]}")/config-safety-check.sh"
if [ "${APPLY}" = "true" ] && [ -f "${SAFETY_CHECK}" ]; then
  echo "==> Running config safety check"
  set +e
  SAFETY_LOG="$(CI=1 CONFIG_SYNC_DIR="${SYNC_DIR}" bash "${SAFETY_CHECK}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
  if [ "${PIPESTATUS[0]}" -eq 0 ]; then SAFETY="passed"; else SAFETY="failed"; fi
  set -e
  echo "    safety check: ${SAFETY}"
fi

# ---------------------------------------------------------------------------
# 5. Markdown report (becomes the PR body).
# ---------------------------------------------------------------------------
list_section() {  # list_section "Title" array...
  local title="$1"; shift
  local n=$#
  [ "${n}" -gt 0 ] || return 0
  printf '**%s (%d):**\n' "${title}" "${n}"
  local i=0
  for f in "$@"; do
    i=$((i + 1))
    if [ "${i}" -gt "${MAX_LIST}" ]; then
      printf -- '- _…and %d more_\n' $((n - MAX_LIST)); break
    fi
    printf -- '- `%s`\n' "${f}"
  done
  echo
}

{
  printf '### 🔄 Prod config drift — `%s` vs this branch (%s)\n\n' "${SITE_LABEL}" "${NOW}"
  printf 'The active configuration on **%s** differs from `%s/` in **%d** file(s): ' "${SITE_LABEL}" "${SYNC_DIR}" "${TOTAL}"
  printf '%d updated, %d new on prod, %d removed on prod.\n\n' "${N_UPDATED}" "${N_ADDED}" "${N_REMOVED}"
  if [ "${APPLY}" = "true" ]; then
    printf 'This PR replaces `%s/` with prod'"'"'s export so that merging it makes the repo match prod again.\n\n' "${SYNC_DIR}"
  fi
  list_section "Updated on prod" "${UPDATED[@]}"
  list_section "New on prod" "${ADDED[@]}"
  if [ "${N_REMOVED}" -gt 0 ]; then
    list_section "Removed on prod" "${REMOVED[@]}"
    printf '_Removed files are deleted from `%s/` here; otherwise the next deploy'"'"'s config import would recreate them on prod._\n\n' "${SYNC_DIR}"
  fi
  if [ "${SAFETY}" = "failed" ]; then
    printf '**⚠️ Config safety check FAILED on the synced result — review before merging:**\n\n```\n%s\n```\n\n' "${SAFETY_LOG}"
  fi
  printf '**How to handle this**\n\n'
  printf -- '- If these prod changes are intentional (made in the prod UI): review and merge. The repo is the source of truth again.\n'
  printf -- '- If a change should **not** have happened on prod: do not merge that part. Fix prod (or revert it there), and this PR will refresh itself on the next nightly run.\n'
  printf -- '- If a feature branch already contains the same change, merge that branch first; this PR shrinks or closes automatically.\n'
} > "${REPORT_FILE}"

echo "==> Report written to ${REPORT_FILE}"
emit drift true; emit added "${N_ADDED}"; emit updated "${N_UPDATED}"; emit removed "${N_REMOVED}"; emit safety "${SAFETY}"
