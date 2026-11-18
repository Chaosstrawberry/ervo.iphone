import SwiftUI
import WebKit
import Observation

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum SheetKind: String, Identifiable {
    case settings, bookmarks, history, downloads
    var id: String { rawValue }
}

/// App state: tabs, settings, bookmarks, history, downloads.
@MainActor
@Observable
final class BrowserStore {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            Persistence.save(settings, to: Files.settings)
            if settings.adblock != oldValue.adblock || settings.adblockWhitelist != oldValue.adblockWhitelist {
                reapplyContentRules()
            }
            if settings.textZoom != oldValue.textZoom {
                applyTextZoom()
            }
        }
    }
    private(set) var tabs: [TabModel] = []
    private(set) var privateTabs: [TabModel] = []
    var activeTabID: UUID? = nil
    var isPrivateMode = false
    var bookmarks: [Bookmark] {
        didSet { Persistence.save(bookmarks, to: Files.bookmarks) }
    }
    private(set) var history: [HistoryEntry]
    private(set) var downloads: [URL] = []
    private(set) var dialogQueue: [JSDialog] = []
    var toast: String? = nil
    var showTabSwitcher = false
    var sheet: SheetKind? = nil
    var shareItem: ShareItem? = nil
    /// Incremented to ask the address bar to take keyboard focus.
    var focusAddressBarRequest = 0

    @ObservationIgnored private var privateDataStore = WKWebsiteDataStore.nonPersistent()
    @ObservationIgnored private var historySaveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var toastTask: Task<Void, Never>? = nil

    private enum Files {
        static let settings = "settings.json"
        static let bookmarks = "bookmarks.json"
        static let history = "history.json"
        static let session = "session.json"
    }

    static let userAgentSuffix: String = {
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let version = parts.prefix(2).joined(separator: ".")
        return "Version/\(version) Mobile/15E148 Safari/604.1"
    }()

    init() {
        settings = Persistence.load(AppSettings.self, from: Files.settings) ?? AppSettings()
        bookmarks = Persistence.load([Bookmark].self, from: Files.bookmarks) ?? []
        history = Persistence.load([HistoryEntry].self, from: Files.history) ?? []
        DownloadManager.shared.store = self
        restoreSession()
        refreshDownloads()
        Task {
            await ContentBlocker.shared.load()
            self.reapplyContentRules()
        }
    }

    // MARK: - Tabs

    var currentTabs: [TabModel] { isPrivateMode ? privateTabs : tabs }

    var activeTab: TabModel? {
        if let id = activeTabID, let tab = currentTabs.first(where: { $0.id == id }) { return tab }
        return currentTabs.last
    }

    func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? privateDataStore : .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.applicationNameForUserAgent = Self.userAgentSuffix
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        return configuration
    }

    @discardableResult
    func openTab(url: URL? = nil,
                 isPrivate: Bool? = nil,
                 activate: Bool = true,
                 configuration: WKWebViewConfiguration? = nil,
                 after: TabModel? = nil) -> TabModel {
        let priv = isPrivate ?? isPrivateMode
        let tab = TabModel(isPrivate: priv, configuration: configuration ?? makeConfiguration(isPrivate: priv), store: self)
        tab.applyContentRules(for: url)

        var list = priv ? privateTabs : tabs
        if let after, let index = list.firstIndex(where: { $0.id == after.id }) {
            list.insert(tab, at: index + 1)
        } else {
            list.append(tab)
        }
        if priv { privateTabs = list } else { tabs = list }

        if activate {
            activeTab?.captureSnapshot()
            isPrivateMode = priv
            activeTabID = tab.id
        }
        if let url { tab.load(url) }
        saveSession()
        return tab
    }

    func select(_ tab: TabModel) {
        if activeTab?.id != tab.id { activeTab?.captureSnapshot() }
        isPrivateMode = tab.isPrivate
        activeTabID = tab.id
        tab.loadPendingIfNeeded()
        saveSession()
    }

    func closeTab(_ tab: TabModel) {
        let wasActive = activeTab?.id == tab.id
        var list = tab.isPrivate ? privateTabs : tabs
        guard let index = list.firstIndex(where: { $0.id == tab.id }) else { return }
        list.remove(at: index)
        tab.tearDown()
        dialogQueue.removeAll { $0.isFinished }

        if tab.isPrivate {
            privateTabs = list
            if list.isEmpty { privateDataStore = .nonPersistent() }
        } else {
            tabs = list
        }

        if wasActive {
            if let next = list.indices.contains(index) ? list[index] : list.last {
                activeTabID = next.id
                next.loadPendingIfNeeded()
            } else if tab.isPrivate {
                isPrivateMode = false
                if let last = tabs.last {
                    activeTabID = last.id
                    last.loadPendingIfNeeded()
                } else {
                    openTab(isPrivate: false)
                }
            } else {
                openTab(isPrivate: false)
            }
        }
        saveSession()
    }

    func closeAll(isPrivate: Bool) {
        let list = isPrivate ? privateTabs : tabs
        list.forEach { $0.tearDown() }
        dialogQueue.removeAll { $0.isFinished }
        if isPrivate {
            privateTabs = []
            privateDataStore = .nonPersistent()
            if isPrivateMode {
                isPrivateMode = false
                if let last = tabs.last { activeTabID = last.id } else { openTab(isPrivate: false) }
            }
        } else {
            tabs = []
            if !isPrivateMode { openTab(isPrivate: false) }
        }
        saveSession()
    }

    /// Loads address bar input in the active tab (or a new one).
    func navigate(_ input: String) {
        guard let url = URLResolver.resolve(input, settings: settings) else { return }
        open(url)
    }

    func open(_ url: URL, newTab: Bool = false) {
        if newTab || activeTab == nil {
            openTab(url: url)
        } else {
            activeTab?.load(url)
        }
    }

    /// Links from other apps: ervobrowser://example.com → https://example.com
    func handleIncoming(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }
        var target: URL? = url
        if scheme == "ervobrowser" || scheme == "ervobrowsers" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            target = components?.url
        }
        guard let target, ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return }
        openTab(url: target, isPrivate: false)
    }

    // MARK: - Ad blocking

    func reapplyContentRules() {
        for tab in tabs + privateTabs {
            tab.applyContentRules(for: tab.url)
        }
    }

    func toggleAdblock(for url: URL?) {
        guard let host = url?.host()?.lowercased() else { return }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let existing = settings.adblockWhitelist.first(where: { bare == $0 || bare.hasSuffix("." + $0) }) {
            settings.adblockWhitelist.removeAll { $0 == existing }
        } else {
            settings.adblockWhitelist.append(bare)
        }
        activeTab?.reload()
    }

    // MARK: - History

    func recordVisit(url: URL, title: String, isPrivate: Bool) {
        guard !isPrivate, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        if let first = history.first, first.url == url {
            history[0].title = title.isEmpty ? first.title : title
            history[0].date = Date()
        } else {
            history.insert(HistoryEntry(title: title, url: url), at: 0)
            if history.count > 3000 { history.removeLast(history.count - 3000) }
        }
        scheduleHistorySave()
    }

    func deleteHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        scheduleHistorySave()
    }

    func clearHistory() {
        history = []
        Persistence.save(history, to: Files.history)
    }

    private func scheduleHistorySave() {
        historySaveTask?.cancel()
        historySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            Persistence.save(self.history, to: Files.history)
        }
    }

    /// Most visited sites (grouped by host) for the start page.
    var topSites: [SiteItem] {
        struct Counter { var title: String; var url: URL; var count: Int }
        var counts: [String: Counter] = [:]
        let hidden = Set(settings.hiddenSites)
        for entry in history.prefix(1500) {
            guard let host = entry.url.host(), let scheme = entry.url.scheme else { continue }
            let key = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if hidden.contains(key) { continue }
            var item = counts[key] ?? Counter(title: key, url: URL(string: "\(scheme)://\(host)/") ?? entry.url, count: 0)
            item.count += 1
            if entry.url.path.isEmpty || entry.url.path == "/", !entry.title.isEmpty { item.title = entry.title }
            counts[key] = item
        }
        return counts.values
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { SiteItem(title: $0.title, url: $0.url) }
    }

    func suggestions(for text: String) -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        var result: [Suggestion] = []
        if let value = SmartInput.calculate(query) {
            result.append(Suggestion(kind: .calc, title: value, url: nil, text: query))
        }
        if let bang = SmartInput.bang(query) {
            result.append(Suggestion(kind: .bang, title: "\(bang.name): \(bang.query)", url: bang.url, text: bang.url.absoluteString))
        } else {
            result.append(Suggestion(kind: .search, title: query, url: nil, text: query))
        }
        var seen = Set<URL>()
        for bookmark in bookmarks where result.count < 7 {
            if "\(bookmark.title) \(bookmark.url.absoluteString)".lowercased().contains(needle), !seen.contains(bookmark.url) {
                seen.insert(bookmark.url)
                result.append(Suggestion(kind: .bookmark, title: bookmark.title, url: bookmark.url, text: bookmark.url.absoluteString))
            }
        }
        for entry in history.prefix(2000) where result.count < 7 {
            if "\(entry.title) \(entry.url.absoluteString)".lowercased().contains(needle), !seen.contains(entry.url) {
                seen.insert(entry.url)
                result.append(Suggestion(kind: .history, title: entry.title, url: entry.url, text: entry.url.absoluteString))
            }
        }
        return result
    }

    func hideSite(_ url: URL) {
        guard let host = url.host() else { return }
        let key = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if !settings.hiddenSites.contains(key) { settings.hiddenSites.append(key) }
    }

    // MARK: - Text size

    static let zoomSteps = [50, 67, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]

    func changeTextZoom(larger: Bool) {
        let current = settings.clampedTextZoom
        if larger {
            settings.textZoom = Self.zoomSteps.first { $0 > current } ?? 300
        } else {
            settings.textZoom = Self.zoomSteps.last { $0 < current } ?? 50
        }
    }

    func applyTextZoom() {
        let factor = CGFloat(settings.clampedTextZoom) / 100
        for tab in tabs + privateTabs {
            tab.webView.pageZoom = factor
        }
    }

    // MARK: - Bookmarks

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(for tab: TabModel?) {
        guard let tab, let url = tab.url else { return }
        if let existing = bookmarks.first(where: { $0.url == url }) {
            bookmarks.removeAll { $0.id == existing.id }
            showToast(L.t("bookmarkRemoved"))
        } else {
            bookmarks.append(Bookmark(title: tab.title.isEmpty ? (url.host() ?? url.absoluteString) : tab.title, url: url))
            showToast(L.t("bookmarkAdded"))
        }
    }

    func renameBookmark(_ bookmark: Bookmark, to title: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { bookmarks[index].title = trimmed }
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    /// Imports a bookmark HTML file (exported from Chrome, Safari, Firefox, Edge …). Returns the number added.
    func importBookmarks(from fileURL: URL) -> Int {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return 0 }
        var existing = Set(bookmarks.map(\.url))
        var added: [Bookmark] = []
        for item in BookmarkHTML.parse(html) where !existing.contains(item.url) {
            existing.insert(item.url)
            added.append(Bookmark(title: item.title, url: item.url))
        }
        if !added.isEmpty { bookmarks.append(contentsOf: added) }
        return added.count
    }

    /// Writes all bookmarks to a temporary HTML file that can be shared / saved to Files.
    func exportBookmarksFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ervo-browser-bookmarks.html")
        do {
            try BookmarkHTML.export(bookmarks).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Downloads

    func refreshDownloads() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Persistence.downloadsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        downloads = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func downloadFinished(_ url: URL?) {
        refreshDownloads()
        showToast(L.f("downloadDone", url?.lastPathComponent ?? ""))
    }

    func deleteDownload(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshDownloads()
    }

    // MARK: - Privacy

    func clearBrowsingData() {
        clearHistory()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { }
        showToast(L.t("cleared"))
    }

    // MARK: - Session

    func saveSession() {
        let saved = tabs.compactMap { tab -> URL? in
            let url = tab.url ?? tab.pendingURL
            guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return url
        }
        let activeURL = tabs.first(where: { $0.id == activeTabID }).flatMap { $0.url ?? $0.pendingURL }
        let activeIndex = activeURL.flatMap { saved.firstIndex(of: $0) } ?? max(0, saved.count - 1)
        Persistence.save(SavedSession(urls: saved, activeIndex: activeIndex), to: Files.session)
    }

    /// Writes everything to disk immediately (called when the app goes to the background).
    func persistAll() {
        historySaveTask?.cancel()
        Persistence.save(history, to: Files.history)
        Persistence.save(bookmarks, to: Files.bookmarks)
        Persistence.save(settings, to: Files.settings)
        saveSession()
    }

    private func restoreSession() {
        if settings.restoreTabs, let session = Persistence.load(SavedSession.self, from: Files.session), !session.urls.isEmpty {
            for url in session.urls {
                let tab = TabModel(isPrivate: false, configuration: makeConfiguration(isPrivate: false), store: self)
                tab.pendingURL = url
                tabs.append(tab)
            }
            let index = min(max(0, session.activeIndex), tabs.count - 1)
            activeTabID = tabs[index].id
            tabs[index].loadPendingIfNeeded()
        } else {
            openTab(isPrivate: false)
        }
    }

    // MARK: - UI helpers

    func presentDialog(_ dialog: JSDialog) {
        dialogQueue.append(dialog)
    }

    func resolveDialog(_ dialog: JSDialog, confirmed: Bool, text: String? = nil) {
        dialog.finish(confirmed: confirmed, text: text)
        dialogQueue.removeAll { $0.id == dialog.id || $0.isFinished }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func requestAddressBarFocus() {
        focusAddressBarRequest += 1
    }
}
