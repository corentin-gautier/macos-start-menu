import AppKit
import SwiftUI

// Hover is computed by hand instead of with SwiftUI's `onHover`, whose
// tracking stops now and then in a panel of an app that is never active
// (typically after a context menu). Views report their frames, the hosting
// view reports the mouse position, the model hit-tests.

enum HoverSpace {
    static let name = "startMenu"
    /// Floating bars: results scrolled under them are not hoverable.
    static func blockerID(_ name: String) -> String { "block:\(name)" }
    static func resultID(_ id: String) -> String { "result:\(id)" }
    static func actionID(_ action: SystemAction) -> String { "action:\(action.rawValue)" }
    static let userID = "user"
    static let sortID = "sort"
}

/// Frames of the hoverable views, in the root coordinate space. Views write
/// here directly (no preference merging on every scroll frame); the model is
/// told once per run loop pass.
final class HoverRegistry {
    static let shared = HoverRegistry()
    private(set) var frames: [String: CGRect] = [:]
    var onChange: ([String: CGRect]) -> Void = { _ in }
    private var scheduled = false

    /// Frames per ID and per reporting view, latest last. Two views can
    /// share an ID for a moment (old and new bottom bar on a style switch,
    /// both reporting): the one that leaves must not erase the other's frame.
    private var reports: [String: [(owner: UUID, frame: CGRect)]] = [:]

    func set(_ id: String, _ frame: CGRect, owner: UUID) {
        var list = reports[id, default: []].filter { $0.owner != owner }
        list.append((owner, frame))
        reports[id] = list
        update(id)
    }

    func remove(_ id: String, owner: UUID) {
        reports[id]?.removeAll { $0.owner == owner }
        if reports[id]?.isEmpty == true { reports[id] = nil }
        update(id)
    }

    private func update(_ id: String) {
        let frame = reports[id]?.last?.frame
        guard frames[id] != frame else { return }
        frames[id] = frame
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async {
            self.scheduled = false
            self.onChange(self.frames)
        }
    }
}

extension View {
    /// Reports this view's frame for hover hit-testing under `id`.
    func hoverFrame(_ id: String) -> some View {
        modifier(HoverFrame(id: id))
    }
}

private struct HoverFrame: ViewModifier {
    let id: String
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HoverSpace.name)) } action: {
                HoverRegistry.shared.set(id, $0, owner: owner)
            }
            .onDisappear { HoverRegistry.shared.remove(id, owner: owner) }
    }
}

/// Hosting view that always receives mouse moves, whatever the key or
/// active state of its window.
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseMove: (CGPoint?) -> Void = { _ in }
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        report(event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMove(nil)
    }

    /// Mouse position in SwiftUI coordinates (origin top-left).
    func currentMouseLocation() -> CGPoint? {
        guard let window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = topLeftPoint(convert(inWindow, from: nil))
        return bounds.contains(CGPoint(x: point.x, y: point.y)) ? point : nil
    }

    private func report(_ event: NSEvent) {
        onMouseMove(topLeftPoint(convert(event.locationInWindow, from: nil)))
    }

    private func topLeftPoint(_ point: NSPoint) -> CGPoint {
        isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
