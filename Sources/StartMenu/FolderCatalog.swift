import AppKit

/// A user folder offered in search results (opened in the Finder).
struct FolderEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let key: SearchKey
    let keywordKeys: [SearchKey]

    var id: String { url.path }

    init(url: URL, name: String, keywords: [String]) {
        self.url = url
        self.name = name
        key = SearchKey(name)
        keywordKeys = keywords.map(SearchKey.init)
    }

    /// Same rules as settings: name matches rank above keyword matches.
    func score(_ query: String) -> Int? {
        let nameScore = Search.score(query, key)
        let keywordScore = keywordKeys.compactMap { Search.score(query, $0, fuzzy: false) }.max().map { $0 - 150 }
        return [nameScore, keywordScore].compactMap { $0 }.max()
    }
}

/// The standard folders of the user's home, with English and French keywords.
enum FolderCatalog {
    static let all: [FolderEntry] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(URL, [String])] = [
            (home, ["home", "maison", "dossier personnel", "utilisateur", "user", NSUserName()]),
            (home.appendingPathComponent("Desktop"), ["desktop", "bureau"]),
            (home.appendingPathComponent("Documents"), ["documents", "docs", "fichiers", "files"]),
            (home.appendingPathComponent("Downloads"), ["downloads", "téléchargements", "telechargements"]),
            (home.appendingPathComponent("Pictures"), ["pictures", "images", "photos", "screenshots", "captures"]),
            (home.appendingPathComponent("Movies"), ["movies", "videos", "vidéos", "films"]),
            (home.appendingPathComponent("Music"), ["music", "musique", "audio"]),
            (home.appendingPathComponent("Applications"), ["applications", "apps"]),
            (home.appendingPathComponent("Public"), ["public", "partage", "shared"]),
            (home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), ["icloud", "icloud drive", "cloud"]),
            (home.appendingPathComponent(".Trash"), ["trash", "corbeille", "bin"]),
        ]
        return candidates.compactMap { url, keywords in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return FolderEntry(url: url, name: displayName(url, home: home), keywords: keywords)
        }
    }()

    private static func displayName(_ url: URL, home: URL) -> String {
        if url == home { return "Home" }
        switch url.lastPathComponent {
        case "com~apple~CloudDocs": return "iCloud Drive"
        case ".Trash": return "Trash"
        default: return FileManager.default.displayName(atPath: url.path)
        }
    }

    /// Folder icons (Desktop, Downloads… have their own); the Trash shows the
    /// Finder's trash icon.
    static func icon(for folder: FolderEntry) -> NSImage {
        if folder.url.lastPathComponent == ".Trash", let trash = NSImage(named: NSImage.trashEmptyName) {
            return trash
        }
        return IconCache.shared.icon(for: folder.url)
    }
}
