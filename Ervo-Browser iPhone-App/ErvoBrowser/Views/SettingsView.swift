import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section(L.t("appearance")) {
                    Picker(L.t("mode"), selection: $store.settings.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("accent"))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Accent.allCases) { accent in
                                    Button {
                                        store.settings.accent = accent
                                    } label: {
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: 2)
                                                    .padding(-4)
                                                    .opacity(store.settings.accent == accent ? 1 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(accent.title)
                                    .accessibilityAddTraits(store.settings.accent == accent ? .isSelected : [])
                                }
                            }
                            .padding(6)
                        }
                    }
                    .padding(.vertical, 4)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Picker(L.t("addressBar"), selection: $store.settings.addressBarPosition) {
                            ForEach(AddressBarPosition.allCases) { position in
                                Text(position.title).tag(position)
                            }
                        }
                    }
                }

                Section {
                    Picker(L.t("searchEngine"), selection: $store.settings.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.name).tag(engine)
                        }
                    }
                    if store.settings.searchEngine == .custom {
                        TextField(L.t("customEngineURL"), text: $store.settings.customSearchURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text(L.t("search"))
                } footer: {
                    if store.settings.searchEngine == .custom {
                        Text(AppSettings.isValidCustomSearch(store.settings.customSearchURL) ? L.t("customEngineHint") : L.t("customEngineInvalid"))
                    }
                }

                Section(L.t("textSize")) {
                    HStack {
                        Button {
                            store.changeTextZoom(larger: false)
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L.t("smaller"))
                        Spacer()
                        Text("\(store.settings.clampedTextZoom) %")
                            .monospacedDigit()
                        Spacer()
                        Button {
                            store.changeTextZoom(larger: true)
                        } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L.t("larger"))
                    }
                }

                Section {
                    Toggle(isOn: $store.settings.adblock) {
                        Label(L.t("adblock"), systemImage: "checkmark.shield")
                    }
                    NavigationLink {
                        ExceptionsView()
                    } label: {
                        HStack {
                            Text(L.t("exceptions"))
                            Spacer()
                            Text("\(store.settings.adblockWhitelist.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(L.t("adblockDesc"))
                }

                Section(L.t("privacy")) {
                    Toggle(L.t("restoreTabs"), isOn: $store.settings.restoreTabs)
                    Button(L.t("clearData"), role: .destructive) {
                        confirmClear = true
                    }
                }

                Section {
                    Button(L.t("openSettings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text(L.t("defaultBrowser"))
                } footer: {
                    Text(L.t("defaultBrowserDesc"))
                }

                Section(L.t("legal")) {
                    NavigationLink(L.t("about")) { AboutView() }
                    NavigationLink(L.t("privacyPolicy")) { LegalDocumentView(document: .privacy) }
                    NavigationLink(L.t("terms")) { LegalDocumentView(document: .terms) }
                    NavigationLink(L.t("licenses")) { LegalDocumentView(document: .licenses) }
                }
            }
            .navigationTitle(L.t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("done")) { dismiss() }
                }
            }
            .confirmationDialog(L.t("clearData"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L.t("clearNow"), role: .destructive) {
                    store.clearBrowsingData()
                }
                Button(L.t("cancel"), role: .cancel) {}
            } message: {
                Text(L.t("clearDataConfirm"))
            }
        }
    }
}

struct ExceptionsView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        List {
            if store.settings.adblockWhitelist.isEmpty {
                Text(L.t("noExceptions")).foregroundStyle(.secondary)
            }
            ForEach(store.settings.adblockWhitelist, id: \.self) { host in
                Text(host)
            }
            .onDelete { offsets in
                store.settings.adblockWhitelist.remove(atOffsets: offsets)
            }
        }
        .navigationTitle(L.t("exceptions"))
    }
}

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                    Text("Ervo-Browser")
                        .font(.title2.weight(.bold))
                    Text("\(L.t("version")) \(version)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                Text(L.t("engineNote"))
                Text(L.t("notAffiliated"))
                Text("© 2026 Erdgames · Oberösterreich · MIT License")
                Link("Erdgames.net@outlook.com", destination: URL(string: "mailto:Erdgames.net@outlook.com")!)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle(L.t("about"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shows one of the bundled legal documents (generated from /legal/*.md).
struct LegalDocumentView: View {
    enum Document: String {
        case privacy, terms, licenses

        var title: String {
            switch self {
            case .privacy: return L.t("privacyPolicy")
            case .terms: return L.t("terms")
            case .licenses: return L.t("licenses")
            }
        }
    }

    let document: Document

    var body: some View {
        LegalWebView(resource: "legal-\(document.rawValue)")
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalWebView: UIViewRepresentable {
    let resource: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        if let url = Bundle.main.url(forResource: resource, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// External links in legal documents open in the system (ErvoBrowser if it is the default browser).
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, !url.isFileURL {
                _ = await UIApplication.shared.open(url)
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        }
    }
}
