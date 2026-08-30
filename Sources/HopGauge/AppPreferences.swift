import Foundation

enum AppPreferences {
    static let languageKey = "hopgauge.language"
    static let menuBarEnabledKey = "hopgauge.menuBarEnabled"
    static let lastDiagnosticURLKey = "hopgauge.lastDiagURL"
    static let recentDiagnosticURLsKey = "hopgauge.recentDiagURLs"
    static let migrationCompletedKey = "hopgauge.didMigrateLegacyPreferences"

    private static let legacyPrefix = ["net", "pulse"].joined()
    private static let legacyBundleIdentifier = "com.jason.\(legacyPrefix)"
    private static let legacyKeys: [(old: String, new: String)] = [
        ("\(legacyPrefix).language", languageKey),
        ("\(legacyPrefix).menuBarEnabled", menuBarEnabledKey),
        ("\(legacyPrefix).lastDiagURL", lastDiagnosticURLKey),
        ("\(legacyPrefix).recentDiagURLs", recentDiagnosticURLsKey),
    ]

    static func migrateLegacyDefaults(
        into defaults: UserDefaults = .standard,
        from legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacyBundleIdentifier)
    ) {
        guard !defaults.bool(forKey: migrationCompletedKey) else { return }

        if let legacyDefaults {
            for key in legacyKeys where defaults.object(forKey: key.new) == nil {
                guard let value = legacyDefaults.object(forKey: key.old) else { continue }
                defaults.set(value, forKey: key.new)
            }
        }
        defaults.set(true, forKey: migrationCompletedKey)
    }

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [menuBarEnabledKey: true])
    }

    static var isMenuBarEnabled: Bool {
        menuBarEnabled(in: .standard)
    }

    static func menuBarEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: menuBarEnabledKey)
    }

    static func notifyMenuBarVisibilityChanged() {
        NotificationCenter.default.post(name: .hopGaugeMenuBarVisibilityChanged, object: nil)
    }
}

extension Notification.Name {
    static let hopGaugeMenuBarVisibilityChanged = Notification.Name("HopGauge.menuBarVisibilityChanged")
}
