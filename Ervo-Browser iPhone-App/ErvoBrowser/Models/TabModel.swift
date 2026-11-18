import SwiftUI
import WebKit
import Observation

/// One browser tab. Owns its WKWebView for its whole lifetime.
@MainActor
@Observable
final class TabModel: Identifiable {
    let id = UUID()
    let isPrivate: Bool
    let webView: WKWebView

    var title: String = ""
    var url: URL? = nil
    var progress: Double = 0
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var hasOnlySecureContent = false
    var snapshot: UIImage? = nil
    var loadError: LoadError? = nil
    /// URL restored from the last session; loaded when the tab is first shown.
    var pendingURL: URL? = nil
    var contentMode: WKWebpagePreferences.ContentMode = .recommended

    struct LoadError: Equatable {
        let message: String
        let failingURL: URL?
        let offline: Bool
    }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private(set) var delegate: TabDelegate? = nil
    private let contentController: WKUserContentController
    @ObservationIgnored private weak var store: BrowserStore? = nil

    /// Blank tabs show ErvoBrowser's own start page instead of a web page.
    var isBlank: Bool { url == nil && pendingURL == nil && !isLoading }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = (url ?? pendingURL)?.host() { return host }
        return L.t("newTab")
    }

    var isEffectivelyDesktop: Bool {
        switch contentMode {
        case .desktop: return true
        case .mobile: return false
        default: return UIDevice.current.userInterfaceIdiom == .pad
        }
    }

    init(isPrivate: Bool, configuration: WKWebViewConfiguration, store: BrowserStore) {
        self.isPrivate = isPrivate
        self.store = store
        self.contentController = configuration.userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.pageZoom = CGFloat(store.settings.clampedTextZoom) / 100
        self.webView = webView

        let delegate = TabDelegate(tab: self, store: store)
        self.delegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        let refresh = UIRefreshControl()
        refresh.addTarget(delegate, action: #selector(TabDelegate.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observe()
    }

    private func observe() {
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.title = webView.title ?? "" }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let url = webView.url { self.url = url }
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.hasOnlySecureContent = webView.hasOnlySecureContent }
            }
        ]
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        loadError = nil
        pendingURL = nil
        self.url = url
        applyContentRules(for: url)
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Loads the restored URL the first time the tab becomes visible.
    func loadPendingIfNeeded() {
        if let pending = pendingURL, webView.url == nil {
            load(pending)
        }
    }

    func goBack() { if webView.canGoBack { loadError = nil; webView.goBack() } }

    func go(to item: WKBackForwardListItem) {
        loadError = nil
        webView.go(to: item)
    }
    func goForward() { if webView.canGoForward { loadError = nil; webView.goForward() } }

    func reload() {
        if let error = loadError, let failing = error.failingURL {
            load(failing)
        } else if webView.url == nil, let pending = pendingURL {
            load(pending)
        } else {
            webView.reload()
        }
    }

    func stop() { webView.stopLoading() }

    func toggleDesktopMode() {
        contentMode = isEffectivelyDesktop ? .mobile : .desktop
        if webView.url != nil { webView.reload() }
    }

    // MARK: - Ad blocking

    /// Adds or removes the compiled blocklist for this tab depending on settings and the site's exception.
    func applyContentRules(for url: URL?) {
        guard let store else { return }
        contentController.removeAllContentRuleLists()
        let enabled = store.settings.adblock && !store.settings.isWhitelisted(url)
        if enabled, let rules = ContentBlocker.shared.ruleList {
            contentController.add(rules)
        }
    }

    // MARK: - Snapshot for the tab switcher

    func captureSnapshot() {
        guard !isBlank, webView.bounds.width > 0, webView.window != nil else { return }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            MainActor.assumeIsolated {
                if let image { self?.snapshot = image }
            }
        }
    }

    func tearDown() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        delegate?.cancelPendingDialogs()
        delegate = nil
    }
}
