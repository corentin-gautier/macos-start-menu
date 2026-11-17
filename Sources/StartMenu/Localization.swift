import Foundation

/// Localized string from Resources/<lang>.lproj/Localizable.strings; the key
/// is the English text. SwiftUI literals (`Text("…")`) are looked up there too.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string (`%@`, `%d`).
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
