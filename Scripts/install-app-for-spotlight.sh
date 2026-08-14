#!/bin/sh

# Reinstalls Kaštan through Finder so Spotlight replaces the prior app identity instead of retaining a duplicate result.
set -eu

if test "$#" -lt 3; then
    printf 'Usage: %s BUNDLE_IDENTIFIER SOURCE_APP INSTALLED_APP [OBSOLETE_APP ...]\n' "$0" >&2
    exit 64
fi

bundle_identifier=$1
source_app=$2
installed_app=$3
shift 3
install_directory=$(dirname "$installed_app")
ditto=${DITTO:-ditto}
killall=${KILLALL:-killall}
lsregister=${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister}
mdfind=${MDFIND:-mdfind}
osascript=${OSASCRIPT:-osascript}

if ! test -d "$source_app"; then
    printf 'Built application not found: %s\n' "$source_app" >&2
    exit 1
fi

mkdir -p "$install_directory"

finder_copy() {
    operation=$1
    "$osascript" - "$operation" "$source_app" "$install_directory" <<'APPLESCRIPT'
on run arguments
    set operation to item 1 of arguments
    set sourcePath to item 2 of arguments
    set destinationPath to item 3 of arguments

    tell application "Finder"
        set sourceItem to POSIX file sourcePath as alias
        set destinationFolder to POSIX file destinationPath as alias

        if operation is "check" then
            return name of sourceItem
        end if

        duplicate sourceItem to destinationFolder with replacing
    end tell
end run
APPLESCRIPT
}

metadata_paths() {
    "$mdfind" "kMDItemCFBundleIdentifier == \"$bundle_identifier\""
}

finder_copy check >/dev/null

"$lsregister" -u "$source_app" >/dev/null 2>&1 || true
for app in "$installed_app" "$@"; do
    if test -d "$app"; then
        "$lsregister" -u "$app" >/dev/null 2>&1 || true
    fi
    rm -rf "$app"
done

# Drop both the visible search process and its app-suggestion cache after neither app identity remains registered.
"$killall" Spotlight >/dev/null 2>&1 || true
"$killall" spotlightknowledged >/dev/null 2>&1 || true
"$killall" spotlightknowledged.updater >/dev/null 2>&1 || true

attempt=0
while test "$attempt" -lt 40 && test -n "$(metadata_paths)"; do
    attempt=$((attempt + 1))
    sleep 0.25
done
if test -n "$(metadata_paths)"; then
    finder_copy install >/dev/null || "$ditto" "$source_app" "$installed_app"
    printf 'Spotlight did not remove the previous application identity.\n' >&2
    exit 1
fi

if ! finder_copy install >/dev/null; then
    "$ditto" "$source_app" "$installed_app"
    printf 'Finder could not install the application.\n' >&2
    exit 1
fi

attempt=0
while test "$attempt" -lt 40 && test -z "$(metadata_paths)"; do
    attempt=$((attempt + 1))
    sleep 0.25
done
if test -z "$(metadata_paths)"; then
    printf 'Spotlight did not index the installed application.\n' >&2
    exit 1
fi

rm -rf "$source_app"
