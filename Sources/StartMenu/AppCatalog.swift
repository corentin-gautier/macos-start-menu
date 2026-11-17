import AppKit

struct AppEntry: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let bundleID: String?
    let key: SearchKey
}

/// Lists the installed applications by reading the app folders directly
/// (no Spotlight), so only `.app` bundles ever show up.
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
                let bundleID = Bundle(url: url)?.bundleIdentifier
                if let bundleID {
                    if bundleID == ownBundleID { continue }
                    guard seenBundleIDs.insert(bundleID).inserted else { continue }
                }
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                entries.append(AppEntry(name: name, url: url, bundleID: bundleID, key: SearchKey(name)))
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
