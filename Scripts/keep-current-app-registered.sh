#!/bin/sh

# Keeps Launch Services and Spotlight focused on the installed Kaštan by removing every other live or stale registration.
set -eu

if test "$#" -ne 2; then
    printf 'Usage: %s BUNDLE_IDENTIFIER INSTALLED_APP\n' "$0" >&2
    exit 64
fi

bundle_identifier=$1
installed_app=$2
lsregister=${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister}
temporary_root=${TMPDIR:-/private/tmp}
temporary_root=${temporary_root%/}

if ! test -d "$installed_app"; then
    printf 'Installed application not found: %s\n' "$installed_app" >&2
    exit 1
fi

installed_info_plist="$installed_app/Contents/Info.plist"
registered_paths=$(mktemp)
trap 'rm -f "$registered_paths"' EXIT HUP INT TERM

"$lsregister" -dump | awk -v wanted="$bundle_identifier" '
function emit() {
    if (identifier == wanted && path != "") print path
    path = ""
    identifier = ""
}
/^-+$/ { emit(); next }
/^path:[[:space:]]/ {
    path = $0
    sub(/^path:[[:space:]]*/, "", path)
    sub(/ \(0x[[:xdigit:]]+\)$/, "", path)
    next
}
/^identifier:[[:space:]]/ {
    identifier = $0
    sub(/^identifier:[[:space:]]*/, "", identifier)
    next
}
END { emit() }
' | LC_ALL=C sort -u > "$registered_paths"

while IFS= read -r app; do
    if test -e "$app" && test "$app" -ef "$installed_app"; then
        continue
    fi

    if test -e "$app"; then
        "$lsregister" -u "$app" >/dev/null
        case "$app" in
            */Build/Products/*.app | */dmg-root/*.app)
                rm -rf "$app"
                ;;
        esac
        continue
    fi

    case "$app" in
        "$HOME"/* | /private/tmp/* | /tmp/* | "$temporary_root"/*)
            ;;
        *)
            printf 'Cannot safely clear stale application registration: %s\n' "$app" >&2
            exit 1
            ;;
    esac

    app_parent=$(dirname "$app")
    existing_ancestor=$app_parent
    while ! test -e "$existing_ancestor"; do
        parent=$(dirname "$existing_ancestor")
        if test "$parent" = "$existing_ancestor"; then
            printf 'Cannot locate an existing parent for: %s\n' "$app" >&2
            exit 1
        fi
        existing_ancestor=$parent
    done

    mkdir -p "$app/Contents"
    cp "$installed_info_plist" "$app/Contents/Info.plist"
    "$lsregister" -u "$app" >/dev/null
    rm -rf "$app"

    directory=$app_parent
    while test "$directory" != "$existing_ancestor"; do
        rmdir "$directory" 2>/dev/null || break
        directory=$(dirname "$directory")
    done
done < "$registered_paths"
