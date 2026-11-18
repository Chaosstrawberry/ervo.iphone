import Foundation

/// Smart address bar helpers (same behaviour as the desktop version): a safe calculator and
/// keyword searches such as "!w Berlin" or "Pizza !maps".
enum SmartInput {
    // MARK: - Keyword searches

    struct Bang {
        let name: String
        let query: String
        let url: URL
    }

    private static func bangTemplate(_ key: String) -> (name: String, template: String)? {
        let de = L.isGerman
        switch key {
        case "w", "wiki": return ("Wikipedia", de ? "https://de.wikipedia.org/w/index.php?search=%s" : "https://en.wikipedia.org/w/index.php?search=%s")
        case "yt": return ("YouTube", "https://www.youtube.com/results?search_query=%s")
        case "gh": return ("GitHub", "https://github.com/search?q=%s")
        case "maps", "map": return ("Maps", "https://maps.apple.com/?q=%s")
        case "so": return ("Stack Overflow", "https://stackoverflow.com/search?q=%s")
        case "tr": return (de ? "Google Übersetzer" : "Google Translate", "https://translate.google.com/?sl=auto&tl=\(de ? "de" : "en")&text=%s&op=translate")
        case "img": return (de ? "Bilder" : "Images", "https://www.google.com/search?tbm=isch&q=%s")
        case "g": return ("Google", "https://www.google.com/search?q=%s")
        case "ddg": return ("DuckDuckGo", "https://duckduckgo.com/?q=%s")
        case "amz": return ("Amazon", de ? "https://www.amazon.de/s?k=%s" : "https://www.amazon.com/s?k=%s")
        case "news": return ("News", "https://news.google.com/search?q=%s")
        default: return nil
        }
    }

    static func bang(_ input: String) -> Bang? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        var key = ""
        if let first = parts.first, first.hasPrefix("!"), first.count > 1 {
            key = String(first.dropFirst()).lowercased()
            parts.removeFirst()
        } else if let last = parts.last, last.hasPrefix("!"), last.count > 1 {
            key = String(last.dropFirst()).lowercased()
            parts.removeLast()
        } else {
            return nil
        }
        guard let def = bangTemplate(key) else { return nil }
        let query = parts.joined(separator: " ")
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))),
              let url = URL(string: def.template.replacingOccurrences(of: "%s", with: encoded)) else { return nil }
        return Bang(name: def.name, query: query, url: url)
    }

    // MARK: - Calculator

    private enum Token: Equatable {
        case number(Double)
        case op(Character)
        case function(String)
    }

    private static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "wurzel": { $0.squareRoot() }, "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) },
        "tan": { Foundation.tan($0) }, "log": { Foundation.log10($0) }, "ln": { Foundation.log($0) }, "abs": { Swift.abs($0) },
        "round": { $0.rounded() }, "floor": { Foundation.floor($0) }, "ceil": { Foundation.ceil($0) }
    ]

    private static func tokenize(_ source: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(source.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." || c == "," {
                var j = i
                var raw = ""
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "," {
                    raw.append(chars[j] == "," ? "." : chars[j])
                    j += 1
                }
                guard raw.filter({ $0 == "." }).count <= 1, let value = Double(raw) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }
            if c.isLetter || c == "π" {
                var j = i
                var word = ""
                while j < chars.count, chars[j].isLetter || chars[j] == "π" {
                    word.append(chars[j])
                    j += 1
                }
                if word == "x" { tokens.append(.op("*")) } else if word == "pi" || word == "π" { tokens.append(.number(Double.pi)) } else if functions[word] != nil { tokens.append(.function(word)) } else { return nil }
                i = j
                continue
            }
            let mapped: Character
            switch c {
            case "×", "·": mapped = "*"
            case "÷", ":": mapped = "/"
            case "−", "–": mapped = "-"
            default: mapped = c
            }
            guard "+-*/^%()".contains(mapped) else { return nil }
            tokens.append(.op(mapped))
            i += 1
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var pos = 0

        mutating func peekOp(_ c: Character) -> Bool {
            if pos < tokens.count, case .op(let o) = tokens[pos], o == c { return true }
            return false
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                if peekOp("+") { pos += 1; guard let r = term() else { return nil }; value += r } else if peekOp("-") { pos += 1; guard let r = term() else { return nil }; value -= r } else { break }
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while true {
                if peekOp("*") { pos += 1; guard let r = unary() else { return nil }; value *= r } else if peekOp("/") { pos += 1; guard let r = unary() else { return nil }; value /= r } else { break }
            }
            return value
        }

        mutating func unary() -> Double? {
            if peekOp("-") { pos += 1; guard let v = unary() else { return nil }; return -v }
            if peekOp("+") { pos += 1; return unary() }
            return power()
        }

        mutating func power() -> Double? {
            guard let base = postfix() else { return nil }
            if peekOp("^") {
                pos += 1
                guard let exponent = unary() else { return nil }
                return Foundation.pow(base, exponent)
            }
            return base
        }

        mutating func postfix() -> Double? {
            guard var value = primary() else { return nil }
            while peekOp("%") { pos += 1; value /= 100 }
            return value
        }

        mutating func primary() -> Double? {
            guard pos < tokens.count else { return nil }
            switch tokens[pos] {
            case .number(let n):
                pos += 1
                return n
            case .function(let name):
                pos += 1
                guard let fn = SmartInput.functions[name] else { return nil }
                if peekOp("(") {
                    pos += 1
                    guard let arg = expression(), peekOp(")") else { return nil }
                    pos += 1
                    return fn(arg)
                }
                guard let arg = unary() else { return nil }
                return fn(arg)
            case .op(let o) where o == "(":
                pos += 1
                guard let v = expression(), peekOp(")") else { return nil }
                pos += 1
                return v
            default:
                return nil
            }
        }
    }

    /// Returns the formatted result for inputs like "12*(3+4)" or "=sqrt(2)", nil for everything else.
    static func calculate(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        let explicit = text.hasPrefix("=")
        if explicit { text.removeFirst() }
        if text.hasSuffix("=") { text.removeLast() }
        guard let tokens = tokenize(text), !tokens.isEmpty else { return nil }
        let hasOperator = tokens.contains { token in
            switch token {
            case .function: return true
            case .op(let o): return o != "(" && o != ")"
            case .number: return false
            }
        }
        if !explicit {
            guard hasOperator, !(tokens.count == 2 && { if case .op = tokens[0] { return true } else { return false } }()) else { return nil }
            if text.range(of: #"^\d{2,4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil { return nil }
            if text.range(of: #"^0\d+[-/]\d+$"#, options: .regularExpression) != nil { return nil }
        }
        var parser = Parser(tokens: tokens)
        guard let value = parser.expression(), parser.pos == tokens.count, value.isFinite else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.locale = Locale(identifier: L.isGerman ? "de_DE" : "en_US")
        return formatter.string(from: NSNumber(value: value))
    }
}
