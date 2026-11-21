import AppKit
import SwiftUI
import Combine

enum StartResult: Identifiable {
    case app(AppEntry)
    case setting(SettingEntry)
    case folder(FolderEntry)
    case file(FileEntry)
    case shortcut(ShortcutEntry)
    case calculation(Calculation)
    case fileSearch(String)
    case webSearch(String)

    var id: String {
        switch self {
        case .app(let app): "app:\(app.id)"
        case .setting(let setting): "setting:\(setting.id)"
        case .folder(let folder): "folder:\(folder.id)"
        case .file(let file): "file:\(file.id)"
        case .shortcut(let shortcut): "shortcut:\(shortcut.id)"
        case .calculation: "calculation"
        case .fileSearch: "fileSearch"
        case .webSearch: "web"
        }
    }

    var isPinnable: Bool {
        switch self {
        case .calculation, .fileSearch, .webSearch: false
        default: true
        }
    }
}

/// How a section lays out its items.
enum SectionStyle {
    /// Icon tiles, `Layout.gridColumns` per row.
    case tiles
    /// Full-width rows.
    case rows
    /// Rows in two columns (recent files).
    case twoColumns

    var columns: Int {
        switch self {
        case .tiles: Layout.gridColumns
        case .rows: 1
        case .twoColumns: 2
        }
    }
}

/// A titled block of results.
struct ResultSection: Identifiable {
    let title: String
    let style: SectionStyle
    let items: [StartResult]
    /// Index of the first item in the flat result list.
    let startIndex: Int
    /// Pinned items also appear in the sections below: keys stay unique.
    var keyPrefix = ""

    var id: String { title }
    var isPinned: Bool { !keyPrefix.isEmpty }

    /// View identity of an item (scroll target, hover ID).
    func key(for result: StartResult) -> String { keyPrefix + result.id }
}

enum SortMode: String, CaseIterable, Identifiable {
    case alphabetical, recent, mostUsed, categories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: L("A–Z")
        case .recent: L("Recent")
        case .mostUsed: L("Most used")
        case .categories: L("Categories")
        }
    }

    var symbol: String {
        switch self {
        case .alphabetical: "textformat"
        case .recent: "clock"
        case .mostUsed: "chart.bar"
        case .categories: "square.grid.2x2"
        }
    }
}

enum UIStyle: String, CaseIterable, Identifiable {
    case glass, classic

    var id: String { rawValue }
    var title: String { self == .glass ? L("Liquid Glass") : L("Classic") }
    var symbol: String { self == .glass ? "drop" : "square" }
}

enum AppLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }
    var title: String { self == .grid ? L("Grid") : L("List") }
    var symbol: String { self == .grid ? "square.grid.3x3" : "list.bullet" }
}

enum MoveDirection { case left, right, up, down }

final class StartMenuModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            navigatesResults = false
            updateResults()
        }
    }
    /// The arrow keys left the search text for the results (→ at the end of
    /// the text, ↑/↓); typing or ← on the first result goes back to the text.
    @Published var navigatesResults = false
    @Published var sortMode: SortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode")
            updateResults()
        }
    }
    @Published var style: UIStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") }
    }
    @Published var layout: AppLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: "layout")
            updateResults()
        }
    }
    @Published private(set) var sections: [ResultSection] = []
    @Published private(set) var selection = 0
    /// Selection is only highlighted while searching or after an arrow key.
    @Published private(set) var showsSelection = false
    /// Changes every time the panel opens, so the view refocuses and scrolls up.
    @Published private(set) var showToken = UUID()
    @Published private(set) var avatar: NSImage?
    /// Hover is hit-tested here (see Hover.swift).
    @Published private(set) var hoveredID: String?
    private var hoverFrames: [String: CGRect] = [:]
    private var mouseLocation: CGPoint?
    @Published private(set) var pendingUninstall: UninstallRequest?
    /// Apps listed by the in-panel Force Quit window, nil when it is closed.
    /// (A synthesized ⌥⌘⎋ doesn't open the system one: it is a protected hotkey.)
    @Published private(set) var forceQuitApps: [NSRunningApplication]?

    enum Onboarding { case permission, ready }
    /// First-launch card: asks for Accessibility, then confirms it works.
    @Published var onboarding: Onboarding? { didSet { refreshHover() } }
    @Published private(set) var opensAtLogin = LoginItem.isEnabled
    @Published private(set) var hidesDock = Dock.isHidden
    @Published private(set) var forceQuitSelection = 0
    /// Bundle paths of the running apps (dot under their tile).
    @Published private(set) var runningPaths = RunningApps.shared.paths
    /// A newer release on GitHub, shown in the sort menu.
    @Published private(set) var availableUpdate = UpdateChecker.shared.availableVersion
    @Published var showsRecentFiles = UserDefaults.standard.object(forKey: "showsRecentFiles") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsRecentFiles, forKey: "showsRecentFiles")
            updateResults()
        }
    }
    @Published var triggerKey = TriggerKey.current {
        didSet {
            TriggerKey.current = triggerKey
            onTriggerKeyChange(triggerKey)
        }
    }
    @Published var opensOnAppleMenuClick = AppleMenuClickMonitor.isEnabled {
        didSet {
            AppleMenuClickMonitor.isEnabled = opensOnAppleMenuClick
            onAppleMenuClickChange()
        }
    }
    @Published var webSearchEngine = WebSearchEngine.current {
        didSet { WebSearchEngine.current = webSearchEngine }
    }
    var onTriggerKeyChange: (TriggerKey) -> Void = { _ in }
    var onAppleMenuClickChange: () -> Void = {}

    let userName = UserProfile.fullName
    var dismiss: () -> Void = {}

    private var apps: [AppEntry] = AppCatalog.scan()
    /// Apps the user hid (bundle ID, or path for apps without one).
    private var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenApps") ?? [])
    /// Hidden apps are listed (dimmed) while this is on; reset on every opening.
    @Published private(set) var showsHidden = false
    /// Pinned apps and settings (`StartResult.id`), in pinning order.
    private var pinned = UserDefaults.standard.stringArray(forKey: "pinned") ?? []
    private var results: [StartResult] = []
    private var resultKeys: [String] = []
    /// Result indices per visual row, for up/down navigation.
    private var rows: [[Int]] = []
    private let maxSettingResults = 6
    private let maxRecentFiles = 6
    private let maxSearchedFiles = 4
    private let maxShortcutResults = 4

    init() {
        let saved = UserDefaults.standard.string(forKey: "sortMode").flatMap(SortMode.init(rawValue:))
        sortMode = saved ?? .alphabetical
        style = UserDefaults.standard.string(forKey: "style").flatMap(UIStyle.init(rawValue:)) ?? .glass
        layout = UserDefaults.standard.string(forKey: "layout").flatMap(AppLayout.init(rawValue:)) ?? .grid
        updateResults()
        avatar = UserProfile.loadAvatar()
        IconCache.shared.preload(apps.map(\.url))
        HoverRegistry.shared.onChange = { [weak self] in self?.updateHoverFrames($0) }
        RunningApps.shared.onChange = { [weak self] in self?.runningPaths = RunningApps.shared.paths }
        UpdateChecker.shared.onChange = { [weak self] in self?.availableUpdate = UpdateChecker.shared.availableVersion }
        RecentFiles.shared.onChange = { [weak self] in self?.refreshResults() }
        ShortcutCatalog.shared.onChange = { [weak self] in self?.refreshResults() }
        RecentFiles.shared.refresh()
        ShortcutCatalog.shared.refresh()
    }

    var isSearching: Bool { !normalizedQuery.isEmpty }
    var resultCount: Int { results.count }
    var highlightedIndex: Int? { showsSelection && !results.isEmpty ? selection : nil }

    private var normalizedQuery: String {
        Search.normalize(query.trimmingCharacters(in: .whitespaces))
    }

    func prepareForShow() {
        endPinDrag()
        query = ""
        navigatesResults = false
        selection = 0
        showsSelection = false
        hoveredID = nil
        tooltipTask?.cancel()
        tooltip = nil
        pendingUninstall = nil
        pendingRename = nil
        forceQuitApps = nil
        onboarding = nil
        opensAtLogin = LoginItem.isEnabled
        hidesDock = Dock.isHidden
        showsHidden = false
        updateResults() // usage may have changed since last time
        RecentFiles.shared.refresh()
        ShortcutCatalog.shared.refresh()
        // Screenshots: `STARTMENU_DEMO_QUERY` opens the menu with a search.
        if let demoQuery = ProcessInfo.processInfo.environment["STARTMENU_DEMO_QUERY"] { query = demoQuery }
        if ProcessInfo.processInfo.environment["STARTMENU_DEMO_FORCEQUIT"] == "1" { showForceQuit() }
        showToken = UUID()
        // Pick up apps installed or removed since last time.
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = AppCatalog.scan()
            DispatchQueue.main.async {
                guard scanned.map(\.path) != self.apps.map(\.path) else { return }
                IconCache.shared.preload(scanned.map(\.url))
                self.apps = scanned
                self.updateResults()
            }
        }
    }

    // MARK: - Results

    private func updateResults() {
        let q = normalizedQuery
        var groups: [(title: String, style: SectionStyle, items: [StartResult])]
        let pinnedItems = q.isEmpty ? pinnedResults : []
        let appStyle: SectionStyle = layout == .grid ? .tiles : .rows

        if q.isEmpty {
            let recent = showsRecentFiles ? RecentFiles.shared.files.prefix(maxRecentFiles).map(StartResult.file) : []
            groups = [(L("Pinned"), appStyle, pinnedItems), (L("Recent files"), .twoColumns, recent)]
                + browseGroups().map { ($0.title, appStyle, $0.apps.map(StartResult.app)) }
            showsSelection = false
        } else {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            let calculation = Calculator.evaluate(trimmed).map { [StartResult.calculation($0)] } ?? []
            let matchedApps = Self.ranked(visibleApps, name: \.name) { Search.score(q, $0.key) }
            let matchedFolders = Self.ranked(FolderCatalog.all, name: \.name) { $0.score(q) }.prefix(4)
            let matchedSettings = Self.ranked(SettingsCatalog.all, name: \.name) { $0.score(q) }
                .prefix(maxSettingResults)
            let matchedShortcuts = Self.ranked(ShortcutCatalog.shared.all, name: \.name) { Search.score(q, $0.key) }
                .prefix(maxShortcutResults)
            // Files keep their recency order: names are too varied to rank well.
            let matchedFiles = RecentFiles.shared.files
                .filter { Search.score(q, $0.key, fuzzy: false) != nil }
                .prefix(maxSearchedFiles)
            groups = [
                (L("Calculator"), .rows, calculation),
                (L("Apps"), appStyle, matchedApps.map(StartResult.app)),
                (L("Folders"), .rows, matchedFolders.map(StartResult.folder)),
                (L("Settings"), .rows, matchedSettings.map(StartResult.setting)),
                (L("Shortcuts"), .rows, matchedShortcuts.map(StartResult.shortcut)),
                (L("Recent files"), .rows, matchedFiles.map(StartResult.file)),
                (L("Search"), .rows, [.fileSearch(trimmed), .webSearch(trimmed)]),
            ]
            showsSelection = true
        }

        var newSections: [ResultSection] = []
        var newRows: [[Int]] = []
        var index = 0
        for group in groups where !group.items.isEmpty {
            var section = ResultSection(title: group.title, style: group.style, items: group.items, startIndex: index)
            if newSections.isEmpty && !pinnedItems.isEmpty { section.keyPrefix = "pinned/" }
            newSections.append(section)
            let indices = Array(index..<index + group.items.count)
            let columns = group.style.columns
            newRows += stride(from: 0, to: indices.count, by: columns).map {
                Array(indices[$0..<min($0 + columns, indices.count)])
            }
            index += group.items.count
        }
        sections = newSections
        results = newSections.flatMap(\.items)
        resultKeys = newSections.flatMap { section in section.items.map(section.key) }
        rows = newRows
        selection = 0
    }

    /// Rebuilds the results without losing the keyboard selection (data
    /// arriving in the background, pins, hidden apps).
    private func refreshResults() {
        let keptSelection = selection
        let keptShowsSelection = showsSelection
        updateResults()
        showsSelection = keptShowsSelection
        selection = min(keptSelection, max(resultCount - 1, 0))
    }

    /// The app list shown when not searching, per sort mode.
    private func browseGroups() -> [(title: String, apps: [AppEntry])] {
        let apps = visibleApps
        let usage = UsageStore.shared
        switch sortMode {
        case .alphabetical:
            return [(L("All apps"), apps)]

        case .mostUsed:
            let sorted = apps.sorted {
                let (a, b) = (usage.useCount($0), usage.useCount($1))
                return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return [(L("Most used"), sorted)]

        case .recent:
            let calendar = Calendar.current
            let now = Date()
            let buckets: [(String, (Date) -> Bool)] = [
                (L("Today"), { calendar.isDateInToday($0) }),
                (L("This week"), { now.timeIntervalSince($0) < 7 * 86_400 }),
                (L("This month"), { now.timeIntervalSince($0) < 31 * 86_400 }),
                (L("Earlier"), { _ in true }),
            ]
            let dated = apps.compactMap { app in usage.lastUsed(app).map { (app, $0) } }
                .sorted { $0.1 > $1.1 }
            var groups: [(String, [AppEntry])] = buckets.map { ($0.0, []) }
            for (app, date) in dated {
                let bucket = buckets.firstIndex { $0.1(date) }!
                groups[bucket].1.append(app)
            }
            let undated = apps.filter { usage.lastUsed($0) == nil }
            return groups + [(L("Not opened recently"), undated)]

        case .categories:
            let grouped = Dictionary(grouping: apps, by: \.category)
            return grouped.keys.sorted().map { ($0.title, grouped[$0]!) }
        }
    }

    /// Matching items, best score first, then alphabetically.
    private static func ranked<T>(_ items: [T], name: KeyPath<T, String>, score: (T) -> Int?) -> [T] {
        var scored: [(item: T, score: Int)] = []
        for item in items {
            if let value = score(item) { scored.append((item, value)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item[keyPath: name] < rhs.item[keyPath: name]
        }
        return scored.map(\.item)
    }

    // MARK: - Pinned

    /// Pinned items still installed (and not hidden), in pinning order.
    private var pinnedResults: [StartResult] {
        var byID: [String: StartResult] = [:]
        for app in visibleApps { byID[StartResult.app(app).id] = .app(app) }
        for setting in SettingsCatalog.all { byID[StartResult.setting(setting).id] = .setting(setting) }
        for folder in FolderCatalog.all { byID[StartResult.folder(folder).id] = .folder(folder) }
        for shortcut in ShortcutCatalog.shared.all { byID[StartResult.shortcut(shortcut).id] = .shortcut(shortcut) }
        return pinned.compactMap { id in
            if let result = byID[id] { return result }
            // Files and folders dropped on the menu. Their existence isn't
            // checked: that would ask for access to Documents, Desktop…
            if id.hasPrefix("file:") {
                return .file(FileEntry(url: URL(fileURLWithPath: String(id.dropFirst(5)))))
            }
            if id.hasPrefix("folder:") {
                let url = URL(fileURLWithPath: String(id.dropFirst(7)))
                let name = FileManager.default.displayName(atPath: url.path)
                return .folder(FolderEntry(url: url, name: name, keywords: []))
            }
            return nil
        }
    }

    func isPinned(_ result: StartResult) -> Bool { pinned.contains(result.id) }

    func togglePinned(_ result: StartResult) {
        if let index = pinned.firstIndex(of: result.id) { pinned.remove(at: index) } else { pinned.append(result.id) }
        savePinned()
    }

    private func savePinned() {
        UserDefaults.standard.set(pinned, forKey: "pinned")
        refreshResults()
    }

    // MARK: - Finder drops

    /// Files, folders and apps dropped from the Finder are pinned at the end.
    func dropFromFinder(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            handled = true
            _ = provider.loadObject(ofClass: NSURL.self) { [weak self] url, _ in
                guard let url = url as? URL else { return }
                DispatchQueue.main.async {
                    guard let self, let id = self.resultID(forDropped: url), !self.pinned.contains(id) else { return }
                    self.pinned.append(id)
                    self.savePinned()
                }
            }
        }
        return handled
    }

    private func resultID(forDropped url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().path
        if let app = apps.first(where: { $0.path == resolved }) { return StartResult.app(app).id }
        if let folder = FolderCatalog.all.first(where: { $0.url.path == path }) { return StartResult.folder(folder).id }
        let isDirectory = url.hasDirectoryPath
            || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        return isDirectory && url.pathExtension.isEmpty ? "folder:\(path)" : "file:\(path)"
    }

    // MARK: - Reordering pins

    /// A pin dragged by hand (no AppKit drag session: its end animation
    /// lagged and a second drag fell back to a plain one). Its tile is hidden
    /// and a copy follows the mouse; the pins reorder live as it passes them.
    struct PinDrag {
        let result: StartResult
        /// Mouse position, and its offset in the tile, in `HoverSpace`.
        var location: CGPoint
        let grabOffset: CGSize
        let size: CGSize
        var origin: CGPoint { CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height) }
    }

    @Published private(set) var pinDrag: PinDrag?
    private var pinsMovedByDrag = false
    /// Frames still show the order before the last move: hit-testing them
    /// would send the pin back.
    private var awaitingPinLayout = false

    func dragPin(_ result: StartResult, key: String, start: CGPoint, location: CGPoint) {
        if pinDrag == nil {
            guard let frame = hoverFrames[HoverSpace.resultID(key)] else { return }
            pinDrag = PinDrag(result: result, location: location,
                              grabOffset: CGSize(width: start.x - frame.minX, height: start.y - frame.minY),
                              size: frame.size)
            mouseMoved(to: nil)  // no hover highlight during the drag
        }
        pinDrag?.location = location
        guard !awaitingPinLayout, let section = sections.first, section.isPinned,
              let target = section.items.first(where: {
                  $0.id != result.id && hoverFrames[HoverSpace.resultID(section.key(for: $0))]?.contains(location) == true
              }) else { return }
        withAnimation(.snappy(duration: 0.2)) { moveDraggedPin(result.id, to: target.id, in: section) }
    }

    /// Moving forward lands after the target, backward before it.
    private func moveDraggedPin(_ id: String, to targetID: String, in old: ResultSection) {
        guard let from = pinned.firstIndex(of: id), let to = pinned.firstIndex(of: targetID),
              let itemFrom = old.items.firstIndex(where: { $0.id == id }),
              let itemTo = old.items.firstIndex(where: { $0.id == targetID }) else { return }
        pinned.insert(pinned.remove(at: from), at: to)
        pinsMovedByDrag = true
        awaitingPinLayout = true
        // Only the pinned section changes; saved once, when the drag ends.
        var items = old.items
        items.insert(items.remove(at: itemFrom), at: itemTo)
        var section = ResultSection(title: old.title, style: old.style, items: items, startIndex: old.startIndex)
        section.keyPrefix = old.keyPrefix
        sections[0] = section
        results.replaceSubrange(0..<items.count, with: items)
        resultKeys.replaceSubrange(0..<items.count, with: items.map(section.key))
    }

    func endPinDrag() {
        guard pinDrag != nil else { return }
        pinDrag = nil
        awaitingPinLayout = false
        if pinsMovedByDrag { UserDefaults.standard.set(pinned, forKey: "pinned") }
        pinsMovedByDrag = false
    }

    // MARK: - Custom names

    private var customNames = UserDefaults.standard.dictionary(forKey: "customAppNames") as? [String: String] ?? [:]
    /// The app being renamed, with its displayed name (asked inside the panel).
    @Published private(set) var pendingRename: AppEntry?

    private func customNameKey(_ app: AppEntry) -> String { app.bundleID ?? app.path }

    /// Renamed apps answer to both names in searches, and sort by the new one.
    private func withCustomNames(_ list: [AppEntry]) -> [AppEntry] {
        guard !customNames.isEmpty else { return list }
        return list.map { app in
            guard let custom = customNames[customNameKey(app)] else { return app }
            var renamed = app
            renamed.name = custom
            renamed.key = SearchKey(custom + " " + app.name)
            return renamed
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func originalName(of app: AppEntry) -> String {
        apps.first { $0.path == app.path }?.name ?? app.name
    }

    func hasCustomName(_ app: AppEntry) -> Bool { customNames[customNameKey(app)] != nil }

    func rename(_ app: AppEntry) {
        pendingRename = app
        refreshHover()
    }

    func cancelRename() {
        pendingRename = nil
        refreshHover()
    }

    /// An empty name, or the original one, removes the custom name.
    func commitRename(_ name: String) {
        guard let app = pendingRename else { return }
        pendingRename = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = customNameKey(app)
        if trimmed.isEmpty || trimmed == originalName(of: app) { customNames[key] = nil } else { customNames[key] = trimmed }
        UserDefaults.standard.set(customNames, forKey: "customAppNames")
        refreshResults()
        refreshHover()
    }

    // MARK: - Hidden apps

    private var visibleApps: [AppEntry] {
        withCustomNames(showsHidden ? apps : apps.filter { !isHidden($0) })
    }

    var hiddenCount: Int { apps.filter(isHidden).count }

    func isHidden(_ app: AppEntry) -> Bool {
        hidden.contains(app.bundleID ?? app.path)
    }

    func setHidden(_ app: AppEntry, _ isHidden: Bool) {
        let key = app.bundleID ?? app.path
        if isHidden { hidden.insert(key) } else { hidden.remove(key) }
        UserDefaults.standard.set(hidden.sorted(), forKey: "hiddenApps")
        if hiddenCount == 0 { showsHidden = false }
        refreshResults()
    }

    func toggleShowsHidden() {
        showsHidden.toggle()
        updateResults()
    }

    // MARK: - Hover

    struct Tooltip: Equatable {
        let text: String
        let shortcut: String?
        let anchor: CGRect
    }

    /// Shown after a short delay on the bottom bar buttons and the sort button.
    @Published private(set) var tooltip: Tooltip?
    private var tooltipTask: DispatchWorkItem?

    private func tooltipText(for id: String?) -> (text: String, shortcut: String?)? {
        guard let id else { return nil }
        if id == HoverSpace.userID { return (L("Users & Groups"), nil) }
        if id == HoverSpace.sortID { return (L("Sort and view"), nil) }
        if id == HoverSpace.settingsID { return (L("Start Menu Settings"), nil) }
        return SystemAction.allCases.first { HoverSpace.actionID($0) == id }.map { ($0.title, $0.shortcut) }
    }

    private func updateTooltip() {
        tooltipTask?.cancel()
        guard let id = hoveredID, let content = tooltipText(for: id), let anchor = hoverFrames[id] else {
            tooltip = nil
            return
        }
        // Moving between buttons keeps the tooltip up, like macOS.
        if tooltip != nil {
            tooltip = Tooltip(text: content.text, shortcut: content.shortcut, anchor: anchor)
            return
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredID == id else { return }
            self.tooltip = Tooltip(text: content.text, shortcut: content.shortcut, anchor: anchor)
        }
        tooltipTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func mouseMoved(to point: CGPoint?) {
        mouseLocation = point
        refreshHover()
    }

    /// Frames change on scroll and on new results, under a still mouse too.
    func updateHoverFrames(_ frames: [String: CGRect]) {
        hoverFrames = frames
        awaitingPinLayout = false
        refreshHover()
    }

    private func refreshHover() {
        var hit: String?
        if let point = mouseLocation, pendingUninstall == nil, pendingRename == nil, forceQuitApps == nil,
           onboarding == nil {
            let under = hoverFrames.filter { $0.value.contains(point) }.map(\.key)
            let overBar = under.contains { $0.hasPrefix("block:") }
            hit = under.first { !$0.hasPrefix("block:") && !(overBar && $0.hasPrefix("result:")) }
        }
        if hit != hoveredID {
            hoveredID = hit
            updateTooltip()
        }
    }

    func resultID(at index: Int) -> String? {
        resultKeys.indices.contains(index) ? resultKeys[index] : nil
    }

    // MARK: - Keyboard navigation

    func moveSelection(_ direction: MoveDirection) {
        guard !results.isEmpty else { return }
        if !showsSelection {
            showsSelection = true
            selection = 0
            return
        }
        switch direction {
        case .left: selection = max(selection - 1, 0)
        case .right: selection = min(selection + 1, results.count - 1)
        case .up, .down:
            guard let row = rows.firstIndex(where: { $0.contains(selection) }) else { return }
            let column = rows[row].firstIndex(of: selection)!
            let target = direction == .down ? row + 1 : row - 1
            guard rows.indices.contains(target) else { return }
            selection = rows[target][min(column, rows[target].count - 1)]
        }
    }

    // MARK: - Actions

    func activateSelection() {
        guard !results.isEmpty else { return }
        activate(index: selection)
    }

    func activate(index: Int) {
        guard results.indices.contains(index) else { return }
        dismiss()
        switch results[index] {
        case .app(let app): SystemAction.openApp(url: app.url)
        case .setting(let setting): NSWorkspace.shared.open(setting.url)
        case .folder(let folder): NSWorkspace.shared.open(folder.url)
        case .file(let file): NSWorkspace.shared.open(file.url)
        case .shortcut(let shortcut): shortcut.run()
        case .calculation(let calculation): calculation.copy()
        case .fileSearch(let text): FileSearch.open(text)
        case .webSearch(let text): webSearchEngine.search(text)
        }
    }

    func isRunning(_ app: AppEntry) -> Bool { runningPaths.contains(app.path) }
    func quit(_ app: AppEntry) { RunningApps.shared.quit(app) }
    func forceQuit(_ app: AppEntry) { RunningApps.shared.forceQuit(app) }

    func perform(_ action: SystemAction) {
        if action == .forceQuit {
            showForceQuit()
            return
        }
        dismiss()
        // Let the panel disappear before keyboard-driven actions fire.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { action.perform() }
    }

    /// Asks for confirmation inside the panel.
    func uninstall(_ app: AppEntry) {
        pendingUninstall = AppUninstaller.request(app, installed: apps)
        refreshHover()
    }

    func cancelUninstall() {
        pendingUninstall = nil
        refreshHover()
    }

    func confirmUninstall() {
        guard let request = pendingUninstall else { return }
        pendingUninstall = nil
        guard AppUninstaller.perform(request) else { return }
        apps = AppCatalog.scan()
        updateResults()
    }

    // MARK: - Onboarding and login item

    func requestPermission() {
        CommandKeyMonitor.requestPermission()
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!)
    }

    func toggleOpensAtLogin() {
        LoginItem.setEnabled(!opensAtLogin)
        opensAtLogin = LoginItem.isEnabled
    }

    func toggleHidesDock() {
        Dock.setHidden(!hidesDock)
        hidesDock = Dock.isHidden
    }

    // MARK: - Force Quit

    func showForceQuit() {
        forceQuitSelection = 0
        reloadForceQuitApps()
        refreshHover()
    }

    /// Regular apps (with a Dock icon), like the system Force Quit window.
    private func reloadForceQuitApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        forceQuitApps = apps
        forceQuitSelection = min(forceQuitSelection, max(apps.count - 1, 0))
    }

    func moveForceQuitSelection(by offset: Int) {
        guard let apps = forceQuitApps, !apps.isEmpty else { return }
        forceQuitSelection = min(max(forceQuitSelection + offset, 0), apps.count - 1)
    }

    func selectForceQuit(_ index: Int) {
        forceQuitSelection = index
    }

    func forceQuitSelected() {
        guard let apps = forceQuitApps, apps.indices.contains(forceQuitSelection) else { return }
        apps[forceQuitSelection].forceTerminate()
        // The list stays open, like the system window; the app leaves it once gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard self?.forceQuitApps != nil else { return }
            self?.reloadForceQuitApps()
        }
    }

    func closeForceQuit() {
        forceQuitApps = nil
        refreshHover()
    }

    func openUserSettings() {
        dismiss()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")!)
    }
}
