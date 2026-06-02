#!/bin/bash

# Pantheon Settings
export THEME_PATH=""
export THEME_INSTALL="npm install"
export THEME_BUILD="npm run build"

# Auto-correct the web-root prefix in THEME_PATH against what's on disk.
# Pantheon projects vary between `html/` (legacy default) and `web/`
# (composer drupal-scaffold default). If THEME_PATH points at one but only
# the other exists in CWD, swap the prefix so a stale value (left over from
# an editor, an old CircleCI env, etc.) doesn't break the build. Only runs
# when THEME_PATH is set; we never invent a path.
if [ -n "${THEME_PATH:-}" ]; then
    _orig="${THEME_PATH}"
    if [ -d html ] && [ ! -d web ]; then
        THEME_PATH="$(printf '%s' "${THEME_PATH}" | sed -E 's#(^|/)web/#\1html/#')"
    elif [ -d web ] && [ ! -d html ]; then
        THEME_PATH="$(printf '%s' "${THEME_PATH}" | sed -E 's#(^|/)html/#\1web/#')"
    fi
    if [ "${THEME_PATH}" != "${_orig}" ]; then
        echo "env_vars.sh: auto-corrected THEME_PATH '${_orig}' -> '${THEME_PATH}'"
    fi
    unset _orig
    export THEME_PATH
fi
