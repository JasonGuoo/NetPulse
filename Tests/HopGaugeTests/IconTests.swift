import AppKit
import XCTest
@testable import HopGauge

final class IconTests: XCTestCase {
    func testIconsetUsesExpectedPixelSizesAndTransparentCorners() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HopGaugeIconTests-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: directory) }

        AppDelegate.makeIconset(at: directory.path)

        let expectedSizes: [String: Int] = [
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1_024,
        ]

        for (name, expectedSize) in expectedSizes {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            let image = try XCTUnwrap(NSBitmapImageRep(data: data), name)

            XCTAssertEqual(image.pixelsWide, expectedSize, name)
            XCTAssertEqual(image.pixelsHigh, expectedSize, name)
            XCTAssertTrue(image.hasAlpha, name)

            let last = expectedSize - 1
            for point in [(0, 0), (last, 0), (0, last), (last, last)] {
                let alpha = try XCTUnwrap(image.colorAt(x: point.0, y: point.1), name).alphaComponent
                XCTAssertEqual(alpha, 0, accuracy: 0.001, "\(name) corner \(point)")
            }

            let center = try XCTUnwrap(
                image.colorAt(x: expectedSize / 2, y: expectedSize / 2),
                name
            )
            XCTAssertGreaterThan(center.alphaComponent, 0.95, name)
        }
    }

    func testStatusItemIconIsCustomColoredAndAnimated() throws {
        let goodColor = try XCTUnwrap(
            AppDelegate.statusItemQualityColor(score: 92, connected: true)
                .usingColorSpace(.deviceRGB)
        )
        let warningColor = try XCTUnwrap(
            AppDelegate.statusItemQualityColor(score: 58, connected: true)
                .usingColorSpace(.deviceRGB)
        )
        let offlineColor = try XCTUnwrap(
            AppDelegate.statusItemQualityColor(score: 92, connected: false)
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(goodColor.greenComponent, goodColor.redComponent)
        XCTAssertGreaterThan(warningColor.redComponent, warningColor.blueComponent)
        XCTAssertGreaterThan(offlineColor.redComponent, offlineColor.greenComponent)

        let first = AppDelegate.renderStatusItemIcon(score: 92, connected: true, phase: 0.1)
        let second = AppDelegate.renderStatusItemIcon(score: 92, connected: true, phase: 0.6)
        let warning = AppDelegate.renderStatusItemIcon(score: 58, connected: true, phase: 0.1)
        let offline = AppDelegate.renderStatusItemIcon(score: 92, connected: false, phase: 0.1)
        XCTAssertEqual(first.size, NSSize(width: 22, height: 18))
        XCTAssertFalse(first.isTemplate)
        XCTAssertNotEqual(first.tiffRepresentation, second.tiffRepresentation)
        XCTAssertNotEqual(first.tiffRepresentation, warning.tiffRepresentation)
        XCTAssertNotEqual(warning.tiffRepresentation, offline.tiffRepresentation)
    }
}
