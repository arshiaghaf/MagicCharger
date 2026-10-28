#!/bin/sh
# An actual failing Swift test must stop the release driver before any build/package.
set -eu
cd "$(dirname "$0")/../.."
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/magic-charger-release-gate.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$FIXTURE/scripts" "$FIXTURE/Tests/ReleaseGateTests"
cp scripts/prepare-release.sh "$FIXTURE/scripts/"
cat > "$FIXTURE/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ReleaseGate", targets: [.testTarget(name: "ReleaseGateTests")])
PACKAGE
cat > "$FIXTURE/Tests/ReleaseGateTests/ReleaseGateTests.swift" <<'TEST'
import XCTest
final class ReleaseGateTests: XCTestCase {
    func testIntentionalFailure() { XCTFail("intentional release gate failure") }
}
TEST
cat > "$FIXTURE/build-app.sh" <<'BUILD'
#!/bin/sh
mkdir -p build
: > build/should-not-exist
BUILD
cat > "$FIXTURE/scripts/package-dmg.sh" <<'PACKAGE'
#!/bin/sh
mkdir -p dist
: > dist/should-not-exist.dmg
PACKAGE
# Resolve the real source SHA without creating a fixture repository.
export GIT_DIR="$(git rev-parse --absolute-git-dir)"
if EXPECTED_SOURCE_SHA=not-the-checked-out-sha sh "$FIXTURE/scripts/prepare-release.sh" > "$FIXTURE/sha.log" 2>&1; then
    echo 'FAIL: release preparation accepted a different source SHA' >&2; exit 1
fi
grep -F 'Checkout SHA does not match' "$FIXTURE/sha.log" >/dev/null
test ! -e "$FIXTURE/.build"
if sh "$FIXTURE/scripts/prepare-release.sh" > "$FIXTURE/result.log" 2>&1; then
    echo 'FAIL: release preparation accepted a failing test' >&2; exit 1
fi
if ! grep -F 'intentional release gate failure' "$FIXTURE/result.log" >/dev/null; then
    cat "$FIXTURE/result.log" >&2
    echo 'FAIL: fixture did not reach the intended test failure' >&2; exit 1
fi
test ! -e "$FIXTURE/build"
test ! -e "$FIXTURE/dist"
printf '%s\n' 'Release gate passed: mismatched SHA rejected; an actual failing release test prevented build and artifact creation.'
