#!/bin/bash
#
# Launches headless Chrome with remote debugging on port 9515 so Behat's DMore
# Chrome driver can drive it over CDP. Distributed by
# helloworlddevs/pantheon-ci-tools; the behat_test job runs this right before the
# Behat runner. The Chrome binary path matches the baked-in Chrome for Testing in
# helloworlddevs/atdove-testing-image (the tool's behat executor) — the same one
# atdove uses in CI.

# Set XDG_RUNTIME_DIR environment variable
export XDG_RUNTIME_DIR=/tmp/runtime-dir
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

# Start Google Chrome
echo "Starting Google Chrome..."

nohup /chrome/linux-128.0.6613.84/chrome-linux64/chrome --ignore-certificate-errors --ignore-ssl-errors --remote-debugging-address=0.0.0.0 --remote-debugging-port=9515 --whitelisted-ips '--allowed-origins=*' --disable-web-security --user-data-dir=/tmp/chrome_dev_test --disable-site-isolation-trials --headless --disable-gpu --proxy-server='direct://' '--proxy-bypass-list=*' --user-agent=Chrome/110.0.5481.77 --disable-software-rasterizer --disable-dev-shm-usage --no-zygote --no-sandbox --window-size=1920,1080 >/tmp/chrome.log 2>&1 &
# Wait for Chrome to start
sleep 5

# Check if Chrome is running
echo "Checking if Chrome is running..."
ps aux | grep '[c]hrome' || echo "No Chrome process running"

# Output Chrome log
echo "Chrome log output:"
cat /tmp/chrome.log
