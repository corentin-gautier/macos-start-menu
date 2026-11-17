import AppKit
import Combine

enum StartResult: Identifiable {
    case app(AppEntry)
    case setting(SettingEntry)
    case folder(FolderEntry)

    var id: String {
        switch self {
        case .app(let app): "app:\(app.id)"
        case .setting(let setting): "setting:\(setting.id)"
        case .folder(let folder): "folder:\(folder.id)"
        }
    }
}

/// A titled block of results: apps are shown as a grid, settings as a list.
struct ResultSection: Identifiable {
    let title: String
    let isGrid: Bool
    let items: [StartResult]
    /// Index of the first item in the flat result list.
    let startIndex: Int

    var id: String { title }
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
    @Published var query = "" { didSet { if query != oldValue { updateResults() } } }
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
    @Published private(set) var forceQuitSelection = 0

    let userName = UserProfile.fullName
    var dismiss: () -> Void = {}

    private var apps: [AppEntry] = AppCatalog.scan()
    /// Apps the user hid (bundle ID, or path for apps without one).
    private var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenApps") ?? [])
    /// Hidden apps are listed (dimmed) while this is on; reset on every opening.
    @Published private(set) var showsHidden = false
    private var results: [StartResult] = []
    /// Result indices per visual row, for up/down navigation.
    private var rows: [[Int]] = []
    private let maxSettingResults = 6

    init() {
        let saved = UserDefaults.standard.string(forKey: "sortMode").flatMap(SortMode.init(rawValue:))
        sortMode = saved ?? .alphabetical
        style = UserDefaults.standard.string(forKey: "style").flatMap(UIStyle.init(rawValue:)) ?? .glass
        layout = UserDefaults.standard.string(forKey: "layout").flatMap(AppLayout.init(rawValue:)) ?? .grid
        updateResults()
        avatar = UserProfile.loadAvatar()
        IconCache.shared.preload(apps.map(\.url))
        HoverRegistry.shared.onChange = { [weak self] in self?.updateHoverFrames($0) }
    }

    var isSearching: Bool { !normalizedQuery.isEmpty }
    var resultCount: Int { results.count }
    var highlightedIndex: Int? { showsSelection && !results.isEmpty ? selection : nil }

    private var normalizedQuery: String {
        Search.normalize(query.trimmingCharacters(in: .whitespaces))
    }

    func prepareForShow() {
        query = ""
        selection = 0
        showsSelection = false
        hoveredID = nil
        tooltipTask?.cancel()
        tooltip = nil
        pendingUninstall = nil
        forceQuitApps = nil
        onboarding = nil
        opensAtLogin = LoginItem.isEnabled
        showsHidden = false
        updateResults() // usage may have changed since last time
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
        var groups: [(title: String, isGrid: Bool, items: [StartResult])]

        if q.isEmpty {
            groups = browseGroups().map { ($0.title, layout == .grid, $0.apps.map(StartResult.app)) }
            showsSelection = false
        } else {
            let matchedApps = Self.ranked(visibleApps, name: \.name) { Search.score(q, $0.key) }
            let matchedFolders = Self.ranked(FolderCatalog.all, name: \.name) { $0.score(q) }.prefix(4)
            let matchedSettings = Self.ranked(SettingsCatalog.all, name: \.name) { $0.score(q) }
                .prefix(maxSettingResults)
            groups = [
                (L("Apps"), layout == .grid, matchedApps.map(StartResult.app)),
                (L("Folders"), false, matchedFolders.map(StartResult.folder)),
                (L("Settings"), false, matchedSettings.map(StartResult.setting)),
            ]
            showsSelection = true
        }

        var newSections: [ResultSection] = []
        var newRows: [[Int]] = []
        var index = 0
        for group in groups where !group.items.isEmpty {
            newSections.append(ResultSection(title: group.title, isGrid: group.isGrid, items: group.items, startIndex: index))
            let indices = Array(index..<index + group.items.count)
            if group.isGrid {
                newRows += stride(from: 0, to: indices.count, by: Layout.gridColumns).map {
                    Array(indices[$0..<min($0 + Layout.gridColumns, indices.count)])
                }
            } else {
                newRows += indices.map { [$0] }
            }
            index += group.items.count
        }
        sections = newSections
        results = newSections.flatMap(\.items)
        rows = newRows
        selection = 0
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

    // MARK: - Hidden apps

    private var visibleApps: [AppEntry] {
        showsHidden ? apps : apps.filter { !isHidden($0) }
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
        let keptSelection = selection
        updateResults()
        selection = min(keptSelection, max(resultCount - 1, 0))
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
        if id == HoverSpace.sortID { return (L("Sort, hidden apps and style"), nil) }
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
        refreshHover()
    }

    private func refreshHover() {
        var hit: String?
        if let point = mouseLocation, pendingUninstall == nil, forceQuitApps == nil, onboarding == nil {
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
        results.indices.contains(index) ? results[index].id : nil
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
        }
    }

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
