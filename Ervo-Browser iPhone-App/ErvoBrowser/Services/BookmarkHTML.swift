import Foundation

/// Netscape bookmark file format (used by every browser for import/export).
enum BookmarkHTML {
    struct Item {
        let title: String
        let url: URL
    }

    static func parse(_ html: String) -> [Item] {
        let pattern = #"<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var items: [Item] = []
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return }
            let href = decode(String(html[hrefRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            let rawTitle = String(html[titleRange]).replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            let title = decode(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(Item(title: title.isEmpty ? href : title, url: url))
        }
        return items
    }

    static func export(_ bookmarks: [Bookmark]) -> String {
        let items = bookmarks.map { bookmark in
            let date = Int(bookmark.created.timeIntervalSince1970)
            return "        <DT><A HREF=\"\(escape(bookmark.url.absoluteString))\" ADD_DATE=\"\(date)\">\(escape(bookmark.title))</A>"
        }.joined(separator: "\n")
        return """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Ervo-Browser</H3>
            <DL><p>
        \(items)
            </DL><p>
        </DL><p>

        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func decode(_ text: String) -> String {
        var result = text
        let named = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = result as NSString
            var output = ""
            var last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = match.range(at: 1).length > 0
                let digits = ns.substring(with: match.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    output += String(Character(scalar))
                } else {
                    output += ns.substring(with: match.range)
                }
                last = match.range.location + match.range.length
            }
            output += ns.substring(from: last)
            result = output
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
