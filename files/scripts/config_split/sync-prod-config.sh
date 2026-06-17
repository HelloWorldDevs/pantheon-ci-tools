#!/usr/bin/env bash
#
# Sync Drupal config from the Pantheon live environment into the repo's
# config/sync/, preserving any config files modified in the current PR.
#
# Runs in one of three MODES (first positional arg, default "all"):
#
#   merge   Phase 1 — runs BEFORE the Pantheon deploy. Exports prod config,
#           merges it into config/sync/ (PR-modified files win), writes the
#           report, and hard-stops on conflicts / failed safety checks. Leaves
#           the merged files in the working tree UNCOMMITTED — the deploy's
#           "Preparing code" step stages+commits them, so the pushed artifact
#           already contains the merged config. Does NOT push or import.
#
#   import  Phase 2 — runs AFTER the deploy, against the freshly-deployed
#           multidev. Pre-uninstalls modules that were removed from config,
#           runs `drush config:import`, and rebuilds caches. Self-contained:
#           it operates on the deployed env and needs no local merge state.
#
#   all     Manual/local path (default) — does merge, then commits + pushes the
#           merged config to the env, then imports. Use this when running the
#           script by hand against an existing multidev with no separate CI
#           deploy step around it.
#
# Why split merge/import: config:import on the env reads the DEPLOYED code's
# config_sync_directory (typically ../config/sync). If the merge runs AFTER the
# deploy, that directory still holds the branch's pre-merge config and prod
# drift is never imported. Merging BEFORE the deploy puts the merged result into
# the artifact the deploy pushes, so import just works — no re-push needed.
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

MODE="${1:-all}"
case "${MODE}" in
  all|merge|import) ;;
  *) echo "Usage: $0 [all|merge|import]" >&2; exit 2 ;;
esac

BASE_BRANCH="${CONFIG_BASE_BRANCH:-main}"
SYNC_DIR="${CONFIG_SYNC_DIR:-config/sync}"
REPORT_FILE="${CONFIG_SYNC_REPORT:-/tmp/config-sync-report.md}"
PR_BASE_DIR="${PR_BASE_DIR:-/tmp/pr-base-config}"
PROD_TMP="$(mktemp -d)"
trap 'rm -rf "$PROD_TMP"' EXIT

# Keep SSH non-interactive for terminus rsync. Each Pantheon environment has
# its own appserver host (appserver.<env>.<id>.drush.in). A freshly-created
# multidev's host key isn't in known_hosts yet, so the first rsync-over-SSH
# upload otherwise blocks FOREVER on an interactive "yes/no" host-key prompt —
# which in CI looks like a hang at "Uploading merged config".
#
# Use `accept-new` rather than `no`: it auto-trusts a host the FIRST time it's
# seen (so the fresh-multidev case proceeds unattended) but records the key in
# known_hosts and REJECTS a subsequent key change — i.e. it still protects
# against MITM/key-swap, unlike `StrictHostKeyChecking no` + UserKnownHostsFile
# /dev/null, which silently accept whatever key is presented every time.
# Idempotent. Needed by both phases (rsync from live; drush to the env).
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if ! grep -qs 'drush\.in' "${HOME}/.ssh/config"; then
  cat >> "${HOME}/.ssh/config" <<'SSHCFG'

Host *.drush.in
  StrictHostKeyChecking accept-new
  LogLevel ERROR
SSHCFG
  chmod 600 "${HOME}/.ssh/config"
fi

# Ensure terminus is authenticated. The MERGE phase now runs BEFORE the deploy
# step (dev-multidev.sh) that used to be the first thing to `auth:login`, so the
# very first terminus call here (config:export from live) would otherwise fail
# with "You are not logged in."
#
# Do NOT guard on `terminus auth:whoami`: it exits 0 even when logged OUT (it
# just prints an empty identity), so a `whoami`-guard silently skips the login
# and the export then fails unauthenticated. Instead just log in when a token is
# present — `auth:login` is idempotent — exactly like dev-multidev.sh and
# check-multidev-capacity.sh do. Needs TERMINUS_TOKEN (a Pantheon machine token)
# in the job environment/context.
if [ -n "${TERMINUS_TOKEN:-}" ]; then
  echo "==> Authenticating terminus with machine token"
  terminus -n auth:login --machine-token="${TERMINUS_TOKEN}"
elif ! terminus auth:whoami >/dev/null 2>&1; then
  echo "ERROR: terminus is not authenticated and TERMINUS_TOKEN is not set." >&2
  exit 1
fi

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

# ── Phase 2 (import) helper ──────────────────────────────────────────────────
# Runs entirely against the deployed env. Pre-uninstall modules removed from
# config, then config:import, then cache:rebuild.
run_import() {
  # Pre-uninstall modules that are enabled on the (often REUSED) multidev but no
  # longer present in the config to be imported. Drupal's config:import frequently
  # can't uninstall a module AND delete that module's config in a single pass — it
  # fails validation with "<config> depends on the <module> that will not be
  # installed after import" and CANNOT self-heal, so every re-run keeps failing.
  # `pm:uninstall` cleanly removes the module and its config first, making the
  # subsequent import conflict-free. Computed against the env's own sync storage
  # (config.storage.sync = the dir config:import actually reads), and the install
  # profile is excluded so we never try to uninstall it. Safety: if sync's
  # core.extension can't be read (empty), we skip rather than risk uninstalling
  # everything.
  echo "==> Reconciling modules removed from config on ${TERMINUS_SITE}.${TERMINUS_ENV}"
  local TO_UNINSTALL
  TO_UNINSTALL="$(terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- ev '$sync = \Drupal::service("config.storage.sync"); $ext = $sync->read("core.extension"); if (is_array($ext) && !empty($ext["module"])) { $active = array_keys(\Drupal::config("core.extension")->get("module")); $remove = array_diff($active, array_keys($ext["module"])); $remove = array_diff($remove, [(string) \Drupal::installProfile()]); echo implode(" ", $remove); }' 2>/dev/null || true)"
  TO_UNINSTALL="$(printf '%s' "${TO_UNINSTALL}" | tr -d '\r' | xargs || true)"
  if [ -n "${TO_UNINSTALL}" ]; then
    echo "    Enabled on env but removed from config — uninstalling first: ${TO_UNINSTALL}"
    terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- pm:uninstall ${TO_UNINSTALL} -y \
      || echo "    (pm:uninstall reported issues; continuing — config:import will surface anything unresolved)"
  else
    echo "    No enabled modules need removing ahead of import."
  fi

  echo "==> Importing config on ${TERMINUS_SITE}.${TERMINUS_ENV}"
  terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- config:import -y

  echo "==> Rebuilding caches"
  terminus drush "${TERMINUS_SITE}.${TERMINUS_ENV}" -- cache:rebuild

  echo "==> Config import complete."
}

# ── import-only mode: nothing local to do, just apply on the env ─────────────
if [ "${MODE}" = "import" ]; then
  run_import
  exit 0
fi

# ── merge (and the merge part of "all") ──────────────────────────────────────
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

# Hard-stop on conflicts (a file changed in both this PR and prod) BEFORE the
# deploy, so a divergent prod change can't be silently dropped. The report
# (written above) still gets posted to the PR/Jira by the later `when: always`
# steps, so the dev sees exactly what to reconcile.
# Set CONFIG_CONFLICT_FAIL=false to downgrade to a warning (legacy behavior).
CONFLICT_FAIL="${CONFIG_CONFLICT_FAIL:-true}"
if [ "${#CONFLICT_REL[@]}" -gt 0 ] && [ "${CONFLICT_FAIL}" != "false" ]; then
  echo "❌ ${#CONFLICT_REL[@]} config file(s) changed in BOTH this PR and prod — blocking deploy:" >&2
  for f in "${CONFLICT_REL[@]}"; do echo "     - ${f}" >&2; done

  RESOLVE_BRANCH="${CIRCLE_BRANCH:-your-branch}"
  CONFLICT_LIST="$(printf '%s, ' "${CONFLICT_REL[@]}")"; CONFLICT_LIST="${CONFLICT_LIST%, }"

  # Append a self-documenting resolution guide to the report so the PR/Jira
  # comment tells the dev exactly how to get unblocked (no need to remember
  # the workflow). Headers are standalone bold lines and the steps go in a
  # fenced code block so both GitHub markdown and the Jira ADF renderer show
  # them cleanly.
  {
    echo
    echo "**⛔ Deploy blocked — reconcile prod drift before merging**"
    echo
    echo "The file(s) above changed on ${TERMINUS_SITE}.live since ${BASE_BRANCH} and also in this PR. Applying prod's version would discard your edits (and vice-versa), so the deploy is stopped before any push or import."
    echo
    echo "**How to resolve**"
    echo
    echo "Pull prod's config into ${BASE_BRANCH}, then merge that into this branch and reconcile:"
    echo
    echo '```bash'
    echo "# 1) Update ${BASE_BRANCH} with prod's current config"
    echo "git checkout ${BASE_BRANCH} && git pull"
    echo "terminus drush ${TERMINUS_SITE}.live -- config:export --destination=/files/private/config-export -y"
    echo "terminus rsync ${TERMINUS_SITE}.live:files/private/config-export/ ./${SYNC_DIR}/"
    echo "git add ${SYNC_DIR} && git commit -m 'Sync prod config drift' && git push"
    echo ""
    echo "# 2) Merge updated ${BASE_BRANCH} into this branch, then resolve: ${CONFLICT_LIST}"
    echo "git checkout ${RESOLVE_BRANCH}"
    echo "git merge ${BASE_BRANCH}"
    echo "git add ${SYNC_DIR} && git commit && git push"
    echo '```'
    echo
    echo "Re-running CI then passes: once ${BASE_BRANCH} matches prod, it's just a normal PR edit and the conflict clears."
    echo
    echo "_Override (keep the PR version and discard prod's drift): set CONFIG_CONFLICT_FAIL=false on the sync step._"
  } >> "${REPORT_FILE}"
  exit 1
fi

echo "==> Running config safety checks on merged result"
SAFETY_CHECK="$(dirname "$0")/config-safety-check.sh"
if [ -f "${SAFETY_CHECK}" ]; then
  # Invoke explicitly via bash so we don't depend on the executable bit
  # and so the script always runs under bash regardless of how it's called.
  if ! bash "${SAFETY_CHECK}"; then
    echo "❌ Config safety check failed. Aborting before deploy." >&2
    echo "_⚠️ Config safety check failed — sync aborted before deploy._" >> "${REPORT_FILE}"
    exit 1
  fi
else
  echo "    config-safety-check.sh not present at ${SAFETY_CHECK} — skipping."
fi

# In "merge" mode we stop here: the merged files sit in the working tree and the
# deploy's "Preparing code" step stages+commits them, so the pushed artifact
# already contains the merged config. Phase 2 (import mode) applies it on the
# env after the deploy.
if [ "${MODE}" = "merge" ]; then
  echo "==> Merge complete (files left staged in working tree for the deploy)."
  exit 0
fi

# ── "all" mode only: commit, push, then import (manual/local path) ───────────
echo "==> Committing merged config (if changed)"
git add "${SYNC_DIR}"
if git diff --cached --quiet; then
  echo "    No config changes to commit."
else
  git commit -m "Sync config from ${TERMINUS_SITE}.live (PR-modified files preserved)"
  echo "==> Pushing merged config to ${TERMINUS_SITE}.${TERMINUS_ENV}"
  terminus -n build:env:push "${TERMINUS_SITE}.${TERMINUS_ENV}" --yes
fi

# Also mirror to files/config-sync for projects whose config_sync_directory
# points there (harmless otherwise).
echo "==> Uploading merged config to ${TERMINUS_SITE}.${TERMINUS_ENV}"
terminus rsync "./${SYNC_DIR}/" "${TERMINUS_SITE}.${TERMINUS_ENV}":files/config-sync/

run_import
