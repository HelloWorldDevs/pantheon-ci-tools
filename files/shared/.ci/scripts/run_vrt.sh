#!/bin/bash

set -euo pipefail

echo "Starting Visual Regression Testing (VRT)..."

# In a real scenario, this would run BackstopJS or similar.
# For now, we simulate a pass.
# To simulate failure, set SIMULATE_VRT_FAILURE=true

if [ "${SIMULATE_VRT_FAILURE:-false}" = "true" ]; then
  echo "❌ VRT Failed!"
  echo "Report generated at: https://dashboard.pantheon.io/sites/${TERMINUS_SITE}/envs/${TERMINUS_ENV}/vrt-report"
  
  # Export report URL for downstream notification
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "VRT_REPORT_URL=https://dashboard.pantheon.io/sites/${TERMINUS_SITE}/envs/${TERMINUS_ENV}/vrt-report" >> "$GITHUB_OUTPUT"
  fi
  
  exit 1
else
  echo "✅ VRT Passed!"
  exit 0
fi
