import Foundation

struct DismissedHints: OptionSet {
    let rawValue: Int

    static let storageKey = "dismissedHints"
    static let welcome = Self(rawValue: 1 << 0)
    static let roomControls = Self(rawValue: 1 << 1)

    static var legacyDefault: Self {
        UserDefaults.standard.bool(forKey: "doNotShowWelcomeAgain") ? .welcome : []
    }

    static var current: Self {
        guard let value = UserDefaults.standard.object(forKey: storageKey) as? Int else {
            return legacyDefault
        }
        return Self(rawValue: value)
    }
}
