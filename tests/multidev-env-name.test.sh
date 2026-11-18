#!/usr/bin/env bash
# Tests for files/scripts/multidev-env-name.sh.
# Run: bash tests/multidev-env-name.test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/files/scripts/multidev-env-name.sh"
FAILURES=0

assert_env() {
  local expected="$1" branch="$2" pr="${3:-}"
  local actual
  actual=$(bash "$SCRIPT" "$branch" "$pr")
  if [ "$actual" = "$expected" ]; then
    echo "ok   '$branch' (PR '${pr}') -> '$actual'"
  else
    echo "FAIL '$branch' (PR '${pr}'): expected '$expected', got '$actual'"
    FAILURES=$((FAILURES + 1))
  fi
}

# Conventional-commit branch names: the Jira key is the env name, the
# same one setup_vars.sh / dev-multidev.sh create.
assert_env "ads-706" "feature/ADS-706-security-updates" "42"
assert_env "ads-706" "fix/ADS-706" "42"
assert_env "wav-123" "WAV-123-some-thing" ""
assert_env "abcdefghij-" "chore/ABCDEFGHIJ-12345" "7"

# No Jira key: fall back to the PR number, like setup_vars.sh.
assert_env "pr-42" "feature/security-updates" "42"
assert_env "pr-42" "feature/ads-706-lowercase" "42"

# Nothing to derive from: print nothing.
assert_env "" "feature/security-updates" ""
assert_env "" "master" "42"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES failure(s)"
  exit 1
fi
echo "All tests passed"
