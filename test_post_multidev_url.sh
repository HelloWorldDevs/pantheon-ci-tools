#!/bin/bash

# Test script for post_multidev_url.sh

TEST_DIR=$(mktemp -d)
SCRIPT_PATH="./files/scripts/post_multidev_url.sh"
MOCK_CURL="$TEST_DIR/curl"

echo "Test Directory: $TEST_DIR"

# Create mock curl
cat << 'EOF' > "$MOCK_CURL"
#!/bin/bash
# Mock curl

# Check arguments to determine behavior
if [[ "$*" == *"api.github.com"* ]]; then
    if [[ "$*" == *"/comments"* ]] && [[ "$*" != *"-X POST"* ]]; then
        # GET comments
        if [ -f "$HOME/github_comments_response" ]; then
            cat "$HOME/github_comments_response"
        else
            echo "[]"
        fi
    elif [[ "$*" == *"-X POST"* ]]; then
        # POST comment
        echo "Posted to GitHub" > "$HOME/github_post_called"
    fi
elif [[ "$*" == *"jira"* ]]; then
    if [[ "$*" == *"/comment"* ]] && [[ "$*" != *"-X POST"* ]]; then
        # GET comments
        if [ -f "$HOME/jira_comments_response" ]; then
            cat "$HOME/jira_comments_response"
        else
            echo '{"comments": []}'
        fi
    elif [[ "$*" == *"-X POST"* ]]; then
        # POST comment
        echo "Posted to Jira" > "$HOME/jira_post_called"
        # Return 201 for success check
        if [[ "$*" == *"-w %{http_code}"* ]]; then
             echo "201"
        fi
    fi
fi
EOF

chmod +x "$MOCK_CURL"

# Export PATH to include mock curl
export PATH="$TEST_DIR:$PATH"
export HOME="$TEST_DIR" # Use test dir as HOME for state files

# Set up environment
export CIRCLE_BRANCH="feature/JIRA-123-test"
export GITHUB_TOKEN="fake-token"
export CIRCLE_PROJECT_USERNAME="testuser"
export CIRCLE_PROJECT_REPONAME="testrepo"
export PR_NUMBER="1"
export MULTIDEV_SITE_URL="https://test-site.pantheonsite.io"
export JIRA_BASE_URL="https://jira.example.com"
export JIRA_USER="jirauser"
export JIRA_TOKEN="jiratoken"

echo "--- Test 1: Fresh Post (GitHub + Jira) ---"
rm -f "$HOME/github_post_called" "$HOME/jira_post_called"
rm -f "$HOME/github_comments_response" "$HOME/jira_comments_response"

bash $SCRIPT_PATH

if [ -f "$HOME/github_post_called" ] && [ -f "$HOME/jira_post_called" ]; then
    echo "✅ Test 1 Passed: Posted to both GitHub and Jira"
else
    echo "❌ Test 1 Failed"
    [ ! -f "$HOME/github_post_called" ] && echo "  - GitHub post missing"
    [ ! -f "$HOME/jira_post_called" ] && echo "  - Jira post missing"
fi

echo "--- Test 2: Idempotency (Already Posted) ---"
# Mock existing comments
echo '[{"body": "🔗 Multidev: https://test-site.pantheonsite.io"}]' > "$HOME/github_comments_response"
echo '{"comments": [{"body": {"content": [{"content": [{"text": "https://test-site.pantheonsite.io"}]}]}}]}' > "$HOME/jira_comments_response"
# Note: The grep in the script is simple, so as long as the URL is in the output, it matches.

rm -f "$HOME/github_post_called" "$HOME/jira_post_called"

bash $SCRIPT_PATH

if [ ! -f "$HOME/github_post_called" ] && [ ! -f "$HOME/jira_post_called" ]; then
    echo "✅ Test 2 Passed: Skipped both as they already exist"
else
    echo "❌ Test 2 Failed"
    [ -f "$HOME/github_post_called" ] && echo "  - GitHub post called unexpectedly"
    [ -f "$HOME/jira_post_called" ] && echo "  - Jira post called unexpectedly"
fi

echo "--- Test 3: GitHub Posted, Jira Missing ---"
echo '[{"body": "🔗 Multidev: https://test-site.pantheonsite.io"}]' > "$HOME/github_comments_response"
rm -f "$HOME/jira_comments_response" # Empty response for Jira

rm -f "$HOME/github_post_called" "$HOME/jira_post_called"

bash $SCRIPT_PATH

if [ ! -f "$HOME/github_post_called" ] && [ -f "$HOME/jira_post_called" ]; then
    echo "✅ Test 3 Passed: Skipped GitHub, Posted to Jira"
else
    echo "❌ Test 3 Failed"
    [ -f "$HOME/github_post_called" ] && echo "  - GitHub post called unexpectedly"
    [ ! -f "$HOME/jira_post_called" ] && echo "  - Jira post missing"
fi

# Cleanup
rm -rf "$TEST_DIR"
