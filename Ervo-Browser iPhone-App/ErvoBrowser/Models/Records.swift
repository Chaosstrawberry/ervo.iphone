import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var url: URL
    var created: Date

    init(title: String, url: URL) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.created = Date()
    }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var url: URL
    var date: Date

    init(title: String, url: URL, date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.date = date
    }
}

/// Open (non-private) tabs, saved for "restore tabs on launch".
struct SavedSession: Codable {
    var urls: [URL]
    var activeIndex: Int
}

struct Suggestion: Identifiable, Hashable {
    enum Kind: Hashable { case search, bookmark, history, calc, bang }
    let id = UUID()
    let kind: Kind
    let title: String
    let url: URL?
    let text: String
}

/// A tile on the start page.
struct SiteItem: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: URL { url }
}
