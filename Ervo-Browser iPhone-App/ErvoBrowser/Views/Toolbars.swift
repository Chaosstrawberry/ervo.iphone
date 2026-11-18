import SwiftUI
import WebKit

// MARK: - Address bar

struct AddressBar: View {
    @Environment(BrowserStore.self) private var store
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let tab = store.activeTab
        let isFocused = focused.wrappedValue

        HStack(spacing: 8) {
            Image(systemName: leadingIcon(tab))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(leadingIsWarning(tab) ? Color.orange : Color.secondary)
                .frame(width: 18)

            TextField(L.t("searchOrType"), text: $text)
                .focused(focused)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .multilineTextAlignment(isFocused ? .leading : .center)
                .font(.system(size: 16))
                .onSubmit {
                    let value = text
                    focused.wrappedValue = false
                    store.navigate(value)
                }

            if isFocused {
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.t("cancel"))
                }
            } else if let tab, !tab.isBlank {
                Button {
                    if tab.isLoading { tab.stop() } else { tab.reload() }
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(tab.isLoading ? L.t("stop") : L.t("reload"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .onAppear { syncText() }
        .onChange(of: isFocused) { _, nowFocused in
            if nowFocused {
                text = store.activeTab?.url?.absoluteString ?? ""
                DispatchQueue.main.async {
                    _ = UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                }
            } else {
                syncText()
            }
        }
        .onChange(of: tab?.url) {
            if !focused.wrappedValue { syncText() }
        }
        .onChange(of: tab?.id) {
            if !focused.wrappedValue { syncText() }
        }
    }

    private func syncText() {
        guard let tab = store.activeTab, !tab.isBlank, let url = tab.url ?? tab.pendingURL else {
            text = ""
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            text = URLResolver.displayHost(url)
        } else {
            text = url.absoluteString
        }
    }

    private func leadingIcon(_ tab: TabModel?) -> String {
        guard let tab, !tab.isBlank, let url = tab.url else {
            return store.isPrivateMode ? "eyeglasses" : "magnifyingglass"
        }
        switch url.scheme?.lowercased() {
        case "https": return "lock.fill"
        case "http": return "exclamationmark.triangle.fill"
        default: return "globe"
        }
    }

    private func leadingIsWarning(_ tab: TabModel?) -> Bool {
        guard let tab, !tab.isBlank else { return false }
        return tab.url?.scheme?.lowercased() == "http"
    }
}

// MARK: - iPhone bottom toolbar

struct BottomToolbar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let tab = store.activeTab
        HStack(spacing: 0) {
            ToolbarIcon(systemName: "chevron.backward", label: L.t("back"), enabled: tab?.canGoBack ?? false,
                        history: tab.map { Array($0.webView.backForwardList.backList.reversed().prefix(12)) } ?? [],
                        onHistory: { item in tab?.go(to: item) }) {
                tab?.goBack()
            }
            ToolbarIcon(systemName: "chevron.forward", label: L.t("forward"), enabled: tab?.canGoForward ?? false,
                        history: tab.map { Array($0.webView.backForwardList.forwardList.prefix(12)) } ?? [],
                        onHistory: { item in tab?.go(to: item) }) {
                tab?.goForward()
            }
            ToolbarIcon(systemName: "plus", label: L.t("newTab")) {
                store.openTab()
                store.requestAddressBarFocus()
            }
            TabsButton()
            BrowserMenu {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L.t("menu"))
        }
        .tint(.primary)
        .padding(.horizontal, 8)
        .frame(height: 50)
    }
}

struct ToolbarIcon: View {
    let systemName: String
    let label: String
    var enabled: Bool = true
    /// Long-press list (back/forward history)
    var history: [WKBackForwardListItem] = []
    var onHistory: ((WKBackForwardListItem) -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .contextMenu {
            if let onHistory {
                ForEach(history, id: \.self) { item in
                    Button {
                        onHistory(item)
                    } label: {
                        Text(item.title?.isEmpty == false ? item.title! : (item.url.host() ?? item.url.absoluteString))
                    }
                }
            }
        }
    }
}

struct TabsButton: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Button {
            store.activeTab?.captureSnapshot()
            store.showTabSwitcher = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Text(countText)
                    .font(.system(size: 11, weight: .bold))
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L.t("tabs"))
        .contextMenu {
            Button {
                store.openTab(isPrivate: false)
            } label: {
                Label(L.t("newTab"), systemImage: "plus.square")
            }
            Button {
                store.openTab(isPrivate: true)
            } label: {
                Label(L.t("newPrivateTab"), systemImage: "eyeglasses")
            }
            if let tab = store.activeTab {
                Button(role: .destructive) {
                    store.closeTab(tab)
                } label: {
                    Label(L.t("closeTab"), systemImage: "xmark")
                }
            }
        }
    }

    private var countText: String {
        let count = store.currentTabs.count
        return count > 99 ? "∞" : "\(count)"
    }
}

// MARK: - Main menu

struct BrowserMenu<MenuLabel: View>: View {
    @Environment(BrowserStore.self) private var store
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Button {
                store.openTab(isPrivate: false)
                store.requestAddressBarFocus()
            } label: {
                Label(L.t("newTab"), systemImage: "plus.square")
            }
            Button {
                store.openTab(isPrivate: true)
                store.requestAddressBarFocus()
            } label: {
                Label(L.t("newPrivateTab"), systemImage: "eyeglasses")
            }

            if let tab = store.activeTab, let url = tab.url, !tab.isBlank {
                Divider()
                Button {
                    store.toggleBookmark(for: tab)
                } label: {
                    if store.isBookmarked(url) {
                        Label(L.t("removeBookmark"), systemImage: "star.slash")
                    } else {
                        Label(L.t("addBookmark"), systemImage: "star")
                    }
                }
                ShareLink(item: url) {
                    Label(L.t("share"), systemImage: "square.and.arrow.up")
                }
                Button {
                    tab.webView.findInteraction?.presentFindNavigator(showingReplace: false)
                } label: {
                    Label(L.t("findInPage"), systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    tab.toggleDesktopMode()
                } label: {
                    if tab.isEffectivelyDesktop {
                        Label(L.t("requestMobile"), systemImage: "iphone")
                    } else {
                        Label(L.t("requestDesktop"), systemImage: "desktopcomputer")
                    }
                }
                if store.settings.adblock {
                    Button {
                        store.toggleAdblock(for: url)
                    } label: {
                        if store.settings.isWhitelisted(url) {
                            Label(L.t("adblockOnSite"), systemImage: "shield.slash")
                        } else {
                            Label(L.t("adblockOnSite"), systemImage: "checkmark.shield")
                        }
                    }
                }
            }

            ControlGroup {
                Button {
                    store.changeTextZoom(larger: false)
                } label: {
                    Label(L.t("smaller"), systemImage: "textformat.size.smaller")
                }
                Button {
                    store.settings.textZoom = 100
                } label: {
                    Text("\(store.settings.clampedTextZoom) %")
                }
                Button {
                    store.changeTextZoom(larger: true)
                } label: {
                    Label(L.t("larger"), systemImage: "textformat.size.larger")
                }
            } label: {
                Label(L.t("textSize"), systemImage: "textformat.size")
            }

            Divider()
            Button { store.sheet = .bookmarks } label: { Label(L.t("bookmarks"), systemImage: "book") }
            Button { store.sheet = .history } label: { Label(L.t("history"), systemImage: "clock.arrow.circlepath") }
            Button { store.sheet = .downloads } label: { Label(L.t("downloads"), systemImage: "arrow.down.circle") }
            Divider()
            Button { store.sheet = .settings } label: { Label(L.t("settings"), systemImage: "gearshape") }
        } label: {
            label()
        }
    }
}

// MARK: - Suggestions

struct SuggestionsList: View {
    @Environment(BrowserStore.self) private var store
    let text: String
    let onSelect: (Suggestion) -> Void

    var body: some View {
        let items = store.suggestions(for: text)
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: item))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title(for: item))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                if item.kind == .calc {
                                    Text("\(item.text) · \(L.t("tapToCopy"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if item.kind != .search {
                                    Text(item.text.replacingOccurrences(of: "https://", with: ""))
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private func icon(for item: Suggestion) -> String {
        switch item.kind {
        case .search: return "magnifyingglass"
        case .bookmark: return "star"
        case .history: return "clock"
        case .calc: return "equal.circle"
        case .bang: return "magnifyingglass.circle"
        }
    }

    private func title(for item: Suggestion) -> String {
        switch item.kind {
        case .search: return L.f("searchSuggestion", item.title, store.settings.searchEngineName)
        case .bookmark, .history: return item.title.isEmpty ? item.text : item.title
        case .calc: return "= \(item.title)"
        case .bang: return item.title
        }
    }
}

// MARK: - iPad

struct PadTabStrip: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.currentTabs) { tab in
                        PadTab(tab: tab, active: tab.id == store.activeTab?.id)
                    }
                }
                .padding(.horizontal, 10)
            }
            Button {
                store.openTab()
                store.requestAddressBarFocus()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 32)
            }
            .keyboardShortcut("t", modifiers: .command)
            .accessibilityLabel(L.t("newTab"))
            .padding(.trailing, 10)
        }
        .tint(.primary)
        .frame(height: 44)
        .background(Color(.secondarySystemBackground))
    }
}

struct PadTab: View {
    @Environment(BrowserStore.self) private var store
    let tab: TabModel
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            if tab.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                FaviconView(url: tab.url, size: 16)
            }
            Text(tab.displayTitle)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                store.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(L.t("closeTab"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 210, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color(.systemBackground) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.select(tab) }
    }
}

struct PadToolbar: View {
    @Environment(BrowserStore.self) private var store
    @Binding var addressText: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let tab = store.activeTab
        HStack(spacing: 2) {
            Button { tab?.goBack() } label: { Image(systemName: "chevron.backward").frame(width: 40, height: 40) }
                .disabled(!(tab?.canGoBack ?? false))
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel(L.t("back"))
            Button { tab?.goForward() } label: { Image(systemName: "chevron.forward").frame(width: 40, height: 40) }
                .disabled(!(tab?.canGoForward ?? false))
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityLabel(L.t("forward"))
            Button { tab?.reload() } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 40) }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(L.t("reload"))

            AddressBar(text: $addressText, focused: focused)
                .frame(maxWidth: 820)
                .padding(.horizontal, 8)

            Button {
                store.toggleBookmark(for: tab)
            } label: {
                Image(systemName: store.isBookmarked(tab?.url) ? "star.fill" : "star")
                    .frame(width: 40, height: 40)
            }
            .disabled(tab?.url == nil || (tab?.isBlank ?? true))
            .keyboardShortcut("d", modifiers: .command)
            .accessibilityLabel(L.t("addBookmark"))

            TabsButton().frame(width: 44)
            BrowserMenu {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(L.t("menu"))
        }
        .font(.system(size: 18, weight: .medium))
        .tint(.primary)
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(.bar)
    }
}

// MARK: - Favicon

struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 16

    var body: some View {
        if let iconURL = faviconURL {
            AsyncImage(url: iconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    fallback
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            fallback.frame(width: size, height: size)
        }
    }

    private var faviconURL: URL? {
        guard let url, let scheme = url.scheme, scheme == "https" || scheme == "http", let host = url.host() else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}
