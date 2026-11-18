import AppKit
import ApplicationServices

/// The modifier key whose lone tap opens the menu, picked in the sort menu.
enum TriggerKey: String, CaseIterable, Identifiable {
    case command, rightCommand, leftCommand, option, rightOption, globe

    var id: String { rawValue }

    static var current: TriggerKey {
        get { UserDefaults.standard.string(forKey: "triggerKey").flatMap(Self.init(rawValue:)) ?? .command }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "triggerKey") }
    }

    var title: String {
        switch self {
        case .command: L("⌘ Command (either)")
        case .rightCommand: L("Right ⌘ Command")
        case .leftCommand: L("Left ⌘ Command")
        case .option: L("⌥ Option (either)")
        case .rightOption: L("Right ⌥ Option")
        case .globe: L("🌐 Globe (fn)")
        }
    }

    /// Virtual key codes reported by `flagsChanged` for this key.
    fileprivate var keyCodes: Set<Int64> {
        switch self {
        case .command: [54, 55]
        case .rightCommand: [54]
        case .leftCommand: [55]
        case .option: [58, 61]
        case .rightOption: [61]
        case .globe: [63, 179]
        }
    }

    fileprivate var flag: CGEventFlags {
        switch self {
        case .command, .rightCommand, .leftCommand: .maskCommand
        case .option, .rightOption: .maskAlternate
        case .globe: .maskSecondaryFn
        }
    }
}

/// Detects a lone tap of the trigger key (press and release with nothing
/// else in between), like the Windows key: Command by default. Uses a
/// listen-only event tap, which requires the Accessibility permission.
final class CommandKeyMonitor {
    /// Longer presses are treated as "holding the key", not a tap.
    private let maxTapDuration: TimeInterval = 0.45
    private static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]

    var trigger = TriggerKey.current
    private let onTap: () -> Void
    private var tap: CFMachPort?
    private var permissionTimer: Timer?

    private var pressStart: TimeInterval?
    private var pressedKey: Int64 = 0
    private var cancelled = false

    /// Called once when the Accessibility permission is granted after launch.
    var onPermissionGranted: () -> Void = {}

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt, which adds Start Menu to the list
    /// in Privacy & Security › Accessibility (the user then turns it on).
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        if AXIsProcessTrusted() {
            installTap()
            return
        }
        // The onboarding card explains and asks (see StartMenuModel.Onboarding);
        // poll until the permission is granted.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.installTap()
            self?.onPermissionGranted()
        }
    }

    private func installTap() {
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<CommandKeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("StartMenu: could not create event tap, retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installTap() }
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Events were lost while the tap was off: drop the press in progress.
            pressStart = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let active = event.flags.intersection(Self.modifiers)
            if pressStart == nil {
                if trigger.keyCodes.contains(keyCode), active == trigger.flag {
                    pressStart = ProcessInfo.processInfo.systemUptime
                    pressedKey = keyCode
                    cancelled = false
                }
            } else if keyCode == pressedKey, !active.contains(trigger.flag) {
                if let start = pressStart, !cancelled, active.isEmpty,
                   ProcessInfo.processInfo.systemUptime - start < maxTapDuration,
                   !Self.inputSince(ProcessInfo.processInfo.systemUptime - start) {
                    DispatchQueue.main.async { [onTap] in onTap() }
                }
                pressStart = nil
                cancelled = false
            } else {
                // Another modifier joined in: a shortcut, not a tap.
                cancelled = true
            }

        default:
            // Any key or click while the key is down means it was a shortcut.
            if pressStart != nil { cancelled = true }
        }
    }

    /// Whether a key or click reached the system in the last `interval`
    /// seconds. Catches what the tap never sees: system shortcuts such as
    /// ⌘Tab are consumed before session taps, and a disabled tap drops events.
    private static func inputSince(_ interval: TimeInterval) -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.contains {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) < interval
        }
    }
}
