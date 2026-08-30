# Changelog

This file records user-visible changes to NetPulse.

## [Unreleased]

## [1.0.0-beta.4] - 2026-08-30

### Added

- Added a native menu bar panel for signal, link rate, current-channel congestion, gateway latency, DNS latency, and network health.
- Added Open, Refresh, and Quit actions to the menu bar panel.
- Added a persistent in-app setting for showing or hiding the menu bar item.

### Changed

- Limited automatic menu bar snapshots to once every 30 seconds while refreshing immediately when opened.
- Added deterministic menu bar and settings rendering for visual review.

## [1.0.0-beta.3] - 2026-08-30

### Fixed

- Replaced the opaque square icon canvas with a transparent rounded macOS icon.
- Generated every iconset entry at its required pixel dimensions on Retina displays.
- Added regression coverage for icon dimensions and transparent corners.

## [1.0.0-beta.2] - 2026-08-30

### Changed

- Adopted the Zero-Clause BSD license.
- Added complete English project, contribution, security, privacy, architecture, and release documentation.
- Made the packaging script produce arm64-only bundles and include the license in the app resources.
- Added continuous integration and GitHub contribution templates.
- Removed obsolete compiled app files from source control.

### Fixed

- Made English self-test screenshots independent of the current macOS language.
- Made overview DNS timing use the selected interface language instead of a Chinese-only label.

## [1.0.0-beta.1] - 2026-08-29

### Added

- Native macOS dashboard for Wi-Fi, gateway, DNS, Internet, VPN, proxy, and public egress status.
- Per-process network traffic, active connection, and listening-port views.
- Wi-Fi signal, noise, SNR, channel, PHY, MCS, nearby-network, and latency analysis.
- Cloudflare download throughput testing.
- URL timing for DNS, TCP, TLS, time to first byte, and download phases.
- Rule-based root-cause guidance and a low-refresh menu bar summary.
- English, Simplified Chinese, Japanese, and Korean interface languages.
- Apple silicon app bundle for macOS 14 and later.

[Unreleased]: https://github.com/JasonGuoo/NetPulse/compare/v1.0.0-beta.4...HEAD
[1.0.0-beta.4]: https://github.com/JasonGuoo/NetPulse/releases/tag/v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/JasonGuoo/NetPulse/releases/tag/v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/JasonGuoo/NetPulse/releases/tag/v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/JasonGuoo/NetPulse/releases/tag/v1.0.0-beta.1
