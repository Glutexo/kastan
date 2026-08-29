#!/bin/sh

# Verifies that temporary app registration is cleared after successful and failed Xcode builds.
set -eu

script_directory=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

built_app="$temporary_directory/Build/Products/Debug/Kastan.app"
unregistered_file="$temporary_directory/unregistered.txt"
fake_lsregister="$temporary_directory/lsregister"
fake_xcodebuild="$temporary_directory/xcodebuild"

printf '%s\n' \
    '#!/bin/sh' \
    'test "$1" = -u' \
    'printf "%s\\n" "$2" >> "$FAKE_UNREGISTERED"' > "$fake_lsregister"
printf '%s\n' \
    '#!/bin/sh' \
    'exit "${FAKE_XCODEBUILD_STATUS:-0}"' > "$fake_xcodebuild"
chmod +x "$fake_lsregister" "$fake_xcodebuild"

FAKE_UNREGISTERED="$unregistered_file" \
LSREGISTER="$fake_lsregister" \
    sh "$script_directory/run-xcodebuild-without-spotlight.sh" \
        "$built_app" "$fake_xcodebuild"

status=0
FAKE_UNREGISTERED="$unregistered_file" \
FAKE_XCODEBUILD_STATUS=23 \
LSREGISTER="$fake_lsregister" \
    sh "$script_directory/run-xcodebuild-without-spotlight.sh" \
        "$built_app" "$fake_xcodebuild" || status=$?

test "$status" -eq 23
test "$(wc -l < "$unregistered_file" | tr -d ' ')" = 2
test "$(LC_ALL=C sort -u "$unregistered_file")" = "$built_app"
