import AppKit
import ApplicationServices

/// Detects a lone tap of either Command key (press and release with nothing
/// else in between), like the Windows key. Uses a listen-only event tap, which
/// requires the Accessibility permission.
final class CommandKeyMonitor {
    /// Longer presses are treated as "holding Command", not a tap.
    private let maxTapDuration: TimeInterval = 0.45

    private let onTap: () -> Void
    private var tap: CFMachPort?
    private var permissionTimer: Timer?

    private var pressStart: TimeInterval?
    private var cancelled = false

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func start() {
        if AXIsProcessTrusted() {
            installTap()
            return
        }
        // Shows the system prompt pointing to Privacy & Security > Accessibility.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.installTap()
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
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let flags = event.flags
            let command = flags.contains(.maskCommand)
            let others = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn])

            if command {
                if pressStart == nil, others.isEmpty {
                    pressStart = ProcessInfo.processInfo.systemUptime
                    cancelled = false
                } else if !others.isEmpty {
                    cancelled = true
                }
            } else {
                if let start = pressStart, !cancelled, others.isEmpty,
                   ProcessInfo.processInfo.systemUptime - start < maxTapDuration {
                    DispatchQueue.main.async { [onTap] in onTap() }
                }
                pressStart = nil
                cancelled = false
            }

        default:
            // Any key or click while Command is down means it was a shortcut.
            if pressStart != nil { cancelled = true }
        }
    }
}
