import AppKit
import OpenDirectory

enum SystemAction: String, CaseIterable, Identifiable {
    case appStore, activityMonitor, forceQuit, settings, aboutThisMac
    case lock, logOut, sleep, restart, shutDown

    var id: String { rawValue }

    static let tools: [SystemAction] = [.appStore, .activityMonitor, .forceQuit, .settings, .aboutThisMac]
    static let power: [SystemAction] = [.lock, .logOut, .sleep, .restart, .shutDown]

    var title: String {
        switch self {
        case .appStore: "App Store"
        case .activityMonitor: "Activity Monitor"
        case .forceQuit: "Force Quit…"
        case .settings: "System Settings"
        case .aboutThisMac: "About This Mac"
        case .lock: "Lock Screen"
        case .logOut: "Log Out…"
        case .sleep: "Sleep"
        case .restart: "Restart…"
        case .shutDown: "Shut Down…"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "bag"
        case .activityMonitor: "waveform.path.ecg"
        case .forceQuit: "xmark.octagon"
        case .settings: "gearshape"
        case .aboutThisMac: "info.circle"
        case .lock: "lock"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .sleep: "moon"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        }
    }

    /// Runs the action. The panel is already hidden at this point.
    func perform() {
        switch self {
        case .appStore: Self.openApp(bundleID: "com.apple.AppStore")
        case .activityMonitor: Self.openApp(bundleID: "com.apple.ActivityMonitor")
        case .settings: Self.openApp(bundleID: "com.apple.systempreferences")
        case .aboutThisMac:
            Self.openApp(url: URL(fileURLWithPath: "/System/Library/CoreServices/Applications/About This Mac.app"))
        case .forceQuit:
            // Same as pressing ⌥⌘⎋, which opens the system Force Quit window.
            Self.postKey(53, flags: [.maskCommand, .maskAlternate])
        case .lock: Self.lockScreen()
        case .sleep: Self.run("/usr/bin/pmset", ["sleepnow"])
        // The loginwindow events below show the system confirmation dialog.
        case .logOut: Self.sendLoginwindowEvent("logo")
        case .restart: Self.sendLoginwindowEvent("rrst")
        case .shutDown: Self.sendLoginwindowEvent("rsdn")
        }
    }

    static func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        openApp(url: url)
    }

    static func openApp(url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func sendLoginwindowEvent(_ code: String) {
        run("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to «event aevt\(code)»"])
    }

    private static func lockScreen() {
        typealias LockFunction = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: LockFunction.self)()
        } else {
            postKey(12, flags: [.maskCommand, .maskControl]) // ⌃⌘Q
        }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}

enum UserProfile {
    static var fullName: String { NSFullUserName() }

    /// The account picture from the local directory (as shown in Users & Groups).
    static func loadAvatar() -> NSImage? {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
              let record = try? node.record(
                withRecordType: kODRecordTypeUsers,
                name: NSUserName(),
                attributes: [kODAttributeTypeJPEGPhoto, kODAttributeTypePicture]
              )
        else { return nil }

        if let data = (try? record.values(forAttribute: kODAttributeTypeJPEGPhoto))?.first as? Data,
           let image = NSImage(data: data) {
            return image
        }
        if let path = (try? record.values(forAttribute: kODAttributeTypePicture))?.first as? String {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }
}
