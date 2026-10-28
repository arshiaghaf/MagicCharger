# Release artifact validation

Release preparation remains separate from publication. It produces an ARM64,
ad-hoc signed, unnotarized DMG and does not install or launch the app, publish a
release, or update a Homebrew tap.

Run `sh scripts/prepare-release.sh` with an installed compatible Swift toolchain.
The script uses `DEVELOPER_DIR` when supplied, otherwise the installed Xcode at
`/Applications/Xcode.app` when available, without changing the global selection.
It runs `swift test --configuration release` before building a release app,
packaging the DMG, checking packaging regressions and verifying its checksum.
An existing versioned DMG must be moved aside explicitly before rebuilding.
`APP_BUILD`, if supplied, must be the same for build, package and cask checks.

The release-preparation workflow checks out the PR head SHA (or the dispatch
SHA), verifies that SHA through `EXPECTED_SOURCE_SHA`, and uses this same test
and artifact path. Upload runs only after all checks succeed, only for manual
dispatch, with read-only repository permissions. `dist/BUILD-METADATA.txt` records
the tested source SHA, release configuration, version/build and Swift toolchain
alongside the DMG and `SHA256SUMS`. Local metadata identifies HEAD; local edits
must be committed before treating it as a reproducible release source.

Both `scripts/package-dmg.sh` and `scripts/render-cask.sh` use
`scripts/validate-release-bundle.sh` to require the checkout's bundle identifier,
marketing version, expected build number, release configuration, ARM64 executable,
unchanged project license and strict code-signature integrity, including nested
code. The cask renderer validates the app mounted read-only from the supplied
DMG, independently of the local build. A valid ad-hoc signature establishes
integrity checks, not Developer ID trust or Apple notarization.

`sh Tests/Packaging/check-release-gate.sh` rejects a mismatched source SHA, then
compiles an intentionally failing release test in a temporary package and verifies
no app build or artifact is created.
After real packaging, `sh Tests/Packaging/check-artifacts.sh` accepts the actual
release DMG and rejects independent fixtures with a wrong identifier, version,
build, debug configuration, missing/changed license or invalid signature. These
checks never launch the packaged app and do not establish hardware behavior,
GUI correctness, minimum-OS compatibility or notification delivery.
