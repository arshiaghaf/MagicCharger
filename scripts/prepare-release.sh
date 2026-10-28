#!/bin/sh
# Keep testing and artifact creation in one fail-fast path for the same checkout.
set -eu
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SOURCE_SHA="$(git rev-parse HEAD)"
if [ -n "${EXPECTED_SOURCE_SHA:-}" ] && [ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]; then
    echo 'Checkout SHA does not match the requested release source' >&2
    exit 2
fi
swift test --configuration release
CONFIGURATION=release sh build-app.sh
sh scripts/package-dmg.sh
sh Tests/Packaging/check-artifacts.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
{
    printf 'source_sha=%s\nconfiguration=release\n' "$SOURCE_SHA"
    printf 'version=%s\nbuild=%s\n' "$(cat VERSION)" "${APP_BUILD:-$(cat BUILD_NUMBER)}"
    swift --version 2>&1
} > dist/BUILD-METADATA.txt
