#!/bin/bash

# Pantheon Settings — customize per project.
#   THEME_PATH    e.g. "./web/themes/custom/foo" or "./html/themes/custom/foo".
#                 The CI pipeline auto-corrects html/ <-> web/ to match the
#                 project's actual web root on every step (via
#                 .ci/scripts/detect_web_root.sh), so a stale prefix here
#                 won't break the build.
#   THEME_INSTALL command run from THEME_PATH to install theme deps.
#   THEME_BUILD   command run from THEME_PATH to produce deployable assets.
export THEME_PATH=""
export THEME_INSTALL="npm install"
export THEME_BUILD="npm run build"
