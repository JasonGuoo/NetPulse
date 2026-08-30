# Architecture

NetPulse is a single Swift Package Manager executable that builds a native SwiftUI macOS app. It has no third-party package dependencies and does not install a helper process or system extension.

## Structure

| Path | Responsibility |
| --- | --- |
| `App.swift` | App lifecycle, window and menu bar setup, icon generation, and development self-tests |
| `AppPreferences.swift` | Persistent application preferences and menu bar visibility notifications |
| `AppModel.swift` | Observable state shared by collectors, diagnostics, and views |
| `Models.swift` | Value types for Wi-Fi, connections, traffic, ping, DNS, HTTP timing, route hops, speed, and verdicts |
| `Core/CoreCoordinator.swift` | Starts and stops collectors, coordinates manual refresh, speed tests, URL diagnosis, and route tracing |
| `Core/WifiInfoCollector.swift` | CoreWLAN and `system_profiler` Wi-Fi collection |
| `Core/NetOverviewCollector.swift` | Gateway, DNS, IP, proxy, VPN, and public egress collection |
| `Core/ConnectionMonitor.swift` | `lsof`, `nettop`, and `netstat` sampling and parsing |
| `Core/PingMonitor.swift` | Latency, loss, and jitter samples for the active targets |
| `Core/DnsBench.swift` | System, Cloudflare, and Google resolver comparison |
| `Core/HttpTiming.swift` | URLSession task-metric breakdown for DNS, TCP, TLS, first byte, and download |
| `Core/RouteTracer.swift` | Bounded macOS traceroute execution and hop-output parsing |
| `Core/SpeedTest.swift` | User-triggered Cloudflare download measurement with rolling-window instantaneous samples |
| `Core/Diagnoser.swift` | Rule-based health and root-cause verdicts |
| `L10n.swift` | Runtime localization tables and language preference |
| `Components/` | Shared cards, charts, and channel visualization |
| `Views/` | Overview, connections, Wi-Fi link, speed, and diagnose screens |
| `Views/MenuBarPanelView.swift` | Low-refresh menu bar snapshot and status panel |
| `Views/SettingsView.swift` | In-app and standard settings controls |

## Data flow

```text
macOS frameworks and commands       User actions
              |                         |
              v                         v
        Core collectors     SpeedTest / DnsBench / HttpTiming / RouteTracer
              |                         |
              +------------+------------+
                           v
                       AppModel
                           |
              +------------+------------+
              |                         |
              v                         v
          Diagnoser                SwiftUI views
              |                         |
              +------------>------------+
```

Collectors parse system output into value types before updating `AppModel`. Views read model state and send explicit actions to `CoreCoordinator`; they do not run shell commands directly.

## Sampling schedule

| Collector | Normal interval |
| --- | --- |
| Wi-Fi live metrics | 2 seconds |
| Nearby Wi-Fi and profiler details | 20 seconds |
| Connection and traffic sample | 2 seconds |
| Gateway, DNS, proxy, VPN, and local IP | 10 seconds |
| Active ping targets | About 1 second per target |
| Public egress details | About 5 minutes |
| Overview verdicts | 5 seconds after initial data is available |
| Menu bar snapshot | 30 seconds and whenever the panel opens |

Speed tests and website diagnostics run only after a user action. Speed tests use a 1 MB warm-up to size a 10–100 MB measurement; the UI receives a rolling instantaneous rate about eight times per second while the final result uses the full-stage average. A route trace is part of a website diagnosis and runs concurrently with HTTP and DNS measurements. It is limited to 20 hops, one UDP probe per hop, and a one-second response wait per hop.

The status item animates only the highlight traveling along the NetPulse pulse trace. Its health color and metrics come from the existing 30-second snapshot, so animation does not add collector work or network traffic.

## Concurrency and lifecycle

`CoreCoordinator` owns the long-running `Task` loops. Starting the app creates one loop per subsystem; stopping the app cancels them. Blocking system tools are wrapped by `Shell.run`, which applies timeouts and returns output for parsing. Observable model changes made by background work are dispatched through `MainActor.run`.

Collectors must treat missing, partial, localized, or changed command output as normal. A failed source should leave the related field unavailable without stopping other collectors.

## Diagnostics

Health scores and verdicts are deterministic rules. They combine Wi-Fi signal and SNR, same-channel neighbors, gateway and Internet latency, packet loss, jitter, DNS response time, TCP retransmissions, HTTP phases, and download throughput.

The score is intentionally conservative when one part of the path is clearly degraded. It is a navigation aid: the underlying measurements remain the evidence shown to the user.

## Testing

`Tests/NetPulseTests` covers parsers, traceroute output, instantaneous-speed estimation, status-icon rendering, channel planning, formatting, URL normalization, HTTP metric construction, IP-provider matching, and diagnostic rules. Parser fixtures use synthetic or documentation-only addresses so test output can be shared safely.

UI work can be checked with `--selftest-png`, `--selftest-menubar-png`, and `--selftest-settings-png`, which render deterministic sample data without requiring screen-recording permission. The diagnose-tab self-test includes a synthetic multi-hop path. `--probe` exercises live collectors without opening the main window.

## Packaging

The root `VERSION` file is the release-version source of truth. `scripts/make-app.sh` performs an arm64 release build, assembles `NetPulse.app`, generates the `.icns` file, includes the license, writes bundle version metadata, and applies an ad-hoc signature. `scripts/package-release.sh` verifies the bundle and creates the versioned zip and SHA-256 file. The project does not create an installer, Developer ID signature, notarization ticket, or auto-update feed.
