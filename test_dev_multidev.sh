#!/bin/bash

# Test script for dev-multidev.sh

TEST_DIR=$(mktemp -d)
SCRIPT_PATH="./files/scripts/dev-multidev.sh"
MOCK_TERMINUS="$TEST_DIR/terminus"

echo "Test Directory: $TEST_DIR"

# Create mock terminus
cat << 'EOF' > "$MOCK_TERMINUS"
#!/bin/bash
# Mock terminus

# Log all calls
echo "terminus $*" >> "$HOME/terminus_calls.log"

# Mock specific commands
if [[ "$*" == *"auth:login"* ]]; then
    exit 0
elif [[ "$*" == *"env:list"* ]]; then
    # Simulate existing environment 'dev'
    echo "dev"
elif [[ "$*" == *"build:env:push"* ]]; then
    exit 0
elif [[ "$*" == *"build:env:create"* ]]; then
    exit 0
elif [[ "$*" == *"drush"* ]]; then
    exit 0
elif [[ "$*" == *"env:clear-cache"* ]]; then
    exit 0
elif [[ "$*" == *"secrets:set"* ]]; then
    exit 0
elif [[ "$*" == *"connection:set"* ]]; then
    exit 0
else
    exit 0
fi
EOF

chmod +x "$MOCK_TERMINUS"

# Export PATH to include mock terminus
export PATH="$TEST_DIR:$PATH"
export HOME="$TEST_DIR"

# Set required env vars
export TERMINUS_TOKEN="mock_token"
export TERMINUS_SITE="mock_site"
export CI_BRANCH="feature/test"
export DEFAULT_BRANCH="main"
export PR_NUMBER="123"

# Run the script
bash "$SCRIPT_PATH"

# Check if drush cim was called
if grep -q "drush .* cim -y" "$TEST_DIR/terminus_calls.log"; then
    echo "✅ PASS: drush cim was called"
else
    echo "❌ FAIL: drush cim was NOT called"
    echo "Calls made:"
    cat "$TEST_DIR/terminus_calls.log"
    exit 1
fi

# Cleanup
rm -rf "$TEST_DIR"
