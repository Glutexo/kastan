#!/bin/sh

# Keeps a temporary Xcode app product out of Launch Services after the requested build finishes.
set -u

if test "$#" -lt 2; then
    printf 'Usage: %s BUILT_APP COMMAND [ARGUMENT ...]\n' "$0" >&2
    exit 64
fi

built_app=$1
shift
lsregister=${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister}

status=0
"$@" || status=$?
"$lsregister" -u "$built_app" >/dev/null 2>&1 || true
exit "$status"
