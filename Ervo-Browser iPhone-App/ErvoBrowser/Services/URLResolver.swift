import Foundation

/// Turns address bar input into a URL: web addresses are opened, everything else is searched.
enum URLResolver {
    private static let hostPattern = #"^(localhost|([\p{L}\p{N}-]+\.)+[\p{L}\p{N}-]{2,}|\d{1,3}(\.\d{1,3}){3})(:\d{1,5})?([/?#].*)?$"#
    private static let passThroughSchemes: Set<String> = ["mailto", "tel", "sms", "facetime", "maps"]

    static func resolve(_ input: String, settings: AppSettings) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let bang = SmartInput.bang(text) { return bang.url }

        if !text.contains(where: { $0.isWhitespace }) {
            if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
                if (scheme == "http" || scheme == "https"), url.host() != nil { return url }
                if passThroughSchemes.contains(scheme) { return url }
                if scheme == "about" && text.lowercased() == "about:blank" { return url }
            }
            if text.range(of: hostPattern, options: .regularExpression) != nil {
                let lower = text.lowercased()
                let isLocal = lower.hasPrefix("localhost") || lower.hasPrefix("127.") || lower.hasPrefix("10.") || lower.hasPrefix("192.168.")
                if let url = URL(string: (isLocal ? "http://" : "https://") + text) { return url }
            }
        }
        return settings.searchURL(for: text)
    }

    /// Short text for the address bar when not editing (host without "www.").
    static func displayHost(_ url: URL?) -> String {
        guard let url else { return "" }
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
