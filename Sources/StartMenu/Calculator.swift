import AppKit

/// The result of an arithmetic expression typed in the search field.
struct Calculation: Hashable {
    let value: Double

    /// Shown in the result row (grouped digits, the Mac's decimal separator).
    var display: String { Self.format(value, grouping: true) }
    /// Copied to the clipboard.
    var plain: String { Self.format(value, grouping: false) }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
    }

    private static func format(_ value: Double, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = 10
        if abs(value) >= 1e15 || (value != 0 && abs(value) < 1e-9) {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = 8
        }
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }
}

/// Evaluates what is typed in the search field when it reads as arithmetic:
/// `12*7`, `(3+4)/2`, `2^10`, `85 × 20%`, `20% of 85` (also "de", "von", "of").
/// Both "." and "," are decimal separators. A plain number is not a
/// calculation: the input needs an operator or a percentage.
enum Calculator {
    static func evaluate(_ text: String) -> Calculation? {
        var input = text.trimmingCharacters(in: .whitespaces)
        if input.hasPrefix("=") { input.removeFirst() }
        guard input.contains(where: \.isNumber), let tokens = tokenize(input) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, parser.hasOperator, value.isFinite else {
            return nil
        }
        return Calculation(value: value)
    }

    fileprivate enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close, percent, of
    }

    private static let ofWords: Set<String> = ["of", "de", "von", "del", "di", "из", "の"]

    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if isDigit(c) || ((c == "." || c == ",") && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                while i < chars.count, isDigit(chars[i]) || chars[i] == "." || chars[i] == "," {
                    text.append(chars[i] == "," ? "." : chars[i])
                    i += 1
                }
                guard let value = Double(text) else { return nil }
                tokens.append(.number(value))
            } else if "+-−*/×÷^".contains(c) {
                let normalized: Character = switch c {
                case "−": "-"
                case "×": "*"
                case "÷": "/"
                default: c
                }
                tokens.append(.op(normalized))
                i += 1
            } else if (c == "x" || c == "X"), case .number = tokens.last {
                // "12x7": x between two numbers multiplies.
                tokens.append(.op("*"))
                i += 1
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else if c == "%" {
                tokens.append(.percent); i += 1
            } else if c.isLetter {
                var word = ""
                while i < chars.count, chars[i].isLetter {
                    word.append(chars[i])
                    i += 1
                }
                guard ofWords.contains(word.lowercased()) else { return nil }
                tokens.append(.of)
            } else {
                return nil
            }
        }
        return tokens
    }

    /// Recursive descent: expression > term > power > unary > postfix > primary.
    private struct Parser {
        let tokens: [Token]
        var position = 0
        /// A binary operator or a percentage was used.
        var hasOperator = false

        init(tokens: [Token]) { self.tokens = tokens }

        var isAtEnd: Bool { position == tokens.count }
        private var current: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while case .op(let op) = current, op == "+" || op == "-" {
                position += 1
                guard let rhs = parseTerm() else { return nil }
                hasOperator = true
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while case .op(let op) = current, op == "*" || op == "/" {
                position += 1
                guard let rhs = parsePower() else { return nil }
                hasOperator = true
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if case .op("^") = current {
                position += 1
                guard let exponent = parsePower() else { return nil }
                hasOperator = true
                return pow(base, exponent)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if case .op(let op) = current, op == "-" || op == "+" {
                position += 1
                guard let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePostfix()
        }

        private mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while current == .percent {
                position += 1
                hasOperator = true
                value /= 100
                if current == .of {
                    position += 1
                    guard let base = parseUnary() else { return nil }
                    value *= base
                }
            }
            return value
        }

        private mutating func parsePrimary() -> Double? {
            switch current {
            case .number(let value):
                position += 1
                return value
            case .open:
                position += 1
                guard let value = parseExpression(), current == .close else { return nil }
                position += 1
                return value
            default:
                return nil
            }
        }
    }
}
