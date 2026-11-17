import AppKit
import SwiftUI

// Hover is computed by hand instead of with SwiftUI's `onHover`, whose
// tracking stops now and then in a panel of an app that is never active
// (typically after a context menu). Views report their frames, the hosting
// view reports the mouse position, the model hit-tests.

enum HoverSpace {
    static let name = "startMenu"
    /// Frame of the scrolling area: results outside it are clipped, not hoverable.
    static let viewportID = "viewport"
    static func resultID(_ id: String) -> String { "result:\(id)" }
    static func actionID(_ action: SystemAction) -> String { "action:\(action.rawValue)" }
    static let userID = "user"
}

struct HoverFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame for hover hit-testing under `id`.
    func hoverFrame(_ id: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(
                key: HoverFramesKey.self,
                value: [id: geometry.frame(in: .named(HoverSpace.name))]
            )
        })
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
