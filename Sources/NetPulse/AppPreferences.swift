import Foundation

enum AppPreferences {
    static let menuBarEnabledKey = "netpulse.menuBarEnabled"

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
        NotificationCenter.default.post(name: .netPulseMenuBarVisibilityChanged, object: nil)
    }
}

extension Notification.Name {
    static let netPulseMenuBarVisibilityChanged = Notification.Name("NetPulse.menuBarVisibilityChanged")
}
