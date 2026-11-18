import UIKit
import WebKit

/// A JavaScript alert/confirm/prompt waiting for the user.
@MainActor
final class JSDialog: Identifiable {
    enum Kind { case alert, confirm, prompt(defaultText: String) }
    struct Result { let confirmed: Bool; let text: String? }

    let id = UUID()
    let kind: Kind
    let host: String
    let message: String
    private var completion: ((Result) -> Void)?

    init(kind: Kind, host: String, message: String, completion: @escaping (Result) -> Void) {
        self.kind = kind
        self.host = host
        self.message = message
        self.completion = completion
    }

    /// Completes exactly once, further calls are ignored.
    func finish(confirmed: Bool, text: String? = nil) {
        let handler = completion
        completion = nil
        handler?(Result(confirmed: confirmed, text: text))
    }

    var isFinished: Bool { completion == nil }

    var defaultText: String {
        if case let .prompt(text) = kind { return text }
        return ""
    }
}

/// Navigation + UI delegate of one tab.
@MainActor
final class TabDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var tab: TabModel?
    private weak var store: BrowserStore?
    private var dialogs: [JSDialog] = []

    private static let internalSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    init(tab: TabModel, store: BrowserStore) {
        self.tab = tab
        self.store = store
        super.init()
    }

    @objc func handleRefresh(_ sender: UIRefreshControl) {
        tab?.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak sender] in
            sender?.endRefreshing()
        }
    }

    func cancelPendingDialogs() {
        dialogs.forEach { $0.finish(confirmed: false) }
        dialogs.removeAll()
    }

    // MARK: - Navigation policy

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return (.allow, preferences)
        }

        // Links to other apps (mailto:, tel:, maps, App Store, …)
        if !Self.internalSchemes.contains(scheme) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame || navigationAction.navigationType == .linkActivated {
                _ = await UIApplication.shared.open(url)
            }
            return (.cancel, preferences)
        }

        if navigationAction.shouldPerformDownload {
            return (.download, preferences)
        }

        if let tab {
            if navigationAction.targetFrame?.isMainFrame ?? false {
                tab.applyContentRules(for: url)
            }
            preferences.preferredContentMode = tab.contentMode
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType {
            return .download
        }
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    // MARK: - Navigation lifecycle

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.loadError = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.loadError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
        guard let tab, let url = webView.url else { return }
        store?.recordVisit(url: url, title: webView.title ?? "", isPrivate: tab.isPrivate)
        store?.saveSession()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // 102 = frame load interrupted (e.g. the response became a download), 204 = handled by plug-in
        if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204) { return }
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? tab?.url
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed]
        let offline = nsError.domain == NSURLErrorDomain && offlineCodes.contains(nsError.code)
        tab?.loadError = TabModel.LoadError(message: nsError.localizedDescription, failingURL: failingURL, offline: offline)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - Windows

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let store, let tab else { return nil }
        let newTab = store.openTab(isPrivate: tab.isPrivate, configuration: configuration, after: tab)
        return newTab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab { store?.closeTab(tab) }
    }

    // MARK: - JavaScript dialogs

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        _ = await present(.alert, message: message, frame: frame)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await present(.confirm, message: message, frame: frame).confirmed
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let result = await present(.prompt(defaultText: defaultText ?? ""), message: prompt, frame: frame)
        return result.confirmed ? (result.text ?? "") : nil
    }

    private func present(_ kind: JSDialog.Kind, message: String, frame: WKFrameInfo) async -> JSDialog.Result {
        guard let store, let tab, store.activeTab?.id == tab.id else {
            return JSDialog.Result(confirmed: false, text: nil)
        }
        let host = frame.securityOrigin.host
        let result: JSDialog.Result = await withCheckedContinuation { continuation in
            let dialog = JSDialog(kind: kind, host: host, message: message) { result in
                continuation.resume(returning: result)
            }
            dialogs.append(dialog)
            store.presentDialog(dialog)
        }
        dialogs.removeAll { $0.isFinished }
        return result
    }

    // MARK: - Link context menu

    func webView(_ webView: WKWebView,
                 contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL, let store, let tab else {
            completionHandler(nil)
            return
        }
        let isPrivate = tab.isPrivate
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIMenuElement] = [
                UIAction(title: L.t("openInNewTab"), image: UIImage(systemName: "plus.square.on.square")) { _ in
                    store.openTab(url: url, isPrivate: isPrivate, activate: true)
                },
                UIAction(title: L.t("openInBackground"), image: UIImage(systemName: "square.on.square")) { _ in
                    store.openTab(url: url, isPrivate: isPrivate, activate: false)
                }
            ]
            if !isPrivate {
                actions.append(UIAction(title: L.t("openInPrivateTab"), image: UIImage(systemName: "eyeglasses")) { _ in
                    store.openTab(url: url, isPrivate: true, activate: true)
                })
            }
            actions.append(UIAction(title: L.t("copyLink"), image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = url
                store.showToast(L.t("linkCopied"))
            })
            actions.append(UIAction(title: L.t("share"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                store.shareItem = ShareItem(url: url)
            })
            return UIMenu(title: url.absoluteString, children: actions)
        }
        completionHandler(configuration)
    }
}

/// Handles WKDownloads independently of tabs (a tab may be closed while downloading).
@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    weak var store: BrowserStore?
    private var destinations: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let url = Persistence.uniqueDownloadURL(for: suggestedFilename)
        destinations[ObjectIdentifier(download)] = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        let url = destinations.removeValue(forKey: ObjectIdentifier(download))
        store?.downloadFinished(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        store?.showToast(L.t("downloadFailed"))
    }
}
