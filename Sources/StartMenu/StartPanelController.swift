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
    private let model = StartMenuModel()
    private var keyMonitor: Any?
    private var styleObserver: AnyCancellable?
    private weak var hosting: TrackingHostingView<StartMenuView>?

    override init() {
        super.init()
        model.dismiss = { [weak self] in self?.hide() }
        panel.delegate = self
        panel.contentView = makeContentView()
        installKeyMonitor()
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

        // Top-left of the screen under the mouse, right below the Apple menu.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let height = min(Layout.panelHeight, visible.height - Layout.margin * 2)
        let frame = NSRect(
            x: visible.minX + Layout.margin,
            y: visible.maxY - Layout.margin - height,
            width: Layout.panelWidth,
            height: height
        )

        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        model.mouseMoved(to: hosting?.currentMouseLocation())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
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
        glass.cornerRadius = model.style.panelCornerRadius
        glass.contentView = hosting
        styleObserver = model.$style.sink { [weak glass] in glass?.cornerRadius = $0.panelCornerRadius }
        return glass
    }

    /// Arrow keys move the selection, Return opens it, Escape closes.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Uninstall confirmation: Escape and Return (the default) cancel.
            if self.model.pendingUninstall != nil {
                if [53, 36, 76].contains(event.keyCode) {
                    self.model.cancelUninstall()
                    return nil
                }
                return modifiers.contains(.command) ? event : nil
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
