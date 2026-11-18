import SwiftUI

/// Root view: iPhone layout (address bar top or bottom + toolbar) and iPad layout (tab strip + toolbar).
struct BrowserView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var addressFocused: Bool
    @State private var addressText = ""
    @State private var promptText = ""

    private var isCompact: Bool { sizeClass != .regular }
    private var barAtBottom: Bool { isCompact && store.settings.addressBarPosition == .bottom }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if !isCompact {
                PadTabStrip()
                PadToolbar(addressText: $addressText, focused: $addressFocused)
            } else if !barAtBottom {
                AddressBar(text: $addressText, focused: $addressFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
            }

            ZStack(alignment: barAtBottom ? .bottom : .top) {
                pageContent
                LoadingBar()
                    .frame(maxHeight: .infinity, alignment: barAtBottom ? .bottom : .top)
                if addressFocused {
                    SuggestionsList(text: addressText) { suggestion in
                        select(suggestion)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isCompact {
                VStack(spacing: 0) {
                    if barAtBottom {
                        AddressBar(text: $addressText, focused: $addressFocused)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, addressFocused ? 8 : 2)
                    }
                    if !addressFocused {
                        BottomToolbar()
                    }
                }
                .background(.bar)
            }
        }
        .overlay(alignment: barAtBottom ? .top : .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(barAtBottom ? .top : .bottom, 24)
                    .transition(.move(edge: barAtBottom ? .top : .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .animation(.easeInOut(duration: 0.15), value: addressFocused)
        .sheet(item: $store.sheet) { kind in
            sheetContent(kind)
                .environment(store)
                .tint(store.settings.accent.color)
        }
        .sheet(item: $store.shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $store.showTabSwitcher) {
            TabSwitcherView()
                .environment(store)
                .tint(store.settings.accent.color)
        }
        .alert(dialogTitle, isPresented: dialogPresented, presenting: store.dialogQueue.first) { dialog in
            switch dialog.kind {
            case .alert:
                Button(L.t("ok")) { store.resolveDialog(dialog, confirmed: true) }
            case .confirm:
                Button(L.t("cancel"), role: .cancel) { store.resolveDialog(dialog, confirmed: false) }
                Button(L.t("ok")) { store.resolveDialog(dialog, confirmed: true) }
            case .prompt:
                TextField("", text: $promptText)
                Button(L.t("cancel"), role: .cancel) { store.resolveDialog(dialog, confirmed: false) }
                Button(L.t("ok")) { store.resolveDialog(dialog, confirmed: true, text: promptText) }
            }
        } message: { dialog in
            Text(dialog.message)
        }
        .onChange(of: store.dialogQueue.first?.id) {
            promptText = store.dialogQueue.first?.defaultText ?? ""
        }
        .onChange(of: store.focusAddressBarRequest) {
            addressFocused = true
        }
        .sensoryFeedback(.impact(weight: .light), trigger: store.tabs.count + store.privateTabs.count)
        .sensoryFeedback(.success, trigger: store.bookmarks.count)
        .background { keyboardShortcuts }
    }

    // MARK: - Page

    @ViewBuilder
    private var pageContent: some View {
        if let tab = store.activeTab {
            ZStack {
                WebViewContainer(tab: tab)
                    .id(tab.id)
                    .opacity(tab.isBlank ? 0 : 1)
                if tab.isBlank {
                    NewTabView(isPrivate: tab.isPrivate)
                }
                if let error = tab.loadError {
                    ErrorOverlay(error: error) { tab.reload() }
                }
            }
        } else {
            NewTabView(isPrivate: store.isPrivateMode)
        }
    }

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        switch kind {
        case .settings: SettingsView()
        case .bookmarks: BookmarksView()
        case .history: HistoryView()
        case .downloads: DownloadsView()
        }
    }

    // MARK: - Helpers

    private func select(_ suggestion: Suggestion) {
        if suggestion.kind == .calc {
            UIPasteboard.general.string = suggestion.title
            store.showToast(L.f("calcCopied", suggestion.title))
            return
        }
        addressFocused = false
        if let url = suggestion.url {
            store.open(url)
        } else {
            store.navigate(suggestion.text)
        }
    }

    private var dialogTitle: String {
        guard let host = store.dialogQueue.first?.host, !host.isEmpty else { return "" }
        return L.f("jsAlertFrom", host)
    }

    /// Hardware keyboard shortcuts (iPad, iPhone with keyboard). Invisible buttons only carry the shortcut.
    private var keyboardShortcuts: some View {
        Group {
            if isCompact {
                Button("") {
                    store.openTab()
                    store.requestAddressBarFocus()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            Button("") { addressFocused = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("") { if let tab = store.activeTab { store.closeTab(tab) } }
                .keyboardShortcut("w", modifiers: .command)
            Button("") {
                store.openTab(isPrivate: true)
                store.requestAddressBarFocus()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("") { store.activeTab?.webView.findInteraction?.presentFindNavigator(showingReplace: false) }
                .keyboardShortcut("f", modifiers: .command)
            Button("") {
                store.activeTab?.captureSnapshot()
                store.showTabSwitcher = true
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            Button("") { store.changeTextZoom(larger: true) }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { store.changeTextZoom(larger: false) }
                .keyboardShortcut("-", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var dialogPresented: Binding<Bool> {
        Binding(get: { store.dialogQueue.first != nil }, set: { _ in })
    }
}

/// Thin progress bar shown while a page loads.
struct LoadingBar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let tab = store.activeTab
        let visible = (tab?.isLoading ?? false) && !(tab?.isBlank ?? true)
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * max(0.05, tab?.progress ?? 0), height: 2.5)
                .animation(.easeOut(duration: 0.25), value: tab?.progress)
        }
        .frame(height: 2.5)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: visible)
        .allowsHitTesting(false)
    }
}

/// Shown when a page could not be loaded.
struct ErrorOverlay: View {
    let error: TabModel.LoadError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: error.offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(error.offline ? L.t("errorOffline") : L.t("errorTitle"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let host = error.failingURL?.host() {
                Text(host).font(.footnote).foregroundStyle(.tertiary)
            }
            Button(L.t("retry"), action: retry)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
