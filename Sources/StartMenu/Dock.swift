import Foundation

/// Hides the macOS Dock for good: auto-hide on, with a reveal delay so long
/// that the Dock never comes back under the mouse. Turning it off restores
/// the user's previous auto-hide setting. The Dock restarts to apply it.
enum Dock {
    private static let domain = "com.apple.dock" as CFString
    private static let autohideKey = "autohide" as CFString
    private static let delayKey = "autohide-delay" as CFString
    /// Seconds the mouse must rest at the screen edge to reveal the Dock.
    private static let hiddenDelay = 1000.0
    /// Our own default: the Dock's auto-hide setting before we hid it.
    private static let previousAutohideKey = "dockAutohideBefore"

    static var isHidden: Bool {
        CFPreferencesAppSynchronize(domain)
        let delay = CFPreferencesCopyAppValue(delayKey, domain) as? Double ?? 0
        return autohide && delay >= hiddenDelay / 2
    }

    private static var autohide: Bool {
        CFPreferencesCopyAppValue(autohideKey, domain) as? Bool ?? false
    }

    static func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden {
            UserDefaults.standard.set(autohide, forKey: previousAutohideKey)
            CFPreferencesSetAppValue(autohideKey, kCFBooleanTrue, domain)
            CFPreferencesSetAppValue(delayKey, hiddenDelay as CFNumber, domain)
        } else {
            let previous = UserDefaults.standard.bool(forKey: previousAutohideKey)
            CFPreferencesSetAppValue(autohideKey, previous as CFBoolean, domain)
            CFPreferencesSetAppValue(delayKey, nil, domain)
        }
        CFPreferencesAppSynchronize(domain)
        restart()
    }

    /// The Dock reads these settings at launch; launchd restarts it.
    private static func restart() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        try? killall.run()
    }
}
