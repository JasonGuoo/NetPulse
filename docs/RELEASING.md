# Releasing NetPulse

This checklist covers Apple silicon beta releases distributed through GitHub Releases.

## Versioning

NetPulse follows semantic versioning. Beta tags use the form `vMAJOR.MINOR.PATCH-beta.NUMBER`. Published tags and assets are immutable; ship a new beta number instead of moving or replacing an existing release.

The app's `CFBundleShortVersionString` must contain only period-separated integers. Use `CFBundleVersion` and the Git tag to distinguish beta builds.

## 1. Prepare the release

- Update `CHANGELOG.md` and move the completed items out of `Unreleased`.
- Confirm that public documentation and release notes are in English.
- Update the root `VERSION` file. The packaging scripts derive bundle and artifact versions from it.
- Confirm that `README.md` and `docs/PRIVACY.md` still describe every endpoint and stored value.
- Make sure the working tree is clean and synchronized with `main`.

## 2. Test and package

```bash
swift test --arch arm64
./scripts/package-release.sh
```

Verify the bundle:

```bash
plutil -lint build/NetPulse.app/Contents/Info.plist
codesign --verify --deep --strict build/NetPulse.app
test "$(lipo -archs build/NetPulse.app/Contents/MacOS/NetPulse)" = "arm64"
test -f build/NetPulse.app/Contents/Resources/LICENSE.txt
```

Run the app on an Apple silicon Mac and check all five views, refresh, the menu bar, one speed test, and one website diagnosis. Inspect an English self-test screenshot before publishing.

## 3. Check the artifacts

`scripts/package-release.sh` creates the versioned arm64 zip and checksum in `build/`. Confirm that both filenames match `VERSION`, then verify the checksum:

```bash
release_version="$(tr -d '[:space:]' < VERSION)"
cd build
shasum -a 256 -c "NetPulse-${release_version}-macOS-arm64.zip.sha256"
cd ..
```

Download the uploaded files once and compare the local and remote SHA-256 values before announcing the release.

## 4. Publish

1. Merge the release commit into `main` and wait for CI to pass.
2. Create an annotated tag from that exact commit.
3. Create a GitHub release from the tag and mark it as a pre-release.
4. Upload the arm64 zip and checksum file.
5. State the supported architecture, minimum macOS version, signature status, test result, and known limitations in the release notes.
6. Check the release page and both asset links in a signed-out browser session.

## Distribution status

The current packaging flow uses an ad-hoc signature. That is suitable for development and an explicit beta, but it triggers Gatekeeper friction on other Macs. A broadly distributed stable build should use a Developer ID Application certificate, hardened runtime, Apple notarization, and stapling. These steps require the maintainer's Apple Developer credentials and must not be automated with repository secrets until the signing workflow has been reviewed.
