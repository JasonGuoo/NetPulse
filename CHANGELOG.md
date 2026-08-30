# Changelog

This file records user-visible changes to HopGauge.

## [Unreleased]

## [1.0.0-beta.5] - 2026-08-30

### Added

- Added on-demand hop-by-hop route tracing to website diagnosis, with bounded probes, silent-hop handling, destination status, and an active-VPN notice.
- Added a native animated speedometer with a real rolling-window needle, live speed curve, running average, peak, stage, and transfer progress.
- Added a text-free animated HopGauge status icon whose full color reflects the latest network-health score.

### Changed

- Renamed the app, Swift package, executable, bundle identity, artifacts, repository, documentation, and interface to HopGauge.
- Added a one-time migration for language, menu bar visibility, and recent diagnosis preferences saved by earlier beta builds.
- Reorganized the README into separate sections for end users and developers.
- Adopted the MIT License for the current source tree so copies and substantial portions must retain the original copyright and permission notice.
- Extended the adaptive download measurement to 10–100 MB so fast connections have a visible and more stable sampling window.

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

[Unreleased]: https://github.com/JasonGuoo/HopGauge/compare/v1.0.0-beta.5...HEAD
[1.0.0-beta.5]: https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.5
[1.0.0-beta.4]: https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.1
