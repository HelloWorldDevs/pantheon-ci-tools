#!/bin/bash
#
# check-multidev.sh — wait until a Pantheon environment is serving before
# we run tests against it.
#
# Pantheon multidev/dev appservers sleep when idle and take 30–60s to wake
# on the first cold hit. Test jobs (behat, playwright) that start hitting
# the URL immediately race that spin-up and fail with timeouts or 5xx on
# the first few requests. Running this guard FIRST makes the readiness
# wait explicit and bounded instead of leaking into per-test flake.
#
# Usage:
#   check-multidev.sh [URL]
# If URL is omitted, falls back to $MULTIDEV_SITE_URL.
#
# Tunables (env):
#   CHECK_MULTIDEV_ATTEMPTS  number of polls before giving up   (default 30)
#   CHECK_MULTIDEV_SLEEP     seconds between polls               (default 10)
#   CHECK_MULTIDEV_TIMEOUT   per-request curl --max-time seconds (default 30)
# Defaults give a ceiling of ~5 minutes (30 × 10s).

set -euo pipefail

URL="${1:-${MULTIDEV_SITE_URL:-}}"

if [ -z "${URL}" ]; then
  echo "check-multidev: no URL provided and MULTIDEV_SITE_URL is unset." >&2
  exit 1
fi

MAX_ATTEMPTS="${CHECK_MULTIDEV_ATTEMPTS:-30}"
SLEEP_SECONDS="${CHECK_MULTIDEV_SLEEP:-10}"
REQ_TIMEOUT="${CHECK_MULTIDEV_TIMEOUT:-30}"

echo "Waiting for ${URL} to be ready (up to $((MAX_ATTEMPTS * SLEEP_SECONDS))s)..."

attempt=1
while [ "${attempt}" -le "${MAX_ATTEMPTS}" ]; do
  # Capture the HTTP status. Use an if-guard (not `|| echo 000`) so a curl
  # transport failure doesn't CONCATENATE with curl's own status output
  # and produce bogus codes like "000000".
  if code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time "${REQ_TIMEOUT}" "${URL}" 2>/dev/null); then
    :
  else
    code="000"
  fi

  case "${code}" in
    2*|3*)
      echo "Ready: ${URL} returned HTTP ${code} after ${attempt} attempt(s)."
      exit 0
      ;;
  esac

  echo "  attempt ${attempt}/${MAX_ATTEMPTS}: HTTP ${code} — retrying in ${SLEEP_SECONDS}s..."
  attempt=$((attempt + 1))
  sleep "${SLEEP_SECONDS}"
done

echo "ERROR: ${URL} did not become ready after ${MAX_ATTEMPTS} attempts." >&2
exit 1
