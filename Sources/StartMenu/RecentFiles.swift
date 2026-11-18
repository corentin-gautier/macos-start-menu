import AppKit
import UniformTypeIdentifiers

/// A document: a recently opened file, or a file pinned by dropping it on
/// the menu.
struct FileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let typeIdentifier: String?
    /// Last opened (Spotlight's `kMDItemLastUsedDate`); nil for pinned files.
    let lastUsed: Date?
    let key: SearchKey

    var id: String { url.path }

    init(url: URL, typeIdentifier: String? = nil, lastUsed: Date? = nil) {
        self.url = url
        name = url.lastPathComponent
        self.typeIdentifier = typeIdentifier ?? UTType(filenameExtension: url.pathExtension)?.identifier
        self.lastUsed = lastUsed
        key = SearchKey(url.deletingPathExtension().lastPathComponent)
    }

    /// "2 hr. ago · Downloads", or the abbreviated folder for pinned files.
    var subtitle: String {
        let folder = url.deletingLastPathComponent()
        guard let lastUsed else { return AppUninstaller.abbreviate(folder) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = Date().timeIntervalSince(lastUsed) < 60 ? L("Just now") : formatter.localizedString(for: lastUsed, relativeTo: Date())
        return "\(when) · \(FileManager.default.displayName(atPath: folder.path))"
    }

    /// The icon of the file's type: reading the file itself (its own icon or
    /// a thumbnail) would ask for access to Desktop, Documents, Downloads…
    var icon: NSImage { IconCache.shared.icon(forType: typeIdentifier) }
}

/// Documents opened in the last 30 days, most recent first, from Spotlight
/// (the same data as the Finder's Recents). Apps, folders and files inside
/// ~/Library or packages are left out.
final class RecentFiles {
    static let shared = RecentFiles()

    private(set) var files: [FileEntry] = []
    /// Called on the main thread when `files` changes.
    var onChange: () -> Void = {}

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private let maxCount = 40
    private let maxAge: TimeInterval = 30 * 86_400
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "logicx", "band", "xcodeproj", "xcworkspace", "xcassets", "plugin", "appex",
    ]
    private static let excludedTypes: Set<String> = [
        "com.apple.application-bundle", "public.folder", "com.apple.mount-point", "public.volume",
    ]

    /// Runs a new query unless one is already running; cheap enough on every opening.
    func refresh() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@", Date(timeIntervalSinceNow: -maxAge) as NSDate)
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in self?.finish() }
        self.query = query
        query.start()
    }

    private func finish() {
        guard let query else { return }
        query.disableUpdates()
        var found: [FileEntry] = []
        for index in 0..<query.resultCount {
            guard found.count < maxCount else { break }
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  isDocument(path)
            else { continue }
            let type = item.value(forAttribute: "kMDItemContentType") as? String
            if let type, Self.excludedTypes.contains(type) { continue }
            let date = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            found.append(FileEntry(url: URL(fileURLWithPath: path), typeIdentifier: type, lastUsed: date))
        }
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        self.query = nil
        observer = nil
        guard found != files else { return }
        files = found
        onChange()
    }

    // MARK: - Folder access

    /// Spotlight silently leaves out the files of these folders until the
    /// app may read them (macOS privacy protection).
    private static let protectedFolders = ["Desktop", "Documents", "Downloads"].map {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path
    }
    private static let askedKey = "askedRecentFilesFolderAccess"

    /// Reading a folder asks for access only the first time; afterwards it
    /// just fails while access is denied.
    static var needsFolderAccess: Bool {
        guard UserDefaults.standard.bool(forKey: askedKey) else { return true }
        return protectedFolders.contains { (try? FileManager.default.contentsOfDirectory(atPath: $0)) == nil }
    }

    /// Shows the system access prompts (one per folder); once they were
    /// answered, opens Privacy & Security › Files & Folders instead.
    func requestFolderAccess() {
        let asked = UserDefaults.standard.bool(forKey: Self.askedKey)
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        DispatchQueue.global(qos: .userInitiated).async {
            let denied = Self.protectedFolders.filter { (try? FileManager.default.contentsOfDirectory(atPath: $0)) == nil }
            DispatchQueue.main.async {
                if asked && !denied.isEmpty {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders")!)
                }
                self.refresh()
            }
        }
    }

    private func isDocument(_ path: String) -> Bool {
        guard path.hasPrefix(home + "/"), !path.hasPrefix(home + "/Library/") else { return false }
        let components = path.dropFirst(home.count + 1).split(separator: "/")
        for component in components.dropLast() {
            if component.hasPrefix(".") { return false }
            if let dot = component.lastIndex(of: "."),
               Self.packageExtensions.contains(component[component.index(after: dot)...].lowercased()) {
                return false
            }
        }
        // The Music app's own copies of imported files.
        if path.contains("/Music/Music/Media") { return false }
        return !(components.last?.hasPrefix(".") ?? true)
    }
}
