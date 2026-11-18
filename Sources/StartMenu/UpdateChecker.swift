import AppKit

/// Looks for a newer release on GitHub at launch and once a day (the app
/// isn't notarized nor on the App Store: nothing else tells users about
/// updates). A newer version shows in the sort menu.
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesPage = URL(string: "https://github.com/corentin-gautier/macos-start-menu/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/corentin-gautier/macos-start-menu/releases/latest")!

    /// The newer version available, if any.
    private(set) var availableVersion: String?
    /// Called on the main thread when `availableVersion` changes.
    var onChange: () -> Void = {}
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StartMenu", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let newer = Self.isVersion(latest, newerThan: Self.currentVersion) ? latest : nil
            DispatchQueue.main.async {
                guard newer != self.availableVersion else { return }
                self.availableVersion = newer
                self.onChange()
            }
        }.resume()
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
