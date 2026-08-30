import Foundation
import XCTest
@testable import NetPulse

final class PreferencesTests: XCTestCase {
    func testMenuBarDefaultsToEnabledAndPersistsChanges() throws {
        let suiteName = "NetPulseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppPreferences.registerDefaults(in: defaults)
        XCTAssertTrue(AppPreferences.menuBarEnabled(in: defaults))

        defaults.set(false, forKey: AppPreferences.menuBarEnabledKey)
        XCTAssertFalse(AppPreferences.menuBarEnabled(in: defaults))

        defaults.set(true, forKey: AppPreferences.menuBarEnabledKey)
        XCTAssertTrue(AppPreferences.menuBarEnabled(in: defaults))
    }
}
