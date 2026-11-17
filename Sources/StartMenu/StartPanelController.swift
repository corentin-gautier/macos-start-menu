import AppKit
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
    static let cornerRadius: CGFloat = 20
    static let gridColumns = 6
    /// Gap between the menu bar and the panel, and from the screen's left edge.
    static let margin: CGFloat = 6
}

final class StartPanelController: NSObject, NSWindowDelegate {
    private let panel = StartPanel()
    private let model = StartMenuModel()
    private var keyMonitor: Any?

    override init() {
        super.init()
        model.dismiss = { [weak self] in self?.hide() }
        panel.delegate = self
        panel.contentView = makeContentView()
        installKeyMonitor()
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
        let hosting = NSHostingView(rootView: StartMenuView(model: model))
        hosting.sizingOptions = []

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Layout.cornerRadius
            glass.contentView = hosting
            return glass
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Layout.cornerRadius
        effect.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// Arrow keys move the selection, Return opens it, Escape closes.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if modifiers.contains(.command), event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
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
