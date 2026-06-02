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

# Detect web root.
#
# Important: `[ -d path ]` resolves symlinks, so a `html/` symlink that
# points at `web/` (a common local-dev convenience for Lando) will look
# identical to a real `html/` directory. The real (non-symlink) dir is
# always the canonical web root — composer scaffolds into it, Pantheon
# pushes it, and `git status` walks it without dereferencing the link.
# When both paths resolve, pick the real one and treat the symlink as a
# convenience alias.
_html_is_link=false
_web_is_link=false
[ -L "html" ] && _html_is_link=true
[ -L "web" ] && _web_is_link=true

if [ -d "html" ] && [ ! -d "web" ]; then
    WEB_ROOT="html"
elif [ -d "web" ] && [ ! -d "html" ]; then
    WEB_ROOT="web"
elif [ -d "html" ] && [ -d "web" ]; then
    if [ "${_html_is_link}" = "true" ] && [ "${_web_is_link}" = "false" ]; then
        WEB_ROOT="web"
        echo "detect_web_root: html/ is a symlink to web/; using WEB_ROOT=web (the real directory)." >&2
    elif [ "${_web_is_link}" = "true" ] && [ "${_html_is_link}" = "false" ]; then
        WEB_ROOT="html"
        echo "detect_web_root: web/ is a symlink to html/; using WEB_ROOT=html (the real directory)." >&2
    else
        WEB_ROOT="html"
        echo "detect_web_root: WARNING both html/ and web/ are real directories; defaulting WEB_ROOT=html. Remove the unused one to silence this." >&2
    fi
else
    WEB_ROOT=""
fi
unset _html_is_link _web_is_link
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
