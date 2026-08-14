#!/bin/sh

# Keeps the app's Spotlight-safe bundle filename separate from its localized product name.
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
project="$repository_root/KastanApp/KastanApp.xcodeproj/project.pbxproj"

test "$(grep -Fc 'PRODUCT_NAME = Kastan;' "$project")" = 2
test "$(grep -Fc 'path = Kastan.app;' "$project")" = 1
test "$(grep -Fc '/Kastan.app/Contents/MacOS/KastanApp' "$project")" = 2
! grep -Fq 'Kaštan.app' "$project"

grep -Fqx 'APP_BUNDLE_NAME := Kastan' "$repository_root/Makefile"
grep -Fqx 'APP_DISPLAY_NAME := Kaštan' "$repository_root/Makefile"

for localization in cs en; do
    strings="$repository_root/KastanApp/Resources/$localization.lproj/InfoPlist.strings"
    grep -Fqx '"CFBundleDisplayName" = "Kaštan";' "$strings"
    grep -Fqx '"CFBundleName" = "Kaštan";' "$strings"
done
