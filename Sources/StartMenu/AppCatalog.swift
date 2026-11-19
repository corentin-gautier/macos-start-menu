import AppKit
import CoreServices
import UniformTypeIdentifiers

struct AppEntry: Identifiable, Hashable {
    var id: String { path }
    /// Display name: the user's custom name, if any (see `StartMenuModel.rename`).
    var name: String
    let url: URL
    /// Symlink-resolved path, also the key for usage statistics.
    let path: String
    let bundleID: String?
    let category: AppCategory
    /// Spotlight's usage data, used until Start Menu has its own.
    let spotlightLastUsed: Date?
    let spotlightUseCount: Int
    var key: SearchKey
}

/// Lists the installed applications by reading the app folders directly
/// (no Spotlight search), so only `.app` bundles ever show up.
enum AppCatalog {
    private static let roots: [(URL, Int)] = [
        (URL(fileURLWithPath: "/Applications"), 2),
        (URL(fileURLWithPath: "/System/Applications"), 2),
        (URL(fileURLWithPath: "/System/Library/CoreServices/Applications"), 1),
        (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), 2),
    ]
    /// The Finder lives outside the app folders.
    private static let extraApps = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

    static func scan() -> [AppEntry] {
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var entries: [AppEntry] = []
        let ownBundleID = Bundle.main.bundleIdentifier

        let candidates = roots.flatMap { findApps(in: $0.0, depth: $0.1) }
            + extraApps.filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in candidates {
            let path = url.resolvingSymlinksInPath().path
            guard seenPaths.insert(path).inserted else { continue }
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            if let bundleID {
                if bundleID == ownBundleID { continue }
                guard seenBundleIDs.insert(bundleID).inserted else { continue }
            }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            let usage = spotlightUsage(url)
            entries.append(AppEntry(
                name: name,
                url: url,
                path: path,
                bundleID: bundleID,
                category: AppCategory.of(url: url, bundle: bundle),
                spotlightLastUsed: usage.lastUsed,
                spotlightUseCount: usage.count,
                key: SearchKey(name)
            ))
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func findApps(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let items = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        var apps: [URL] = []
        for item in items {
            if item.pathExtension == "app" {
                apps.append(item)
            } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                apps += findApps(in: item, depth: depth - 1)
            }
        }
        return apps
    }

    private static func spotlightUsage(_ url: URL) -> (lastUsed: Date?, count: Int) {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return (nil, 0) }
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 0
        return (lastUsed, count)
    }
}

/// App icons rasterized once to a single bitmap at display size. The icons
/// macOS returns hold many representations (icns) and are re-rendered every
/// frame otherwise, which makes scrolling stutter.
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    /// Points; the bitmap is 2x for Retina.
    private let size: CGFloat = 64

    func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url.path as NSString) { return cached }
        let icon = rasterize(NSWorkspace.shared.icon(forFile: url.path))
        cache.setObject(icon, forKey: url.path as NSString)
        return icon
    }

    /// The generic icon of a file type (no file access).
    func icon(forType identifier: String?) -> NSImage {
        let key = "type:\(identifier ?? "")" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let type = identifier.flatMap(UTType.init) ?? .data
        let icon = rasterize(NSWorkspace.shared.icon(for: type))
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Warms the cache in the background so tiles never wait for an icon.
    func preload(_ urls: [URL]) {
        DispatchQueue.global(qos: .utility).async {
            for url in urls { _ = self.icon(for: url) }
        }
    }

    private func rasterize(_ source: NSImage) -> NSImage {
        let pixels = Int(size * 2)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        bitmap.size = NSSize(width: size, height: size)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }
}
