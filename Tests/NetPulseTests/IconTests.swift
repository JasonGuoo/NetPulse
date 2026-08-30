import AppKit
import XCTest
@testable import NetPulse

final class IconTests: XCTestCase {
    func testIconsetUsesExpectedPixelSizesAndTransparentCorners() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetPulseIconTests-\(UUID().uuidString).iconset")
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
}
