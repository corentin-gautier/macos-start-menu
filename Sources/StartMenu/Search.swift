import Foundation

/// Precomputed, normalized forms of a name used for matching.
struct SearchKey: Hashable {
    let full: String
    let words: [String]
    let initials: String

    init(_ text: String) {
        full = Search.normalize(text)
        words = Search.splitWords(text).map(Search.normalize)
        initials = String(words.compactMap(\.first))
    }
}

enum Search {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Splits on separators and camelCase boundaries ("TextEdit" -> "Text", "Edit").
    static func splitWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character.isWhitespace || "-_.&+:/()".contains(character) {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Higher is better; nil means no match. `query` must be normalized.
    static func score(_ query: String, _ key: SearchKey, fuzzy: Bool = true) -> Int? {
        guard !query.isEmpty else { return nil }
        let lengthPenalty = min(key.full.count, 60)

        if key.full == query { return 1000 }
        if key.full.hasPrefix(query) { return 900 - lengthPenalty }
        if key.words.contains(where: { $0.hasPrefix(query) }) { return 750 - lengthPenalty }
        if query.count >= 2, key.initials.hasPrefix(query) { return 650 - lengthPenalty }
        if key.full.contains(query) { return 500 - lengthPenalty }
        guard fuzzy, query.count >= 2 else { return nil }

        // Characters of the query appear in order; fewer gaps rank higher.
        var searchFrom = key.full.startIndex
        var previous: String.Index?
        var gaps = 0
        for character in query {
            guard let found = key.full[searchFrom...].firstIndex(of: character) else { return nil }
            if let previous, key.full.index(after: previous) != found { gaps += 1 }
            previous = found
            searchFrom = key.full.index(after: found)
        }
        return max(50, 300 - gaps * 40 - lengthPenalty)
    }
}
