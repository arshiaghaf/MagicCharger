#!/bin/sh
# Shared by packaging and independent-DMG validation. Does not launch the app.
set -eu
if [ "$#" -ne 4 ]; then
    echo 'Usage: sh scripts/validate-release-bundle.sh APP VERSION BUILD LICENSE_FILE' >&2
    exit 2
fi
APP="$1"
PLIST="$APP/Contents/Info.plist"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" != co.arshia.magiccharger ] ||
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" != "$2" ] ||
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" != "$3" ]; then
    echo 'Release bundle identity/version/build does not match this checkout' >&2
    exit 2
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :MagicChargerBuildConfiguration' "$PLIST" 2>/dev/null || true)" != release ]; then
    echo 'Packaging requires a release bundle; rebuild with CONFIGURATION=release sh build-app.sh' >&2
    exit 2
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" != MagicCharger ]; then
    echo 'Release bundle executable must be MagicCharger' >&2
    exit 2
fi
if ! cmp -s "$4" "$APP/Contents/Resources/LICENSE"; then
    echo 'Release bundle must contain the unchanged project LICENSE' >&2
    exit 2
fi
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/MagicCharger")"
if [ "$ARCHITECTURES" != arm64 ]; then
    echo "Release bundle must be arm64 only; found: $ARCHITECTURES" >&2
    exit 2
fi
# Integrity, including nested code, is separate from Developer ID/notarization.
if ! codesign --verify --deep --strict "$APP"; then
    echo 'Release bundle signature integrity check failed' >&2
    exit 2
fi
