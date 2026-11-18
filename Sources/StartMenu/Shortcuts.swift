import AppKit

/// A shortcut from the Shortcuts app, run without opening it.
struct ShortcutEntry: Identifiable, Hashable {
    let name: String
    let key: SearchKey

    var id: String { name }

    init(name: String) {
        self.name = name
        key = SearchKey(name)
    }

    /// Dragged out of the menu (and dropped back on it to pin).
    var url: URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }

    func run() {
        let process = Process()
        process.executableURL = ShortcutCatalog.tool
        process.arguments = ["run", name]
        try? process.run()
    }
}

/// The user's shortcuts, listed with the `shortcuts` command line tool.
final class ShortcutCatalog {
    static let shared = ShortcutCatalog()
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")
    static let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")

    private(set) var all: [ShortcutEntry] = []
    /// Called on the main thread when `all` changes.
    var onChange: () -> Void = {}
    private var isLoading = false

    func refresh() {
        guard !isLoading, FileManager.default.isExecutableFile(atPath: Self.tool.path) else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async {
            let names = Self.list()
            DispatchQueue.main.async {
                self.isLoading = false
                guard let names else { return }
                let entries = names.map(ShortcutEntry.init)
                guard entries != self.all else { return }
                self.all = entries
                self.onChange()
            }
        }
    }

    private static func list() -> [String]? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = tool
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
