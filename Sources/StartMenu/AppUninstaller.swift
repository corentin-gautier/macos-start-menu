import AppKit

/// Moves an app and the files it left in ~/Library to the Trash, after
/// confirmation. Everything stays recoverable with the Finder's "Put Back".
enum AppUninstaller {
    /// System apps live on the read-only system volume (Safari is a link to it).
    static func canUninstall(_ app: AppEntry) -> Bool {
        !app.path.hasPrefix("/System/") && app.bundleID != "com.apple.Safari"
    }

    /// Returns true if the app was moved to the Trash.
    @discardableResult
    static func uninstall(_ app: AppEntry, installed: [AppEntry]) -> Bool {
        let leftovers = Leftovers.find(for: app, installed: installed)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Uninstall “\(app.name)”?"
        alert.informativeText = leftovers.isEmpty
            ? "The app will be moved to the Trash."
            : "The app and the \(leftovers.count) item\(leftovers.count == 1 ? "" : "s") it left in your Library "
                + "(settings, caches, data) will be moved to the Trash."
        alert.icon = IconCache.shared.icon(for: app.url)
        if !leftovers.isEmpty { alert.accessoryView = listView(leftovers) }
        alert.addButton(withTitle: "Move to Trash").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        quitIfRunning(app)

        guard trash(app.url) else {
            showError("“\(app.name)” couldn’t be moved to the Trash.")
            return false
        }
        let failed = leftovers.filter { !trash($0) }
        if !failed.isEmpty {
            showError("Some of “\(app.name)”’s files couldn’t be removed:\n"
                + failed.map { abbreviate($0) }.joined(separator: "\n"))
        }
        return true
    }

    // MARK: - Helpers

    private static func quitIfRunning(_ app: AppEntry) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.resolvingSymlinksInPath().path == app.path
                || (app.bundleID != nil && $0.bundleIdentifier == app.bundleID)
        }
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, running.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// Tries directly, then through the Finder, which handles items owned by
    /// root or protected by macOS (it asks for an administrator password).
    private static func trash(_ url: URL) -> Bool {
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { return true }
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"\(path)\" as alias)")?
            .executeAndReturnError(&error)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.runModal()
    }

    private static func abbreviate(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func listView(_ urls: [URL]) -> NSView {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 10))
        text.string = urls.map(abbreviate).joined(separator: "\n")
        text.isEditable = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textColor = .secondaryLabelColor
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: min(160, CGFloat(urls.count) * 16 + 8)))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }
}

/// Finds what an app leaves in ~/Library (system-wide /Library is left alone).
/// Matching is deliberately strict:
/// bundle ID (exact, or followed by a dot) everywhere, and the exact app name
/// only in the folders where apps name things after themselves.
enum Leftovers {
    private static let byBundleID = [
        "Application Support", "Caches", "Preferences", "Saved Application State", "Containers",
        "Group Containers", "HTTPStorages", "WebKit", "Logs", "Cookies", "Application Scripts",
        "LaunchAgents", "Preferences/ByHost",
    ]
    private static let byName = ["Application Support", "Caches", "Logs"]

    /// Folders shared by many apps or vendors, never removed by name.
    private static let protectedNames: Set<String> = [
        "apple", "google", "microsoft", "adobe", "com.apple", "crashreporter", "cloudkit",
    ]

    /// `installed` keeps files of other apps whose bundle ID extends this one
    /// (e.g. "com.google.chrome.for.testing" when removing Chrome).
    static func find(for app: AppEntry, installed: [AppEntry] = []) -> [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let bundleID = app.bundleID?.lowercased()
        let name = app.name.lowercased()
        let names = Set([name, (app.url.deletingPathExtension().lastPathComponent).lowercased()])
            .filter { $0.count >= 4 && !protectedNames.contains($0) }
        let longerIDs = installed.compactMap { $0.bundleID?.lowercased() }
            .filter { bundleID != nil && $0 != bundleID && $0.hasPrefix(bundleID! + ".") }
        var found: [URL] = []

        for folder in Set(byBundleID + byName) {
            let directory = library.appendingPathComponent(folder)
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for item in items {
                let lower = item.lowercased()
                var match = false
                if let bundleID, byBundleID.contains(folder) {
                    // "com.app.id", "com.app.id.plist", "com.app.id.savedState",
                    // and group containers like "TEAMID.com.app.id".
                    match = lower == bundleID || lower.hasPrefix(bundleID + ".")
                        || (folder == "Group Containers" && lower.hasSuffix("." + bundleID))
                    if longerIDs.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) { match = false }
                }
                if !match, byName.contains(folder) { match = names.contains(lower) }
                if match { found.append(directory.appendingPathComponent(item)) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }
}
