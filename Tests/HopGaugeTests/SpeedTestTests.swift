import XCTest
@testable import HopGauge

final class SpeedTestTests: XCTestCase {
    func testWindowEstimatorReportsInstantaneousRatherThanCumulativeSpeed() throws {
        var estimator = SpeedWindowEstimator()

        let first = try XCTUnwrap(estimator.sample(
            totalBytes: 1_000_000,
            targetBytes: 4_000_000,
            elapsed: 0.2
        ))
        XCTAssertEqual(first.instantaneousMbps, 40, accuracy: 0.001)
        XCTAssertEqual(first.averageMbps, 40, accuracy: 0.001)
        XCTAssertEqual(first.fraction, 0.25, accuracy: 0.001)

        let second = try XCTUnwrap(estimator.sample(
            totalBytes: 3_000_000,
            targetBytes: 4_000_000,
            elapsed: 0.4
        ))
        XCTAssertEqual(second.averageMbps, 60, accuracy: 0.001)
        XCTAssertEqual(second.instantaneousMbps, 55.2, accuracy: 0.001)
        XCTAssertEqual(second.peakMbps, 55.2, accuracy: 0.001)
    }

    func testWindowEstimatorThrottlesUpdates() {
        var estimator = SpeedWindowEstimator()
        XCTAssertNil(estimator.sample(
            totalBytes: 100_000,
            targetBytes: 1_000_000,
            elapsed: 0.05
        ))
        XCTAssertNotNil(estimator.sample(
            totalBytes: 300_000,
            targetBytes: 1_000_000,
            elapsed: 0.12
        ))
    }

    func testForcedFinalSampleDoesNotCreateAShortIntervalSpeedSpike() throws {
        var estimator = SpeedWindowEstimator()

        let first = try XCTUnwrap(estimator.sample(
            totalBytes: 1_000_000,
            targetBytes: 2_000_000,
            elapsed: 0.2
        ))
        let final = try XCTUnwrap(estimator.sample(
            totalBytes: 1_100_000,
            targetBytes: 2_000_000,
            elapsed: 0.21,
            force: true
        ))

        XCTAssertEqual(first.instantaneousMbps, 40, accuracy: 0.001)
        XCTAssertEqual(final.instantaneousMbps, 40, accuracy: 0.001)
        XCTAssertEqual(final.peakMbps, 40, accuracy: 0.001)
    }
}
