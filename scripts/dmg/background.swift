// Draws the DMG window background (an arrow from the app to Applications)
// at 1x and 2x, then: tiffutil -cathidpicheck background.png background@2x.png
// -out background.tiff. Usage: swift scripts/dmg/background.swift <output folder>
import AppKit

let size = NSSize(width: 540, height: 360)
let out = CommandLine.arguments.dropFirst().first ?? "."

for scale in [1, 2] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor(white: 0.96, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    // Icons sit at x 140 and 400, y 170 from the top (create-dmg coordinates).
    let y = size.height - 170
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 228, y: y))
    arrow.line(to: NSPoint(x: 306, y: y))
    arrow.move(to: NSPoint(x: 292, y: y + 13))
    arrow.line(to: NSPoint(x: 308, y: y))
    arrow.line(to: NSPoint(x: 292, y: y - 13))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(white: 0.62, alpha: 1).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
