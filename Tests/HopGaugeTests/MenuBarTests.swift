import XCTest
@testable import HopGauge

final class MenuBarTests: XCTestCase {
    func testCongestionLevelsUseTheLinkViewThresholds() {
        XCTAssertEqual(ChannelPlan.congestionLevel(for: 0), .low)
        XCTAssertEqual(ChannelPlan.congestionLevel(for: 2), .low)
        XCTAssertEqual(ChannelPlan.congestionLevel(for: 3), .medium)
        XCTAssertEqual(ChannelPlan.congestionLevel(for: 4), .medium)
        XCTAssertEqual(ChannelPlan.congestionLevel(for: 5), .high)
    }

    func testMenuBarSnapshotUsesCurrentChannelSpectrumOverlap() {
        let model = AppModel()
        model.wifi.connected = true
        model.wifi.ssid = "HomeLab"
        model.wifi.channel = 48
        model.wifi.band = "5GHz"
        model.wifi.channelWidthMHz = 80
        model.neighbors = [
            NeighborNetwork(ssid: "Overlap-A", channel: 44, band: "5GHz", widthMHz: 80, rssi: -62, security: "WPA2", phyMode: "802.11ax"),
            NeighborNetwork(ssid: "Overlap-B", channel: 48, band: "5GHz", widthMHz: 20, rssi: -70, security: "WPA2", phyMode: "802.11ax"),
            NeighborNetwork(ssid: "Clear", channel: 100, band: "5GHz", widthMHz: 20, rssi: -72, security: "WPA2", phyMode: "802.11ax"),
            NeighborNetwork(ssid: "HomeLab", channel: 48, band: "5GHz", widthMHz: 80, rssi: -40, security: "WPA2", phyMode: "802.11ax", isOwnRouter: true),
        ]

        let snapshot = MenuBarSnapshot()
        snapshot.update(from: model)

        XCTAssertEqual(snapshot.channelOverlapCount, 2)
    }
}
