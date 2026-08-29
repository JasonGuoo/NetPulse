# Contributing to NetPulse

NetPulse accepts bug fixes, diagnostic improvements, documentation updates, and focused feature work. Open an issue before starting a large change so the scope can be agreed on first.

## Before opening an issue

1. Search the existing issues.
2. Reproduce the problem on the latest release or the current `main` branch.
3. Remove SSIDs, public IP addresses, hostnames, account names, and unrelated process details from screenshots and logs.
4. Use the private reporting process in [SECURITY.md](SECURITY.md) if the problem could expose data or weaken system security.

## Development setup

You need an Apple silicon Mac, macOS 14 or later, Xcode Command Line Tools, and Swift 5.10 or later.

```bash
git clone https://github.com/JasonGuoo/NetPulse.git
cd NetPulse
swift test --arch arm64
swift run NetPulse
```

Create a branch from the latest `main` and keep each pull request focused on one problem.

## Engineering guidelines

- Use `NetPulse` as the product name in code, documentation, bundle metadata, and user-facing text.
- Keep system collection and network operations in `Sources/NetPulse/Core`. Views should consume model state instead of launching commands directly.
- Use absolute paths, finite timeouts, and argument arrays for macOS command-line tools.
- Keep parsers deterministic and cover new output formats with sanitized fixtures.
- Do not add privileged helpers, `sudo`, packet capture, telemetry, or a remote service without discussing the change first.
- Put user-facing text in `L10n.swift` and update English, Simplified Chinese, Japanese, and Korean entries together.
- Use documentation ranges such as `192.0.2.0/24`, `198.51.100.0/24`, and `203.0.113.0/24` in examples. Never commit a real SSID, public IP, device name, or account name.
- Preserve the macOS 14 and arm64 deployment target unless an issue documents the reason for changing it.
- Update `docs/PRIVACY.md` when a change stores data, adds an endpoint, or changes when a request is sent.

## Tests and checks

Run these before opening a pull request:

```bash
swift test --arch arm64
./scripts/package-release.sh
codesign --verify --deep --strict build/NetPulse.app
test "$(lipo -archs build/NetPulse.app/Contents/MacOS/NetPulse)" = "arm64"
```

For a UI change, render the affected views in English and inspect the images:

```bash
swift build --arch arm64
NETPULSE_LANG=en .build/arm64-apple-macosx/debug/NetPulse \
  --selftest-png /tmp/netpulse-overview.png Overview
```

The build path can vary with the installed Swift toolchain. Use `swift build --show-bin-path` if the command above does not match your environment.

## Pull requests

A useful pull request includes:

- A short explanation of the problem and the chosen fix
- The macOS version and Mac model used for testing
- The exact commands that passed
- Before and after screenshots for visible changes
- New or updated tests for parser and diagnostic behavior
- Documentation changes for user-visible behavior, privacy, or release requirements

By submitting a contribution, you confirm that you have the right to submit it and agree that it may be distributed under the repository's [0BSD license](LICENSE).
