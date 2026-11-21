import AppKit
import Combine
import SwiftUI

/// Borderless panel that takes keyboard focus without activating the app,
/// so the frontmost app stays frontmost (like Spotlight).
final class StartPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum Layout {
    static let panelWidth: CGFloat = 640
    static let panelHeight: CGFloat = 640
    static let gridColumns = 6
    /// Gap between the menu bar and the panel, and from the screen's left edge.
    static let margin: CGFloat = 6
}

final class StartPanelController: NSObject, NSWindowDelegate {
    private let panel = StartPanel()
    let model = StartMenuModel()
    private var keyMonitor: Any?
    private let demoBackdrop = DemoBackdrop.fromEnvironment()
    private var styleObserver: AnyCancellable?
    private var navigationObserver: AnyCancellable?
    private weak var hosting: TrackingHostingView<StartMenuView>?

    override init() {
        super.init()
        model.dismiss = { [weak self] in self?.hide() }
        panel.delegate = self
        panel.contentView = makeContentView()
        installKeyMonitor()
        // The caret hides while the arrows drive the results.
        navigationObserver = model.$navigatesResults.removeDuplicates().sink { [weak self] navigates in
            self?.fieldEditor?.insertionPointColor = navigates ? .clear : .textColor
        }
        // A context or sort menu can leave the panel without keyboard focus.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.panel.makeKey()
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.prepareForShow()
        // Until the permission is granted, the menu keeps asking for it.
        if !CommandKeyMonitor.isTrusted { model.onboarding = .permission }
        // Screenshots: STARTMENU_DEMO_ONBOARDING=permission|ready shows that card.
        switch ProcessInfo.processInfo.environment["STARTMENU_DEMO_ONBOARDING"] {
        case "permission": model.onboarding = .permission
        case "ready": model.onboarding = .ready
        default: break
        }

        // Top-left of the screen under the mouse, right below the Apple menu.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let height = min(Layout.panelHeight, visible.height - Layout.margin * 2)
        var frame = NSRect(
            x: visible.minX + Layout.margin,
            y: visible.maxY - Layout.margin - height,
            width: Layout.panelWidth,
            height: height
        )
        if let backdrop = demoBackdrop {
            // Screenshots: centered on the main screen, over a wallpaper.
            let main = NSScreen.screens[0].frame
            frame.origin = NSPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
            backdrop.show(around: frame, below: panel)
        }

        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        model.mouseMoved(to: hosting?.currentMouseLocation())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [panel] in
            // The shadow was computed for the first animation frame and showed
            // as a gray band under the rounded bottom edge.
            panel.invalidateShadow()
        }
    }

    /// First launch: the menu opens on the onboarding card.
    func showOnboarding(_ step: StartMenuModel.Onboarding) {
        show()
        model.onboarding = step
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        demoBackdrop?.hide()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func makeContentView() -> NSView {
        let hosting = TrackingHostingView(rootView: StartMenuView(model: model))
        hosting.sizingOptions = []
        hosting.onMouseMove = { [weak model] in model?.mouseMoved(to: $0) }
        self.hosting = hosting

        let glass = NSGlassEffectView()
        glass.contentView = hosting

        // Everything is clipped to the panel's rounded shape: unclipped, a
        // faint rectangle showed in the bottom corners, and the window shadow
        // followed it as a gray band.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerCurve = .continuous
        glass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        styleObserver = model.$style.sink { [weak self, weak glass, weak container] style in
            glass?.cornerRadius = style.panelCornerRadius
            container?.layer?.cornerRadius = style.panelCornerRadius
            self?.panel.invalidateShadow()
        }
        return container
    }

    /// The search field's editor, when it has the keyboard.
    private var fieldEditor: NSTextView? { panel.firstResponder as? NSTextView }

    /// No selected text and the caret after the last character.
    private var caretAtEnd: Bool {
        guard let editor = fieldEditor else { return true }
        let range = editor.selectedRange()
        return range.length == 0 && range.location == (editor.string as NSString).length
    }

    /// Arrow keys move the selection, Return opens it, Escape closes.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Uninstall confirmation: Escape and Return (the default) cancel.
            // Onboarding card: Escape closes, Return confirms the last step.
            if let step = self.model.onboarding {
                switch event.keyCode {
                case 53:
                    self.model.onboarding = nil
                    if step == .ready { self.hide() }
                case 36, 76:
                    if step == .ready { self.model.onboarding = nil; self.hide() }
                    else { self.model.requestPermission() }
                default:
                    return event
                }
                return nil
            }

            // Force Quit window: arrows choose, Return force quits, Escape closes.
            if self.model.forceQuitApps != nil {
                switch event.keyCode {
                case 53: self.model.closeForceQuit()
                case 36, 76: self.model.forceQuitSelected()
                case 125: self.model.moveForceQuitSelection(by: 1)
                case 126: self.model.moveForceQuitSelection(by: -1)
                default: return modifiers.contains(.command) ? event : nil
                }
                return nil
            }

            if self.model.pendingUninstall != nil {
                if [53, 36, 76].contains(event.keyCode) {
                    self.model.cancelUninstall()
                    return nil
                }
                return modifiers.contains(.command) ? event : nil
            }

            // Rename card: its text field takes the keys (Return submits),
            // Escape cancels, ⌘ shortcuts go through the edit routing below.
            if self.model.pendingRename != nil {
                if event.keyCode == 53 {
                    self.model.cancelRename()
                    return nil
                }
                if !modifiers.contains(.command) { return event }
            }

            // An agent app has no Edit menu, so its standard shortcuts are
            // routed by hand to the search field's editor.
            if modifiers == .command || modifiers == [.command, .shift] {
                let editActions: [String: Selector] = [
                    "a": #selector(NSText.selectAll(_:)),
                    "c": #selector(NSText.copy(_:)),
                    "v": #selector(NSText.paste(_:)),
                    "x": #selector(NSText.cut(_:)),
                    "z": modifiers.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")),
                ]
                let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                if key == "q" {
                    NSApp.terminate(nil)
                    return nil
                }
                if let action = editActions[key] {
                    NSApp.sendAction(action, to: nil, from: nil)
                    return nil
                }
            }

            // With search text, ← and → move the caret until → reaches the end
            // of the text; that, or ↑/↓, hands the arrows to the results, and ←
            // on the first result hands them back. A modifier (⇧ selection,
            // ⌥ word, ⌘ line) always edits the text.
            if (123...126).contains(event.keyCode) {
                let editing = modifiers.subtracting([.function, .numericPad])
                if !editing.isEmpty {
                    self.model.navigatesResults = false
                    return event
                }
                if !self.model.query.isEmpty {
                    if !self.model.navigatesResults {
                        if event.keyCode == 123 { return event }
                        self.model.navigatesResults = true
                        if event.keyCode == 124 {
                            return self.caretAtEnd ? nil : event
                        }
                    } else if event.keyCode == 123, self.model.selection == 0 {
                        self.model.navigatesResults = false
                        return nil
                    }
                }
            }

            switch event.keyCode {
            case 53: // Escape
                self.hide()
            case 36, 76: // Return, Enter
                self.model.activateSelection()
            case 123:
                self.model.moveSelection(.left)
            case 124:
                self.model.moveSelection(.right)
            case 125:
                self.model.moveSelection(.down)
            case 126:
                self.model.moveSelection(.up)
            default:
                return event
            }
            return nil
        }
    }
}

/// Screenshot helper: `STARTMENU_DEMO_BACKDROP=<image>` puts that image in a
/// window behind the panel, so the glass has something to refract instead of
/// the flat gray of a window-only capture.
final class DemoBackdrop {
    /// Space around the panel.
    static let margin: CGFloat = 70
    private let window: NSWindow

    static func fromEnvironment() -> DemoBackdrop? {
        guard let path = ProcessInfo.processInfo.environment["STARTMENU_DEMO_BACKDROP"],
              let image = NSImage(contentsOfFile: path) else { return nil }
        return DemoBackdrop(image: image)
    }

    private init(image: NSImage) {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        let view = NSImageView(image: image)
        view.imageScaling = .scaleAxesIndependently
        window.contentView = view
    }

    func show(around frame: NSRect, below panel: NSWindow) {
        window.setFrame(frame.insetBy(dx: -Self.margin, dy: -Self.margin), display: true)
        window.level = NSWindow.Level(rawValue: panel.level.rawValue - 1)
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}
