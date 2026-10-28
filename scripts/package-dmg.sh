#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP="build/Magic Charger.app"
if [ ! -d "$APP" ]; then
    echo "Build the app first with CONFIGURATION=release sh build-app.sh" >&2
    exit 2
fi

VERSION="$(cat VERSION)"
BUILD="${APP_BUILD:-$(cat BUILD_NUMBER)}"
sh scripts/validate-release-bundle.sh "$APP" "$VERSION" "$BUILD" LICENSE

mkdir -p dist
WORK="$(mktemp -d "${TMPDIR:-/tmp}/magic-charger-dmg.XXXXXX")"
STAGING="$WORK/staging"
MOUNTPOINT="$WORK/mount"
SCRATCH="$WORK/scratch.dmg"
mkdir "$STAGING" "$MOUNTPOINT"
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach -quiet "$MOUNTPOINT" || {
            echo "Could not detach scratch image at $MOUNTPOINT; retaining it for recovery" >&2
            return
        }
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ditto "$APP" "$STAGING/Magic Charger.app"
ln -s /Applications "$STAGING/Applications"
cp assets/MagicCharger.icns "$STAGING/.VolumeIcon.icns"
if xcrun --find SetFile >/dev/null 2>&1; then
    xcrun SetFile -a C "$STAGING"
fi

DMG="Magic-Charger-$VERSION.dmg"
if [ -e "dist/$DMG" ]; then
    echo "dist/$DMG already exists; remove it explicitly before rebuilding" >&2
    exit 2
fi
swift build --package-path scripts/dmg-layout --configuration release --scratch-path "$WORK/swift-build" >&2
LAYOUT_BIN="$(swift build --package-path scripts/dmg-layout --configuration release \
    --scratch-path "$WORK/swift-build" --show-bin-path)/DmgLayout"
"$LAYOUT_BIN" background "$STAGING"

# Carbon background aliases must be created on the actual HFS+ volume.
hdiutil create -quiet -volname "Magic Charger $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDRW "$SCRATCH"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNTPOINT" "$SCRATCH"
MOUNTED=1
"$LAYOUT_BIN" apply "$MOUNTPOINT"
"$LAYOUT_BIN" verify "$MOUNTPOINT"
hdiutil detach -quiet "$MOUNTPOINT"
MOUNTED=0
hdiutil convert -quiet "$SCRATCH" -format UDZO -o "$WORK/$DMG"
hdiutil verify -quiet "$WORK/$DMG"
mv "$WORK/$DMG" "dist/$DMG"
(cd dist && shasum -a 256 "$DMG" > SHA256SUMS)
echo "Created dist/$DMG and dist/SHA256SUMS (arm64 only; ad-hoc signed; not notarized)"
