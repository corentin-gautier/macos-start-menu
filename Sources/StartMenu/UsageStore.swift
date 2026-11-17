import AppKit

/// Records when and how often each app comes to the front, for the "Recent"
/// and "Most used" sorts. Spotlight's own usage data is too sparse to rely on.
final class UsageStore {
    static let shared = UsageStore()

    private let defaults = UserDefaults.standard
    private var lastUsed: [String: Double]
    private var counts: [String: Int]

    private init() {
        lastUsed = defaults.dictionary(forKey: "usage.lastUsed") as? [String: Double] ?? [:]
        counts = defaults.dictionary(forKey: "usage.counts") as? [String: Int] ?? [:]
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let path = app?.bundleURL?.resolvingSymlinksInPath().path { self?.record(path) }
        }
    }

    private func record(_ path: String) {
        lastUsed[path] = Date().timeIntervalSince1970
        counts[path, default: 0] += 1
        defaults.set(lastUsed, forKey: "usage.lastUsed")
        defaults.set(counts, forKey: "usage.counts")
    }

    func lastUsed(_ app: AppEntry) -> Date? {
        lastUsed[app.path].map(Date.init(timeIntervalSince1970:)) ?? app.spotlightLastUsed
    }

    func useCount(_ app: AppEntry) -> Int {
        counts[app.path, default: 0] + app.spotlightUseCount
    }
}
