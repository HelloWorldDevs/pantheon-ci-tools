#!/bin/bash
#
# Prints local-Behat setup instructions on `lando start` (wired into .lando.yml
# post-start by helloworlddevs/pantheon-ci-tools). Mirrors the helper atdove
# ships at tests/behat/readme.sh so every project gets the same guidance.
#
# Stays quiet for projects that don't have Behat tests.
[ -d tests/behat ] || exit 0

echo -e "\033[36mIf you want to test locally, you will need to install Chrome for Testing. From the root of this project run:\033[0m"
echo -e "\033[33mnpx @puppeteer/browsers install chromedriver@stable\033[0m"
echo -e "\033[33mnpx @puppeteer/browsers install chrome@stable\033[0m"
echo ""

echo -e "\033[36mThen before you run 'lando behat' you need to start Chrome with one of these commands:\033[0m"
echo ""

echo -e "\033[36mSee browser tests (all quotes needed):\033[0m"
echo -e "\033[33m\"\$(find ./chrome -type f -name 'Google Chrome for Testing' | head -n 1)\" --ignore-certificate-errors --ignore-ssl-errors --remote-debugging-address=0.0.0.0 --remote-debugging-port=9515 --whitelisted-ips '--allowed-origins=*' --disable-web-security --user-data-dir=/tmp/chrome_dev_test --disable-site-isolation-trials --mute-audio\033[0m"
echo ""

echo -e "\033[36mHeadless (all quotes needed):\033[0m"
echo -e "\033[33m\"\$(find ./chrome -type f -name 'Google Chrome for Testing' | head -n 1)\" --ignore-certificate-errors --ignore-ssl-errors --remote-debugging-address=0.0.0.0 --remote-debugging-port=9515 --whitelisted-ips '--allowed-origins=*' --disable-web-security --user-data-dir=/tmp/chrome_dev_test --disable-site-isolation-trials --headless --disable-gpu --window-size=1920,1080 --proxy-server='direct://' '--proxy-bypass-list=*' --blink-settings=imagesEnabled=false --user-agent=Chrome/110.0.5481.77 --mute-audio \033[0m"
echo ""

echo -e "\033[34mYou can run a specific test by adding the file name to the command.\033[0m"
echo -e "\033[32mlando behat content.feature\033[0m"
echo -e "\033[34mYou can run a specific test by adding the tag to the command.\033[0m"
echo -e "\033[32mlando behat @tag\033[0m"
