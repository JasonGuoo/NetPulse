import Foundation
import XCTest
@testable import HopGauge

final class PreferencesTests: XCTestCase {
    func testMenuBarDefaultsToEnabledAndPersistsChanges() throws {
        let suiteName = "HopGaugeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppPreferences.registerDefaults(in: defaults)
        XCTAssertTrue(AppPreferences.menuBarEnabled(in: defaults))

        defaults.set(false, forKey: AppPreferences.menuBarEnabledKey)
        XCTAssertFalse(AppPreferences.menuBarEnabled(in: defaults))

        defaults.set(true, forKey: AppPreferences.menuBarEnabledKey)
        XCTAssertTrue(AppPreferences.menuBarEnabled(in: defaults))
    }

    func testLegacyPreferencesMigrateWithoutOverwritingNewValues() throws {
        let currentSuite = "HopGaugeTests.current.\(UUID().uuidString)"
        let legacySuite = "HopGaugeTests.legacy.\(UUID().uuidString)"
        let current = try XCTUnwrap(UserDefaults(suiteName: currentSuite))
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
        defer {
            current.removePersistentDomain(forName: currentSuite)
            legacy.removePersistentDomain(forName: legacySuite)
        }

        let legacyPrefix = ["net", "pulse"].joined()
        legacy.set("ja", forKey: "\(legacyPrefix).language")
        legacy.set(false, forKey: "\(legacyPrefix).menuBarEnabled")
        legacy.set("https://example.com", forKey: "\(legacyPrefix).lastDiagURL")
        current.set("ko", forKey: AppPreferences.languageKey)

        AppPreferences.migrateLegacyDefaults(into: current, from: legacy)

        XCTAssertEqual(current.string(forKey: AppPreferences.languageKey), "ko")
        XCTAssertFalse(current.bool(forKey: AppPreferences.menuBarEnabledKey))
        XCTAssertEqual(
            current.string(forKey: AppPreferences.lastDiagnosticURLKey),
            "https://example.com"
        )
        XCTAssertTrue(current.bool(forKey: AppPreferences.migrationCompletedKey))
    }
}
