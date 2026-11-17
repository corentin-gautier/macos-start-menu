import Foundation

/// Groups shown by the "Categories" sort. Cases are in display order.
enum AppCategory: Int, CaseIterable, Comparable {
    case productivity, internet, creativity, music, games, entertainment, information, developer, utilities, other

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .productivity: "Productivity"
        case .internet: "Internet & Social"
        case .creativity: "Creativity"
        case .music: "Music"
        case .games: "Games"
        case .entertainment: "Entertainment"
        case .information: "Information"
        case .developer: "Developer Tools"
        case .utilities: "Utilities"
        case .other: "Other"
        }
    }

    /// Bundle ID rules come first (many apps have no or a misleading
    /// `LSApplicationCategoryType`), then the declared category, then
    /// install location hints.
    static func of(url: URL, bundle: Bundle?) -> AppCategory {
        let bundleID = bundle?.bundleIdentifier?.lowercased() ?? ""
        if let match = bundleIDRules.first(where: { bundleID.hasPrefix($0.0) }) { return match.1 }

        if let declared = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
           let category = declaredCategories[declared.lowercased().replacingOccurrences(of: "public.app-category.", with: "")] {
            return category
        }

        let path = url.path.lowercased()
        if musicFolders.contains(where: { path.contains("/\($0)/") }) { return .music }
        if isSteamShortcut(url) { return .games }
        return .other
    }

    private static let declaredCategories: [String: AppCategory] = [
        "productivity": .productivity, "business": .productivity, "finance": .productivity,
        "social-networking": .internet,
        "graphics-design": .creativity, "photography": .creativity, "video": .creativity,
        "music": .music,
        "games": .games, "board-games": .games, "action-games": .games, "adventure-games": .games,
        "arcade-games": .games, "card-games": .games, "casino-games": .games, "dice-games": .games,
        "educational-games": .games, "family-games": .games, "kids-games": .games, "music-games": .games,
        "puzzle-games": .games, "racing-games": .games, "role-playing-games": .games,
        "simulation-games": .games, "sports-games": .games, "strategy-games": .games,
        "trivia-games": .games, "word-games": .games,
        "entertainment": .entertainment,
        "education": .information, "reference": .information, "books": .information, "news": .information,
        "travel": .information, "healthcare-fitness": .information, "lifestyle": .information,
        "weather": .information, "sports": .information, "medical": .information,
        "developer-tools": .developer,
        "utilities": .utilities,
    ]

    private static let bundleIDRules: [(String, AppCategory)] = [
        // Browsers
        ("com.google.chrome", .internet), ("com.apple.safari", .internet), ("org.mozilla.firefox", .internet),
        ("com.brave.browser", .internet), ("company.thebrowser", .internet), ("com.microsoft.edgemac", .internet),
        ("com.apple.mobilephone", .internet),
        // Music software
        ("com.ableton", .music), ("com.arturia", .music), ("com.focusrite", .music), ("com.spitfireaudio", .music),
        ("com.splice", .music), ("com.xlnaudio", .music), ("com.izotope", .music), ("com.stltones", .music),
        ("com.native-instruments", .music), ("com.apple.logic", .music), ("com.apple.garageband", .music),
        // Games
        ("com.valvesoftware.steam", .games), ("com.mojang", .games), ("com.epicgames", .games),
        // Creative tools
        ("org.blenderfoundation", .creativity), ("com.obsproject", .creativity),
        // Apple apps without a declared category
        ("com.apple.calculator", .utilities), ("com.apple.clock", .utilities), ("com.apple.findmy", .utilities),
        ("com.apple.home", .utilities), ("com.apple.passwords", .utilities), ("com.apple.screencontinuity", .utilities),
        ("com.apple.diskutility", .utilities), ("com.apple.magnifier", .utilities),
        ("com.apple.podcasts", .entertainment), ("com.apple.stocks", .information), ("com.apple.weather", .information),
        ("com.apple.campo", .productivity),
    ]

    private static let musicFolders = ["arturia", "native instruments", "izotope", "spitfire audio", "xln audio"]

    /// Steam game shortcuts are tiny bundles running `run.sh` with a steam:// URL.
    private static func isSteamShortcut(_ url: URL) -> Bool {
        let script = url.appendingPathComponent("Contents/MacOS/run.sh")
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return false }
        return text.contains("steam://")
    }
}
