#!/bin/sh

# Verifies that repository builds cannot expose temporary Kaštan app products to Spotlight.
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
make_command=${MAKE:-make}

assert_nonindexed_build() {
    target=$1
    expected_path=$2
    expected_product=$3
    output=$("$make_command" --no-print-directory -n XCODEBUILD=xcodebuild "$target")
    xcodebuild_count=$(printf '%s\n' "$output" | grep -Ec '"xcodebuild" (build|test)')
    wrapper_count=$(printf '%s\n' "$output" |
        grep -Fc 'Scripts/run-xcodebuild-without-spotlight.sh')
    derived_data_paths=$(printf '%s\n' "$output" |
        sed -n 's/.*-derivedDataPath "\([^"]*\)".*/\1/p')

    test "$xcodebuild_count" -eq 1
    test "$wrapper_count" -eq 1
    test "$derived_data_paths" = "$expected_path"
    printf '%s\n' "$output" | grep -Fq \
        "\"$repository_root/$expected_product\" \"xcodebuild\""
    case "$derived_data_paths" in
        *.noindex) ;;
        *)
            printf '%s uses a Spotlight-indexed Derived Data path: %s\n' \
                "$target" "$derived_data_paths" >&2
            exit 1
            ;;
    esac
}

cd "$repository_root"
assert_nonindexed_build \
    build \
    .build/macos-app.noindex \
    .build/macos-app.noindex/Build/Products/Debug/Kastan.app
assert_nonindexed_build \
    install-app \
    .build/install-app.noindex \
    .build/install-app.noindex/Build/Products/Debug/Kastan.app
assert_nonindexed_build \
    test-app \
    .build/macos-app.noindex \
    .build/macos-app.noindex/Build/Products/Debug/Kastan.app
assert_nonindexed_build \
    dmg \
    .build/distribution.noindex \
    .build/distribution.noindex/Build/Products/Release/Kastan.app
