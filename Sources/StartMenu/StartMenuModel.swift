import AppKit
import Combine

enum StartResult: Identifiable {
    case app(AppEntry)
    case setting(SettingEntry)

    var id: String {
        switch self {
        case .app(let app): "app:\(app.id)"
        case .setting(let setting): "setting:\(setting.id)"
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
        case .alphabetical: "A–Z"
        case .recent: "Recent"
        case .mostUsed: "Most used"
        case .categories: "Categories"
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

enum MoveDirection { case left, right, up, down }

final class StartMenuModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { updateResults() } } }
    @Published var sortMode: SortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode")
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
    @Published var hoveredAction: SystemAction?

    let userName = UserProfile.fullName
    var dismiss: () -> Void = {}

    private var apps: [AppEntry] = AppCatalog.scan()
    private var results: [StartResult] = []
    /// Result indices per visual row, for up/down navigation.
    private var rows: [[Int]] = []
    private let maxSettingResults = 6

    init() {
        let saved = UserDefaults.standard.string(forKey: "sortMode").flatMap(SortMode.init(rawValue:))
        sortMode = saved ?? .alphabetical
        updateResults()
        avatar = UserProfile.loadAvatar()
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
        hoveredAction = nil
        updateResults() // usage may have changed since last time
        showToken = UUID()
        // Pick up apps installed or removed since last time.
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = AppCatalog.scan()
            DispatchQueue.main.async {
                guard scanned.map(\.path) != self.apps.map(\.path) else { return }
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
            groups = browseGroups().map { ($0.title, true, $0.apps.map(StartResult.app)) }
            showsSelection = false
        } else {
            let matchedApps = Self.ranked(apps, name: \.name) { Search.score(q, $0.key) }
            let matchedSettings = Self.ranked(SettingsCatalog.all, name: \.name) { $0.score(q) }
                .prefix(maxSettingResults)
            groups = [
                ("Apps", true, matchedApps.map(StartResult.app)),
                ("Settings", false, matchedSettings.map(StartResult.setting)),
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
        let usage = UsageStore.shared
        switch sortMode {
        case .alphabetical:
            return [("All apps", apps)]

        case .mostUsed:
            let sorted = apps.sorted {
                let (a, b) = (usage.useCount($0), usage.useCount($1))
                return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return [("Most used", sorted)]

        case .recent:
            let calendar = Calendar.current
            let now = Date()
            let buckets: [(String, (Date) -> Bool)] = [
                ("Today", { calendar.isDateInToday($0) }),
                ("This week", { now.timeIntervalSince($0) < 7 * 86_400 }),
                ("This month", { now.timeIntervalSince($0) < 31 * 86_400 }),
                ("Earlier", { _ in true }),
            ]
            let dated = apps.compactMap { app in usage.lastUsed(app).map { (app, $0) } }
                .sorted { $0.1 > $1.1 }
            var groups: [(String, [AppEntry])] = buckets.map { ($0.0, []) }
            for (app, date) in dated {
                let bucket = buckets.firstIndex { $0.1(date) }!
                groups[bucket].1.append(app)
            }
            let undated = apps.filter { usage.lastUsed($0) == nil }
            return groups + [("Not opened recently", undated)]

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
        }
    }

    func perform(_ action: SystemAction) {
        dismiss()
        // Let the panel disappear before keyboard-driven actions fire.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { action.perform() }
    }

    func openUserSettings() {
        dismiss()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")!)
    }
}
