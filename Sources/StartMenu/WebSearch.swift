import AppKit

/// The engine of the "Search the web" result, picked in the sort menu.
enum WebSearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, ecosia

    var id: String { rawValue }

    static var current: WebSearchEngine {
        get { UserDefaults.standard.string(forKey: "webSearchEngine").flatMap(Self.init(rawValue:)) ?? .google }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "webSearchEngine") }
    }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }

    private var base: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        }
    }

    func url(for query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    func search(_ query: String) {
        if let url = url(for: query) { NSWorkspace.shared.open(url) }
    }
}
