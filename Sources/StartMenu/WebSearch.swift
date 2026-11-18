import AppKit

/// The engine of the "Search the web" result, picked in the settings menu:
/// search engines, then AI assistants that take a question in their URL.
enum WebSearchEngine: String, CaseIterable, Identifiable {
    case google, bing, duckDuckGo, brave, ecosia, startpage, qwant, kagi, yahoo, yandex, baidu, naver
    case perplexity, chatGPT, claude

    var id: String { rawValue }

    static var current: WebSearchEngine {
        get { UserDefaults.standard.string(forKey: "webSearchEngine").flatMap(Self.init(rawValue:)) ?? .google }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "webSearchEngine") }
    }

    static let searchEngines = allCases.filter { !$0.isAssistant }
    static let assistants = allCases.filter(\.isAssistant)

    var isAssistant: Bool {
        switch self {
        case .perplexity, .chatGPT, .claude: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckDuckGo: "DuckDuckGo"
        case .brave: "Brave Search"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .qwant: "Qwant"
        case .kagi: "Kagi"
        case .yahoo: "Yahoo"
        case .yandex: "Yandex"
        case .baidu: "Baidu"
        case .naver: "Naver"
        case .perplexity: "Perplexity"
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }

    /// Search page and the name of its query parameter.
    private var endpoint: (base: String, parameter: String) {
        switch self {
        case .google: ("https://www.google.com/search", "q")
        case .bing: ("https://www.bing.com/search", "q")
        case .duckDuckGo: ("https://duckduckgo.com/", "q")
        case .brave: ("https://search.brave.com/search", "q")
        case .ecosia: ("https://www.ecosia.org/search", "q")
        case .startpage: ("https://www.startpage.com/do/search", "q")
        case .qwant: ("https://www.qwant.com/", "q")
        case .kagi: ("https://kagi.com/search", "q")
        case .yahoo: ("https://search.yahoo.com/search", "p")
        case .yandex: ("https://yandex.com/search/", "text")
        case .baidu: ("https://www.baidu.com/s", "wd")
        case .naver: ("https://search.naver.com/search.naver", "query")
        case .perplexity: ("https://www.perplexity.ai/search", "q")
        case .chatGPT: ("https://chatgpt.com/", "q")
        case .claude: ("https://claude.ai/new", "q")
        }
    }

    func url(for query: String) -> URL? {
        var components = URLComponents(string: endpoint.base)
        components?.queryItems = [URLQueryItem(name: endpoint.parameter, value: query)]
        return components?.url
    }

    func search(_ query: String) {
        if let url = url(for: query) { NSWorkspace.shared.open(url) }
    }
}
