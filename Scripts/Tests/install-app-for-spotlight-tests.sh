#!/bin/sh

# Verifies that installation waits for removal and indexing while delegating the replacement to Finder.
set -eu

script_directory=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

source_app="$temporary_directory/build/Kaštan.app"
installed_app="$temporary_directory/Applications/Kaštan.app"
mkdir -p "$source_app/Contents" "$installed_app/Contents"
printf 'current build\n' > "$source_app/Contents/version"
printf 'previous build\n' > "$installed_app/Contents/version"

unregistered_file="$temporary_directory/unregistered.txt"
killed_file="$temporary_directory/killed.txt"
fake_lsregister="$temporary_directory/lsregister"
fake_killall="$temporary_directory/killall"
fake_mdfind="$temporary_directory/mdfind"
fake_osascript="$temporary_directory/osascript"

printf '%s\n' \
    '#!/bin/sh' \
    'test "$1" = -u' \
    'printf "%s\\n" "$2" >> "$FAKE_UNREGISTERED"' > "$fake_lsregister"
printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\\n" "$1" >> "$FAKE_KILLED"' > "$fake_killall"
printf '%s\n' \
    '#!/bin/sh' \
    'if test -d "$FAKE_INSTALLED_APP"; then printf "%s\\n" "$FAKE_INSTALLED_APP"; fi' > "$fake_mdfind"
printf '%s\n' \
    '#!/bin/sh' \
    'test "$1" = -' \
    'case "$2" in' \
    '    check) test -d "$3" && test -d "$4" && test -d "$FAKE_INSTALLED_APP" ;;' \
    '    install) cp -R "$3" "$4/" ;;' \
    '    *) exit 64 ;;' \
    'esac' > "$fake_osascript"
chmod +x "$fake_lsregister" "$fake_killall" "$fake_mdfind" "$fake_osascript"

FAKE_INSTALLED_APP="$installed_app" \
FAKE_KILLED="$killed_file" \
FAKE_UNREGISTERED="$unregistered_file" \
KILLALL="$fake_killall" \
LSREGISTER="$fake_lsregister" \
MDFIND="$fake_mdfind" \
OSASCRIPT="$fake_osascript" \
    sh "$script_directory/install-app-for-spotlight.sh" \
        cz.glutexo.kastan "$source_app" "$installed_app"

test "$(cat "$installed_app/Contents/version")" = 'current build'
test ! -e "$source_app"
grep -Fqx "$source_app" "$unregistered_file"
grep -Fqx "$installed_app" "$unregistered_file"
test "$(wc -l < "$unregistered_file" | tr -d ' ')" = 2
grep -Fqx 'Spotlight' "$killed_file"
grep -Fqx 'spotlightknowledged' "$killed_file"
test "$(wc -l < "$killed_file" | tr -d ' ')" = 2
