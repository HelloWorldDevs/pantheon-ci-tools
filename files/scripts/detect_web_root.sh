#!/bin/bash
#
# Detect the Drupal web root (`html/` or `web/`) for the current project
# and auto-correct THEME_PATH so a stale prefix doesn't break the build.
#
# This is the single source of truth used in two places:
#   1. setup_vars.sh sources it at the top of every CI job.
#   2. CircleCI's "Load environment variables" step appends a source line
#      for it to $BASH_ENV, so every later step re-runs the normalization
#      AFTER the project's env_vars.sh (which may set THEME_PATH itself)
#      gets sourced. Without that, env_vars.sh would overwrite the
#      corrected value on every step.
#
# Idempotent: safe to source repeatedly. Only mutates THEME_PATH when the
# prefix actually mismatches the detected web root.

# Detect web root. Prefer html/ when both exist (Pantheon's traditional
# layout); warn loudly so the project can clean up.
if [ -d "html" ] && [ ! -d "web" ]; then
    WEB_ROOT="html"
elif [ -d "web" ] && [ ! -d "html" ]; then
    WEB_ROOT="web"
elif [ -d "html" ] && [ -d "web" ]; then
    WEB_ROOT="html"
    echo "detect_web_root: WARNING both html/ and web/ exist; defaulting WEB_ROOT=html. Remove the unused one to silence this." >&2
else
    WEB_ROOT=""
fi
export WEB_ROOT

# Auto-correct THEME_PATH if its prefix doesn't match the detected web root.
# Only runs when THEME_PATH is already set; we never invent a path.
if [ -n "${THEME_PATH:-}" ] && [ -n "${WEB_ROOT}" ]; then
    _orig_theme_path="${THEME_PATH}"
    if [ "${WEB_ROOT}" = "html" ]; then
        THEME_PATH="$(printf '%s' "${THEME_PATH}" | sed -E 's#(^|/)web/#\1html/#')"
    else
        THEME_PATH="$(printf '%s' "${THEME_PATH}" | sed -E 's#(^|/)html/#\1web/#')"
    fi
    if [ "${THEME_PATH}" != "${_orig_theme_path}" ]; then
        echo "detect_web_root: auto-corrected THEME_PATH for WEB_ROOT=${WEB_ROOT}: '${_orig_theme_path}' -> '${THEME_PATH}'"
    fi
    unset _orig_theme_path
    export THEME_PATH
fi
