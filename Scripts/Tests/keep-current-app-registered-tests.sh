#!/bin/sh

# Verifies that the Spotlight cleanup preserves the installed app while removing live and stale build registrations.
set -eu

script_directory=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

export HOME="$temporary_directory/home"
export TMPDIR="$temporary_directory/tmp"
mkdir -p "$HOME" "$TMPDIR"

installed_app="$HOME/Applications/Kastan.app"
live_app="$HOME/project/Build/Products/Debug/Kastan.app"
stale_app="$TMPDIR/removed/Build/Products/Debug/Kastan.app"
other_app="$HOME/Applications/Other.app"
mkdir -p "$installed_app/Contents" "$live_app/Contents" "$other_app/Contents"
printf 'installed info\n' > "$installed_app/Contents/Info.plist"

dump_file="$temporary_directory/launch-services.txt"
unregistered_file="$temporary_directory/unregistered.txt"
fake_lsregister="$temporary_directory/lsregister"

printf '%s\n' \
    '--------------------------------------------------------------------------------' \
    "path:                       $installed_app (0x1)" \
    'identifier:                 cz.glutexo.kastan' \
    '--------------------------------------------------------------------------------' \
    "path:                       $live_app (0x2)" \
    'identifier:                 cz.glutexo.kastan' \
    '--------------------------------------------------------------------------------' \
    "path:                       $stale_app (0x3)" \
    'identifier:                 cz.glutexo.kastan' \
    '--------------------------------------------------------------------------------' \
    "path:                       $other_app (0x4)" \
    'identifier:                 example.other' \
    '--------------------------------------------------------------------------------' > "$dump_file"

printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '    -dump) cat "$FAKE_LSREGISTER_DUMP" ;;' \
    '    -u) printf "%s\\n" "$2" >> "$FAKE_LSREGISTER_UNREGISTERED" ;;' \
    '    *) exit 64 ;;' \
    'esac' > "$fake_lsregister"
chmod +x "$fake_lsregister"

FAKE_LSREGISTER_DUMP="$dump_file" \
FAKE_LSREGISTER_UNREGISTERED="$unregistered_file" \
LSREGISTER="$fake_lsregister" \
    sh "$script_directory/keep-current-app-registered.sh" \
        cz.glutexo.kastan "$installed_app"

test -d "$installed_app"
test -d "$other_app"
test ! -e "$live_app"
test ! -e "$stale_app"
test ! -e "$TMPDIR/removed"
test "$(wc -l < "$unregistered_file" | tr -d ' ')" = 2
grep -Fqx "$live_app" "$unregistered_file"
grep -Fqx "$stale_app" "$unregistered_file"
