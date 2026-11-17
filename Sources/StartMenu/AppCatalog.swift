import AppKit
import CoreServices

struct AppEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let url: URL
    /// Symlink-resolved path, also the key for usage statistics.
    let path: String
    let bundleID: String?
    let category: AppCategory
    /// Spotlight's usage data, used until Start Menu has its own.
    let spotlightLastUsed: Date?
    let spotlightUseCount: Int
    let key: SearchKey
}

/// Lists the installed applications by reading the app folders directly
/// (no Spotlight search), so only `.app` bundles ever show up.
enum AppCatalog {
    private static let roots: [(URL, Int)] = [
        (URL(fileURLWithPath: "/Applications"), 2),
        (URL(fileURLWithPath: "/System/Applications"), 2),
        (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), 2),
    ]

    static func scan() -> [AppEntry] {
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var entries: [AppEntry] = []
        let ownBundleID = Bundle.main.bundleIdentifier

        for (root, depth) in roots {
            for url in findApps(in: root, depth: depth) {
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

final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url.path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: url.path as NSString)
        return icon
    }
}
