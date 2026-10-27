#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 3 ]; then
    echo "Usage: sh scripts/render-cask.sh VERSION PUBLISHED_DMG_FILE RELEASE_ASSET_URL" >&2
    exit 2
fi
VERSION="$1"
ASSET="$2"
URL="$3"
DMG="Magic-Charger-$VERSION.dmg"

if [ "$VERSION" != "$(cat VERSION)" ] ||
   ! printf '%s\n' "$VERSION" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
   [ ! -f "$ASSET" ] || [ "$(basename "$ASSET")" != "$DMG" ] ||
   ! printf '%s\n' "$URL" | LC_ALL=C grep -Eq '^https://[A-Za-z0-9._~:/?=&%+@-]+$'; then
    echo "Expected the checkout version, the published DMG file, and its real HTTPS asset URL" >&2
    exit 2
fi
case "$URL" in
    */"$DMG"|*/"$DMG"\?*) ;;
    *) echo "URL must name the same versioned DMG asset" >&2; exit 2 ;;
esac

# Check the supplied release asset itself before declaring an ARM-only cask.
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magic-charger-cask.XXXXXX")"
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then hdiutil detach -quiet "$MOUNT_DIR" >/dev/null 2>&1 || true; fi
    rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$ASSET"
MOUNTED=1
PLIST="$MOUNT_DIR/Magic Charger.app/Contents/Info.plist"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" != co.arshia.magiccharger ] ||
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" != "$VERSION" ]; then
    echo "Published DMG bundle identity/version does not match the requested release" >&2
    exit 2
fi
ARCHITECTURES="$(lipo -archs "$MOUNT_DIR/Magic Charger.app/Contents/MacOS/MagicCharger")"
if [ "$ARCHITECTURES" != arm64 ]; then
    echo "Published DMG must contain an arm64-only app; found: $ARCHITECTURES" >&2
    exit 2
fi
hdiutil detach -quiet "$MOUNT_DIR"
MOUNTED=0
rmdir "$MOUNT_DIR"
trap - EXIT HUP INT TERM
SHA256="$(shasum -a 256 "$ASSET" | awk '{print $1}')"

cat <<CASK
cask "magic-charger" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$URL"
  name "Magic Charger"
  desc "Charging notifications for Magic Keyboard and Magic Mouse"
  homepage "https://github.com/arshiaghaf/magic-charger"

  depends_on macos: :sonoma
  depends_on arch: :arm64
  app "Magic Charger.app"
end
CASK
