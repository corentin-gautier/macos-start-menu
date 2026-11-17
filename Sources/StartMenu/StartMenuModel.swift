import AppKit
import Combine

enum StartResult {
    case app(AppEntry)
    case setting(SettingEntry)
}

enum MoveDirection { case left, right, up, down }

final class StartMenuModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { updateResults() } } }
    @Published private(set) var appResults: [AppEntry] = []
    @Published private(set) var settingResults: [SettingEntry] = []
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
    private let maxSettingResults = 6

    init() {
        updateResults()
        avatar = UserProfile.loadAvatar()
    }

    var isSearching: Bool { !normalizedQuery.isEmpty }
    var resultCount: Int { appResults.count + settingResults.count }
    var highlightedIndex: Int? { showsSelection && resultCount > 0 ? selection : nil }

    private var normalizedQuery: String {
        Search.normalize(query.trimmingCharacters(in: .whitespaces))
    }

    func prepareForShow() {
        query = ""
        selection = 0
        showsSelection = false
        hoveredAction = nil
        showToken = UUID()
        // Pick up apps installed or removed since last time.
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = AppCatalog.scan()
            DispatchQueue.main.async {
                guard scanned != self.apps else { return }
                self.apps = scanned
                self.updateResults()
            }
        }
    }

    private func updateResults() {
        let q = normalizedQuery
        if q.isEmpty {
            appResults = apps
            settingResults = []
            showsSelection = false
        } else {
            appResults = Self.ranked(apps, name: \.name) { Search.score(q, $0.key) }
            settingResults = Array(
                Self.ranked(SettingsCatalog.all, name: \.name) { $0.score(q) }.prefix(maxSettingResults)
            )
            showsSelection = true
        }
        selection = 0
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

    func result(at index: Int) -> StartResult? {
        if index < appResults.count { return .app(appResults[index]) }
        let settingIndex = index - appResults.count
        return settingResults.indices.contains(settingIndex) ? .setting(settingResults[settingIndex]) : nil
    }

    // MARK: - Keyboard navigation

    /// Apps are a grid, settings a list below it.
    func moveSelection(_ direction: MoveDirection) {
        guard resultCount > 0 else { return }
        if !showsSelection {
            showsSelection = true
            selection = 0
            return
        }
        let columns = Layout.gridColumns
        let appCount = appResults.count
        var target = selection

        switch direction {
        case .left: target -= 1
        case .right: target += 1
        case .down:
            if selection < appCount {
                let next = selection + columns
                let lastRowStart = (appCount - 1) / columns * columns
                if next < appCount { target = next }
                else if selection >= lastRowStart { target = appCount } // into settings
                else { target = appCount - 1 }
            } else {
                target += 1
            }
        case .up:
            if selection < appCount { target = selection - columns >= 0 ? selection - columns : selection }
            else if selection == appCount, appCount > 0 { target = (appCount - 1) / columns * columns }
            else { target -= 1 }
        }
        selection = min(max(target, 0), resultCount - 1)
    }

    // MARK: - Actions

    func activateSelection() {
        guard resultCount > 0 else { return }
        activate(index: selection)
    }

    func activate(index: Int) {
        guard let result = result(at: index) else { return }
        dismiss()
        switch result {
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
