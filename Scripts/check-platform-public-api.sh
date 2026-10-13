#!/bin/bash

# A simple script that tries to compile the package and
# its public API fixture across every supported Apple
# platform. This should be run alongside the main unit
# tests – both are important!

set -euo pipefail

product="${1:-KickstartExchange}"
case "$product" in
    KickstartExchange|KickstartSignal) ;;
    *) echo "Usage: $0 [KickstartExchange|KickstartSignal]" >&2; exit 1 ;;
esac

package_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_scratch="$(mktemp -d /private/tmp/KickstartSDK-platform-compilation.XXXXXX)"
external_fixture="$sdk_scratch/PublicAPIFixture.swift"
source_list="$sdk_scratch/sources"
test_list="$sdk_scratch/tests"
shared_list="$sdk_scratch/shared"
find "$package_path/Sources/KickstartShared" -name '*.swift' > "$shared_list"
resource_accessor="$sdk_scratch/resource_bundle_accessor.swift"
toolchain_usr="$(dirname "$(dirname "$(xcrun --toolchain default --find swiftc)")")"
testing_plugin_root="$toolchain_usr/lib/swift/host/plugins/testing"

cleanup() {
    local exit_status=$?
    trap - EXIT
    if command -v trash >/dev/null 2>&1; then
        trash "$sdk_scratch" >/dev/null 2>&1 || true
    fi
    exit "$exit_status"
}
trap cleanup EXIT

cp "$package_path/Tests/${product}Tests/PublicAPIFixture.swift" "$external_fixture"
find "$package_path/Sources/$product" -name '*.swift' > "$source_list"
find "$package_path/Tests/${product}Tests" -name '*.swift' > "$test_list"

{
    echo 'import Foundation'
    echo 'extension Foundation.Bundle {'
    echo '    static nonisolated let module = Bundle.main'
    echo '}'
} > "$resource_accessor"

if ! grep -q "^import ${product}\$" "$external_fixture"; then
    echo "PublicAPIFixture.swift must import $product directly." >&2
    exit 1
fi

if grep -Eq '@testable|@_spi|^package[[:space:]]+import' "$external_fixture"; then
    echo "PublicAPIFixture.swift must use only the public SDK API." >&2
    exit 1
fi

for declaration in '.iOS(.v15)' '.macOS(.v12)' '.tvOS(.v15)' '.watchOS(.v8)' '.visionOS(.v1)'; do
    if ! grep -Fq "$declaration" "$package_path/Package.swift"; then
        echo "Package.swift is missing its required $declaration deployment minimum." >&2
        exit 1
    fi
done

check_platform() {
    local platform_name="$1"
    local platform_slug="$2"
    local sdk_name="$3"
    local target="$4"
    local plugin_sdk_name="${5:-$sdk_name}"
    local sdk_path
    local plugin_sdk_path
    local platform_developer
    local platform_plugin_root
    local platform_root="$sdk_scratch/$platform_slug"

    sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
    plugin_sdk_path="$(xcrun --sdk "$plugin_sdk_name" --show-sdk-path)"
    platform_developer="$(dirname "$(dirname "$sdk_path")")"
    platform_plugin_root="$(dirname "$(dirname "$plugin_sdk_path")")/usr/lib/swift/host/plugins"

    for configuration in debug release; do
        local configuration_arguments=()
        local modules="$platform_root/$configuration/Modules"
        local module_cache="$platform_root/$configuration/ModuleCache"
        mkdir -p "$modules" "$module_cache"

        if [[ "$configuration" == "debug" ]]; then
            configuration_arguments=(-D DEBUG -Onone)
        else
            configuration_arguments=(-O)
        fi
        if [[ "$target" == *-macabi ]]; then
            configuration_arguments+=(
                -F "$sdk_path/System/iOSSupport/System/Library/Frameworks"
                -I "$sdk_path/System/iOSSupport/usr/lib/swift"
            )
        fi

        xcrun --sdk "$sdk_name" swiftc -emit-library -static -emit-module -parse-as-library \
            -module-name KickstartShared -package-name KickstartSDK -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
            "${configuration_arguments[@]}" -target "$target" -sdk "$sdk_path" \
            -module-cache-path "$module_cache" \
            -emit-module-path "$modules/KickstartShared.swiftmodule" \
            -o "$modules/libKickstartShared.a" @"$shared_list"

        xcrun --sdk "$sdk_name" swiftc \
            -emit-library -static -emit-module \
            -parse-as-library \
            -I "$modules" \
            -module-name "$product" \
            -package-name KickstartSDK \
            -swift-version 6 \
            -strict-concurrency=complete \
            -warnings-as-errors \
            -enable-testing \
            "${configuration_arguments[@]}" \
            -target "$target" \
            -sdk "$sdk_path" \
            -module-cache-path "$module_cache" \
            -load-plugin-library "$platform_plugin_root/libObservationMacros.dylib" \
            -load-plugin-library "$platform_plugin_root/libSwiftUIMacros.dylib" \
            -emit-module-path "$modules/$product.swiftmodule" \
            -o "$modules/lib$product.a" \
            @"$source_list" \
            "$resource_accessor"

        xcrun --sdk "$sdk_name" swiftc \
            -typecheck \
            -parse-as-library \
            -module-name "${product}ExternalPublicAPICheck" \
            -swift-version 6 \
            -strict-concurrency=complete \
            -warnings-as-errors \
            "${configuration_arguments[@]}" \
            -target "$target" \
            -sdk "$sdk_path" \
            -module-cache-path "$module_cache" \
            -I "$modules" \
            "$external_fixture"

        xcrun --sdk "$sdk_name" swiftc \
            -typecheck \
            -parse-as-library \
            -module-name "${product}Tests" \
            -package-name KickstartSDK \
            -swift-version 6 \
            -strict-concurrency=complete \
            -warnings-as-errors \
            -enable-testing \
            "${configuration_arguments[@]}" \
            -target "$target" \
            -sdk "$sdk_path" \
            -module-cache-path "$module_cache" \
            -I "$modules" \
            -F "$platform_developer/Library/Frameworks" \
            -plugin-path "$testing_plugin_root" \
            @"$test_list" \
            "$resource_accessor"
    done

    echo "Verified $product on $platform_name ($target) by compiling the SDK static library and type-checking tests and an external client in debug and release."
}

check_platform "iOS and iPadOS" ios iphoneos arm64-apple-ios15.0
# Xcode stores the iOS SwiftUI macro plug-ins under the device platform.
check_platform "iOS Simulator" ios-simulator iphonesimulator arm64-apple-ios15.0-simulator iphoneos
check_platform "macOS" macos macosx arm64-apple-macosx12.0
check_platform "Mac Catalyst" catalyst macosx arm64-apple-ios15.0-macabi
check_platform "tvOS" tvos appletvos arm64-apple-tvos15.0
check_platform "watchOS" watchos watchos arm64_32-apple-watchos8.0
check_platform "visionOS" visionos xros arm64-apple-xros1.0
