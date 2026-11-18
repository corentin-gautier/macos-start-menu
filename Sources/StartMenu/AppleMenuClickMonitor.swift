import AppKit

/// Optional: a click on the Apple logo opens the start menu instead of the
/// Apple menu (the Apple menu can't be replaced: the system draws it).
/// ⌥-click still opens the real Apple menu, and so does the keyboard (⌃F2).
///
/// Unlike `CommandKeyMonitor`, this tap can block events, so it only asks for
/// left clicks and only exists while the option is on.
final class AppleMenuClickMonitor {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "openOnAppleMenuClick") }
        set { UserDefaults.standard.set(newValue, forKey: "openOnAppleMenuClick") }
    }

    /// Width of the Apple logo's area, from the screen edge.
    private static let logoWidth: CGFloat = 50

    private let onClick: () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The mouse-up of a swallowed mouse-down is swallowed too.
    private var swallowsMouseUp = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    /// Installs or removes the tap to match `isEnabled` (needs Accessibility).
    func update() {
        if Self.isEnabled, CommandKeyMonitor.isTrusted { install() } else { uninstall() }
    }

    private func install() {
        guard tap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<AppleMenuClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("StartMenu: could not create the Apple menu click tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func uninstall() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        swallowsMouseUp = false
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            guard !event.flags.contains(.maskAlternate), Self.isOnAppleLogo(event.location) else { return false }
            swallowsMouseUp = true
            DispatchQueue.main.async { [onClick] in onClick() }
            return true
        case .leftMouseUp:
            defer { swallowsMouseUp = false }
            return swallowsMouseUp
        default:
            return false
        }
    }

    /// `point` is in global display coordinates (origin top-left of the main
    /// screen). The menu bar must be on screen there: in full screen, or with
    /// an auto-hiding menu bar, the click belongs to the window below.
    private static func isOnAppleLogo(_ point: CGPoint) -> Bool {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let screen = NSScreen.screens.first(where: { screen in
            let frame = screen.frame
            let top = mainHeight - frame.maxY
            return point.x >= frame.minX && point.x < frame.maxX && point.y >= top && point.y < top + frame.height
        }) else { return false }
        // Right-to-left languages mirror the menu bar.
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let fromEdge = rightToLeft ? screen.frame.maxX - point.x : point.x - screen.frame.minX
        guard fromEdge < logoWidth, point.y - (mainHeight - screen.frame.maxY) < 60 else { return false }
        return menuBarFrames().contains { $0.contains(point) }
    }

    /// Frames of the menu bars on screen (Window Server's "Menubar" windows).
    private static func menuBarFrames() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == menuLevel,
                  window[kCGWindowName as String] as? String == "Menubar",
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
}
