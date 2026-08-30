# Privacy

NetPulse is designed as a local diagnostics tool. It has no account system, analytics, advertising, crash-reporting service, or project-operated backend.

## Data read on the Mac

NetPulse reads the following information while it is running:

- Wi-Fi interface, SSID when macOS permits it, signal, noise, channel, negotiated rate, PHY mode, MCS, security, and nearby networks
- Local IP addresses, subnet, gateway, active DNS servers, proxy configuration, and VPN or tunnel state
- Process names, process IDs, local and remote endpoints, listening ports, byte counts, and transfer rates visible to the current user
- Gateway, DNS, and public-target latency, packet loss, jitter, and system-wide TCP retransmission counts
- URL timing, response metadata, and responding route-hop addresses for a website diagnosis started by the user

These measurements are kept in process memory and are discarded when NetPulse quits.

## Data saved on the Mac

NetPulse stores four values in the current user's macOS preferences:

- The selected interface language under `netpulse.language`
- Whether the menu bar item is visible under `netpulse.menuBarEnabled`
- The last URL submitted for website diagnosis under `netpulse.lastDiagURL`
- Up to five recent diagnostic URLs under `netpulse.recentDiagURLs`

The URL values are updated when a diagnosis starts. NetPulse does not save measurement history, website contents, connection tables, speed-test results, or diagnostic reports.

Normal macOS and shell behavior may still create system-level logs outside NetPulse's control.

## Automatic network requests

While NetPulse is open, it sends one ICMP echo request about once per second to each active target: the local gateway, the active DNS server, `1.1.1.1`, and `8.8.8.8`. A duplicate public target is disabled when it matches the active DNS server.

At launch and about every five minutes, NetPulse requests:

- `https://www.cloudflare.com/cdn-cgi/trace` for the public address, Cloudflare location code, and WARP state
- `https://ipinfo.io/json` for public address, approximate location, and network organization

Those providers receive the public IP address and the standard metadata carried by an HTTPS request. Their handling of that request is governed by their own policies.

## Requests started by the user

- A speed test downloads data from `https://speed.cloudflare.com`. A normal run uses a 3 MB warm-up and a 5–25 MB measurement. A failed measurement can retry with a smaller transfer.
- A website diagnosis requests the URL entered by the user with an ephemeral URL session. It also queries the system resolver, `1.1.1.1`, and `8.8.8.8` for the target hostname.
- The same action starts one bounded UDP traceroute toward that hostname. It sends one probe per hop, stops after the destination or 20 hops, and waits at most one second for each hop. It does not perform reverse-DNS lookups for intermediate addresses.

NetPulse measures response metadata and timing. It does not save the downloaded page body.

## Permissions

NetPulse runs as the current user. It does not request administrator access, install a privileged helper, capture packets, or change network settings. Route tracing uses the `traceroute` tool supplied by macOS. macOS may restrict SSID, nearby-network, or process information; NetPulse leaves unavailable fields empty or marks them as restricted.

## Sharing diagnostics

Screenshots and logs can contain SSIDs, local and public IP addresses, hostnames, process names, VPN details, and approximate location. Redact them before opening a public issue. Use the private process in [SECURITY.md](../SECURITY.md) when sensitive details are required for a vulnerability report.

## Changes to this document

Any contribution that adds persistent storage, telemetry, a new endpoint, or a new permission must update this document in the same pull request.
