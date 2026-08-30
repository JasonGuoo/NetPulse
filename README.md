# HopGauge

![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Architecture](https://img.shields.io/badge/Apple%20Silicon-arm64-3478f6)
![License](https://img.shields.io/badge/license-MIT-2ea44f)

HopGauge is a native macOS network diagnostics app for Apple Silicon. It brings Wi-Fi conditions, latency, DNS, live traffic, download throughput, and website timing into one place so that a slow connection is easier to explain.

![HopGauge overview](docs/overview.png)

## For Users

### Download and install

[Download HopGauge 1.0 Beta 5](https://github.com/JasonGuoo/HopGauge/releases/tag/v1.0.0-beta.5) from GitHub Releases.

1. Download `HopGauge-1.0.0-beta.5-macOS-arm64.zip`.
2. Extract the archive and move `HopGauge.app` to Applications.
3. On first launch, Control-click the app, choose **Open**, and confirm.

The beta is ad-hoc signed and is not notarized with Apple. The published app supports Apple Silicon only and requires macOS 14 Sonoma or later.

HopGauge does not require `sudo`, create an account, or install a background service.

### What HopGauge shows

| Area | Details |
| --- | --- |
| Overview | Health score, likely root cause, gateway, active DNS, proxy and VPN state, public egress, and Wi-Fi status |
| Connections | Per-process traffic, active remote endpoints, cumulative transfer totals, and local listening ports |
| Wi-Fi link | RSSI, noise, SNR, negotiated rate, channel width, MCS, PHY mode, nearby channel use, and latency history |
| Speed | Cloudflare download test with an animated instantaneous-speed needle, live curve, running average, peak, progress, and Wi-Fi link comparison |
| Diagnose | DNS, TCP, TLS, time to first byte, and download timing for a URL, plus DNS comparison and a hop-by-hop network path |
| Menu bar | Signal strength, link rate, current-channel congestion, gateway and DNS latency, and network status |

![HopGauge live speed test](docs/speed.png)

The menu bar uses a text-free HopGauge pulse icon whose full color follows the latest network-health score. Its pulse highlight animates locally without increasing network activity. The panel takes a lightweight snapshot every 30 seconds and refreshes immediately when opened. It can be shown or hidden from the gear menu in the main window or from HopGauge Settings.

![HopGauge menu bar panel](docs/menu-bar.png)

The interface can follow the system language or use English, Simplified Chinese, Japanese, or Korean.

### Network access and privacy

HopGauge has no accounts, analytics, advertising, or crash-reporting service. It saves the selected interface language, menu bar visibility, the last diagnosed URL, and up to five recent diagnostic URLs in the current user's macOS preferences. Measurement results remain in memory and are discarded when HopGauge quits.

The following features make network requests:

| Activity | When it runs | Destination |
| --- | --- | --- |
| Connectivity and latency checks | While HopGauge is running | The current gateway, active DNS server, `1.1.1.1`, and `8.8.8.8` |
| Public egress lookup | At launch and about every five minutes | Cloudflare trace and `ipinfo.io` |
| Download speed test | Only when requested | Cloudflare's speed test endpoint; normally about 10–100 MB including warm-up |
| Website diagnosis | Only when requested | The URL entered by the user, the system resolver, `1.1.1.1`, `8.8.8.8`, and bounded traceroute probes toward the entered host |

Process names, network addresses, SSIDs, and public IP details can be sensitive. Review and redact screenshots or logs before posting them. See [Privacy](docs/PRIVACY.md) for the full data-flow summary.

### Known limitations

- macOS privacy controls and OS changes can hide the SSID or nearby networks.
- An unprivileged process cannot always inspect connections owned by other users or `root`.
- Per-connection packet loss is not available without elevated capture privileges. HopGauge uses target pings and system-wide TCP retransmissions as supporting signals.
- Some routers and networks block ICMP. A failed ping alone does not prove that the Internet connection is down.
- Some routers do not answer traceroute probes. A silent intermediate hop does not by itself indicate packet loss, and an active VPN changes the visible path.
- Download tests use real bandwidth and may incur data charges.
- A health score compresses several measurements into one number. Check the underlying metrics before acting on it.

For general questions, read [Support](SUPPORT.md). Report reproducible bugs through [GitHub Issues](https://github.com/JasonGuoo/HopGauge/issues), and report security problems through the private process in [Security](SECURITY.md).

## For Developers

[![CI](https://github.com/JasonGuoo/HopGauge/actions/workflows/ci.yml/badge.svg)](https://github.com/JasonGuoo/HopGauge/actions/workflows/ci.yml)

### Development requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools
- Swift 5.10 or later

The project is a native SwiftUI application with no third-party Swift package dependencies and no HopGauge backend.

### Build and test

```bash
git clone https://github.com/JasonGuoo/HopGauge.git
cd HopGauge
swift build --arch arm64
swift run HopGauge
```

Run the test suite with:

```bash
swift test --arch arm64
```

Create a double-clickable app bundle with:

```bash
./scripts/make-app.sh
open build/HopGauge.app
```

The script produces an arm64-only, ad-hoc signed bundle at `build/HopGauge.app`. Build output is excluded from version control.

Create the verified release zip and SHA-256 file with:

```bash
./scripts/package-release.sh
```

### Architecture and data sources

HopGauge uses macOS frameworks and command-line tools already present on the system. The main inputs are CoreWLAN, `system_profiler`, `lsof`, `nettop`, `route`, `traceroute`, `scutil`, `ipconfig`, `ping`, `dig`, and `netstat`.

Collectors feed a shared application model. Rule-based diagnostics then compare signal quality, latency, loss, DNS timing, HTTP timing, and measured throughput. These results are troubleshooting clues, not a substitute for a packet capture or an ISP-side test.

Read [Architecture](docs/ARCHITECTURE.md) for the component map, data flow, refresh cadence, and release layout.

### Repository layout

```text
.
├── Package.swift
├── VERSION                 # Current release version
├── Sources/HopGauge/
│   ├── App.swift           # Application entry point and development utilities
│   ├── AppModel.swift      # Shared observable state
│   ├── Components/         # Reusable charts and visual components
│   ├── Core/               # Collection, diagnostics, and speed testing
│   ├── Resources/          # App icon source
│   └── Views/              # Main application views
├── Tests/HopGaugeTests/    # Parser and diagnostic-rule tests
├── docs/                   # Architecture, privacy, and release notes
└── scripts/                # App bundle and release-archive packaging
```

### Contributing

Bug reports and pull requests are welcome. Read [Contributing](CONTRIBUTING.md) before sending a change. Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md), project decisions are described in [Governance](GOVERNANCE.md), and release history is recorded in the [Changelog](CHANGELOG.md).

## License

The current source tree is released under the [MIT License](LICENSE). Copies and substantial portions of the software must retain the original copyright notice and the complete MIT permission notice, including:

`Copyright (c) 2026 Jason Guo`

Unless a file says otherwise, this license covers the source code, tests, documentation, and bundled artwork in the repository. Previously published releases remain governed by the license included with that release.
