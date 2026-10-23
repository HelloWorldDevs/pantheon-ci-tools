#!/bin/bash
#
# Launches headless Chrome with remote debugging on port 9515 so Behat's DMore
# Chrome driver can drive it over CDP. Distributed by
# helloworlddevs/pantheon-ci-tools; the behat_test job runs this right before the
# Behat runner.
#
# The binary is resolved at runtime rather than hardcoded, so this works on the
# stock cimg/php:*-browsers executor (google-chrome on PATH), on the old custom
# image (Chrome for Testing under /chrome/), and locally. Override with
# CHROME_BIN if you need a specific build.

# Set XDG_RUNTIME_DIR environment variable
export XDG_RUNTIME_DIR=/tmp/runtime-dir
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

# Start Google Chrome
echo "Starting Google Chrome..."

# Resolve the Chrome binary.
CHROME_BIN="${CHROME_BIN:-}"
if [ -z "${CHROME_BIN}" ]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      CHROME_BIN="$(command -v "${candidate}")"
      break
    fi
  done
fi
if [ -z "${CHROME_BIN}" ]; then
  # Legacy custom image layout: Chrome for Testing installed by @puppeteer/browsers.
  CHROME_BIN="$(ls -1 /chrome/linux-*/chrome-linux64/chrome 2>/dev/null | head -n 1 || true)"
fi
if [ -z "${CHROME_BIN}" ] || [ ! -x "${CHROME_BIN}" ]; then
  echo "ERROR: no Chrome binary found (tried google-chrome, chromium, /chrome/linux-*/). Set CHROME_BIN." >&2
  exit 1
fi
echo "Using Chrome: ${CHROME_BIN} ($("${CHROME_BIN}" --version 2>/dev/null || echo 'version unknown'))"

nohup "${CHROME_BIN}" --ignore-certificate-errors --ignore-ssl-errors --remote-debugging-address=0.0.0.0 --remote-debugging-port=9515 --whitelisted-ips '--allowed-origins=*' --disable-web-security --user-data-dir=/tmp/chrome_dev_test --disable-site-isolation-trials --headless --disable-gpu --proxy-server='direct://' '--proxy-bypass-list=*' --user-agent=Chrome/110.0.5481.77 --disable-software-rasterizer --disable-dev-shm-usage --no-zygote --no-sandbox --window-size=1920,1080 >/tmp/chrome.log 2>&1 &
# Wait for Chrome to start
sleep 5

# Check if Chrome is running
echo "Checking if Chrome is running..."
ps aux | grep '[c]hrome' || echo "No Chrome process running"

# Output Chrome log
echo "Chrome log output:"
cat /tmp/chrome.log
