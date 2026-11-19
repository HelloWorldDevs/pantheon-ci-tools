#!/usr/bin/env bash
#
# Tests for files/scripts/config_split/prod-config-drift.sh, using a fake
# `terminus` that behaves like a Pantheon app server: the site's files live in
# $HOME/files (where rsync over SSH to `user@host:files/...` reads from) and the
# filesystem root is not writable, so `drush config:export` fails for any
# destination outside $HOME/files.
#
# Run: bash tests/prod-config-drift.test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/files/scripts/config_split/prod-config-drift.sh"
FAILS=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- fake Pantheon --------------------------------------------------------
REMOTE_HOME="${WORK}/srv/bindings/abc123"
mkdir -p "${REMOTE_HOME}/files" "${WORK}/bin"
cat > "${WORK}/bin/terminus" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
echo "terminus $*" >> "${FAKE_LOG}"
cmd="$1"; shift
case "${cmd}" in
  drush)
    shift            # site.env
    [ "$1" = "--" ] && shift
    sub="$1"; shift
    case "${sub}" in
      php:eval|php-eval|ev)
        # Drush's notices go to stderr on the real thing too.
        echo " [notice] Command: drush php:eval" >&2
        case "$*" in
          *HOME*) echo "${FAKE_REMOTE_HOME}" ;;
          *) echo "unexpected php:eval: $*" >&2; exit 1 ;;
        esac
        ;;
      config:export|cex)
        dest=""
        for a in "$@"; do case "${a}" in --destination=*) dest="${a#--destination=}" ;; esac; done
        case "${dest}" in
          "${FAKE_REMOTE_HOME}/files/"*) ;;
          *) echo " [error]  The destination directory ${dest} is not writable." >&2; exit 1 ;;
        esac
        rm -rf "${dest}"; mkdir -p "${dest}"
        cp -R "${FAKE_LIVE_CONFIG}/." "${dest}/"
        echo "deny from all" > "${dest}/.htaccess"
        ;;
      *) echo "unexpected drush command ${sub}" >&2; exit 1 ;;
    esac
    ;;
  connection:info)
    shift            # site.env
    case "$1" in
      --field=sftp_username) echo "live.abc123" ;;
      --field=sftp_host)     echo "appserver.live.abc123.drush.in" ;;
      --field=sftp_port)     echo "2222" ;;
      *) echo "unexpected connection:info $*" >&2; exit 1 ;;
    esac
    ;;
  rsync) echo "Command \"rsync\" is not defined." >&2; exit 1 ;;
  *) echo "unexpected terminus command ${cmd}" >&2; exit 1 ;;
esac
FAKE
chmod +x "${WORK}/bin/terminus"

# Fake rsync: remote sources (user@host:path) are served from the fake app
# server's $HOME; local-to-local syncs go to the real rsync.
REAL_RSYNC="$(command -v rsync)"
cat > "${WORK}/bin/rsync" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
remote=""; dst=""
for a in "\$@"; do
  case "\${a}" in
    *@*:*) remote="\${a}" ;;
    -*) ;;
    *) dst="\${a}" ;;
  esac
done
[ -n "\${remote}" ] || exec "${REAL_RSYNC}" "\$@"
echo "rsync \$*" >> "\${FAKE_LOG}"
path="\${remote#*:}"
case "\${path}" in /*) echo "rsync: absolute remote path \${path}" >&2; exit 1 ;; esac
[ -d "\${FAKE_REMOTE_HOME}/\${path}" ] || { echo "rsync: \${path}: No such file or directory" >&2; exit 23; }
cp -R "\${FAKE_REMOTE_HOME}/\${path%/}/." "\${dst%/}/"
FAKE
chmod +x "${WORK}/bin/rsync"

# --- fake project ---------------------------------------------------------
PROJECT="${WORK}/project"
mkdir -p "${PROJECT}/config/sync" "${WORK}/live"
printf 'name: Site\n'   > "${PROJECT}/config/sync/system.site.yml"
printf 'old: true\n'    > "${PROJECT}/config/sync/gone.yml"
printf 'name: Prod\n'   > "${WORK}/live/system.site.yml"
printf 'new: true\n'    > "${WORK}/live/added.yml"
git -C "${PROJECT}" init -q

run_drift() {
  ( cd "${PROJECT}" && env \
      PATH="${WORK}/bin:${PATH}" \
      FAKE_LOG="${WORK}/terminus.log" \
      FAKE_REMOTE_HOME="${REMOTE_HOME}" \
      FAKE_LIVE_CONFIG="${WORK}/live" \
      TERMINUS_SITE=example \
      APPLY=false \
      REPORT_FILE="${WORK}/report.md" \
      GITHUB_OUTPUT="${WORK}/out" \
      "$@" bash "${SCRIPT}" )
}

# --- 1. Terminus export path ---------------------------------------------
: > "${WORK}/out"; : > "${WORK}/terminus.log"
OUTPUT="$(run_drift 2>&1)"; RC=$?
if [ "${RC}" -eq 0 ]; then pass "exports live config via terminus and exits 0"
else fail "exports live config via terminus and exits 0 (rc=${RC})"; echo "${OUTPUT}" | sed 's/^/     /'; fi

grep -q '^drift=true$'  "${WORK}/out" && pass "reports drift=true"  || fail "reports drift=true"
grep -q '^updated=1$'   "${WORK}/out" && pass "counts 1 updated"    || fail "counts 1 updated"
grep -q '^added=1$'     "${WORK}/out" && pass "counts 1 added"      || fail "counts 1 added"
grep -q '^removed=1$'   "${WORK}/out" && pass "counts 1 removed"    || fail "counts 1 removed"

if grep -q -- "--destination=${REMOTE_HOME}/files/" "${WORK}/terminus.log"; then
  pass "config:export writes under the remote \$HOME/files"
else
  fail "config:export writes under the remote \$HOME/files"; sed 's/^/     /' "${WORK}/terminus.log"
fi

if grep -q -- "rsync .*-e ssh -p 2222.* live.abc123@appserver.live.abc123.drush.in:files/private/config-export/" "${WORK}/terminus.log"; then
  pass "downloads with plain rsync over SSH (no terminus rsync plugin)"
else
  fail "downloads with plain rsync over SSH (no terminus rsync plugin)"; sed 's/^/     /' "${WORK}/terminus.log"
fi

# --- 2. Pre-exported dir (local runs) exits 0 with no drift --------------
: > "${WORK}/out"
cp -R "${PROJECT}/config/sync" "${WORK}/same"
( cd "${PROJECT}" && PROD_CONFIG_DIR="${WORK}/same" APPLY=false REPORT_FILE="${WORK}/report.md" \
    GITHUB_OUTPUT="${WORK}/out" bash "${SCRIPT}" >/dev/null 2>&1 ); RC=$?
[ "${RC}" -eq 0 ] && pass "PROD_CONFIG_DIR with no drift exits 0" || fail "PROD_CONFIG_DIR with no drift exits 0 (rc=${RC})"
grep -q '^drift=false$' "${WORK}/out" && pass "reports drift=false" || fail "reports drift=false"

echo
if [ "${FAILS}" -eq 0 ]; then echo "All tests passed."; else echo "${FAILS} test(s) failed."; exit 1; fi
