// Helper for scripts/screenshots.sh.
//   backdrop <out.png>   writes the colorful gradient the glass refracts
//   park-mouse           moves the mouse to the bottom-left corner of the main screen
//   panel-rect           prints "x,y,w,h" of the demo backdrop window (panel ± margin)
import AppKit

func backdrop(to path: String) {
    let w = 1600, h = 1600
    let corners: [[Double]] = [[0.40, 0.55, 1.00], [0.95, 0.45, 0.75], [0.35, 0.80, 0.80], [0.95, 0.65, 0.35]] // TL TR BL BR
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let p = rep.bitmapData!
    for y in 0..<h {
        for x in 0..<w {
            let u = Double(x) / Double(w - 1), v = Double(y) / Double(h - 1)
            // Soft light glow in the middle.
            let glow = max(0, 1 - hypot(u - 0.55, v - 0.45) / 0.45) * 0.35
            for k in 0..<3 {
                let top = corners[0][k] * (1 - u) + corners[1][k] * u
                let bottom = corners[2][k] * (1 - u) + corners[3][k] * u
                let value = (top * (1 - v) + bottom * v) * (1 - glow) + (k == 1 ? 0.85 : 0.95) * glow
                p[(y * w + x) * 3 + k] = UInt8(max(0, min(255, value * 255)))
            }
        }
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func parkMouse() {
    let main = CGDisplayBounds(CGMainDisplayID())
    let point = CGPoint(x: main.minX + 5, y: main.maxY - 5)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
            mouseButton: .left)!.post(tap: .cghidEventTap)
}

func panelRect() {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let frames = windows
        .filter { $0[kCGWindowOwnerName as String] as? String == "Start Menu" }
        .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
    // The backdrop is the largest StartMenu window: it surrounds the panel.
    guard let r = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { exit(1) }
    print("\(r.minX),\(r.minY),\(r.width),\(r.height)")
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "backdrop" where args.count > 2: backdrop(to: args[2])
case "park-mouse": parkMouse()
case "panel-rect": panelRect()
default:
    FileHandle.standardError.write("usage: screenshot-helper backdrop <out.png> | park-mouse | panel-rect\n".data(using: .utf8)!)
    exit(2)
}
