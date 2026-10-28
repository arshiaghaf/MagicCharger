#!/bin/sh
# Regression checks use only temporary fixtures and never launch an app.
set -eu
cd "$(dirname "$0")/../.."
ROOT="$PWD"
VERSION="$(cat VERSION)"
BUILD="${APP_BUILD:-$(cat BUILD_NUMBER)}"
ASSET="$ROOT/dist/Magic-Charger-$VERSION.dmg"
test -f "$ASSET"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/magic-charger-packaging-check.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT
trap 'exit 1' HUP INT TERM

# A real release artifact renders its actual checksum and ARM-only requirement.
TEST_URL="https://example.invalid/Magic-Charger-$VERSION.dmg"
sh scripts/render-cask.sh "$VERSION" "$ASSET" "$TEST_URL" > "$FIXTURES/cask.rb"
EXPECTED_SHA="$(shasum -a 256 "$ASSET" | awk '{print $1}')"
grep -F "sha256 \"$EXPECTED_SHA\"" "$FIXTURES/cask.rb" >/dev/null
grep -F 'depends_on arch: :arm64' "$FIXTURES/cask.rb" >/dev/null

for CASE in identity version build debug missing-license changed-license invalid-signature; do
    CASE_ROOT="$FIXTURES/$CASE"
    APP="$CASE_ROOT/staging/Magic Charger.app"
    mkdir -p "$CASE_ROOT/staging"
    ditto 'build/Magic Charger.app' "$APP"
    PLIST="$APP/Contents/Info.plist"
    EXPECTED='Release bundle identity/version/build does not match'
    case "$CASE" in
        identity) /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier invalid-fixture' "$PLIST" ;;
        version) /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString invalid-fixture' "$PLIST" ;;
        build) /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST" ;;
        debug)
            /usr/libexec/PlistBuddy -c 'Set :MagicChargerBuildConfiguration debug' "$PLIST"
            EXPECTED='Packaging requires a release bundle' ;;
        missing-license)
            rm "$APP/Contents/Resources/LICENSE"
            EXPECTED='Release bundle must contain the unchanged project LICENSE' ;;
        changed-license)
            printf '\nchanged fixture\n' >> "$APP/Contents/Resources/LICENSE"
            EXPECTED='Release bundle must contain the unchanged project LICENSE' ;;
        invalid-signature)
            printf '\ninvalid signature fixture\n' >> "$APP/Contents/MacOS/MagicCharger"
            EXPECTED='Release bundle signature integrity check failed' ;;
    esac
    # Isolate metadata/license validation from signature failure in those cases.
    if [ "$CASE" != invalid-signature ]; then
        codesign --force --sign - "$APP"
        codesign --verify --deep --strict "$APP"
    fi
    BAD_ASSET="$CASE_ROOT/Magic-Charger-$VERSION.dmg"
    hdiutil create -quiet -volname 'Magic Charger validation fixture' -srcfolder "$CASE_ROOT/staging" -fs HFS+ -format UDZO "$BAD_ASSET"
    if sh scripts/render-cask.sh "$VERSION" "$BAD_ASSET" "$TEST_URL" > "$CASE_ROOT/cask.rb" 2> "$CASE_ROOT/result.log"; then
        echo "FAIL: $CASE DMG was accepted" >&2; exit 1
    fi
    grep -F "$EXPECTED" "$CASE_ROOT/result.log" >/dev/null
    test ! -s "$CASE_ROOT/cask.rb"

    # Packaging consumes the very same validator before creating any DMG.
    mkdir -p "$CASE_ROOT/scripts" "$CASE_ROOT/build"
    cp scripts/package-dmg.sh scripts/validate-release-bundle.sh "$CASE_ROOT/scripts/"
    cp VERSION BUILD_NUMBER LICENSE "$CASE_ROOT/"
    mv "$APP" "$CASE_ROOT/build/Magic Charger.app"
    if sh "$CASE_ROOT/scripts/package-dmg.sh" > "$CASE_ROOT/package.log" 2>&1; then
        echo "FAIL: packaging accepted $CASE bundle" >&2; exit 1
    fi
    grep -F "$EXPECTED" "$CASE_ROOT/package.log" >/dev/null
    test ! -e "$CASE_ROOT/dist"
done
printf '%s\n' 'Packaging regressions passed: real release cask/checksum and seven rejected DMG/bundle fixtures.'
