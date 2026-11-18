import SwiftUI

/// ErvoBrowser's start page (shown for blank tabs).
struct NewTabView: View {
    @Environment(BrowserStore.self) private var store
    let isPrivate: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.top, 44)
                    .accessibilityHidden(true)

                Text(isPrivate ? L.t("privateTab") : greeting)
                    .font(.title2.weight(.semibold))

                Button {
                    store.requestAddressBarFocus()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        Text(L.t("searchOrType"))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                if isPrivate {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L.t("privateTitle"), systemImage: "eyeglasses")
                            .font(.headline)
                        Text(L.t("privateText"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 20)
                } else {
                    let favorites = Array(store.bookmarks.prefix(8))
                    if !favorites.isEmpty {
                        tileSection(title: L.t("favorites"), items: favorites.map { SiteItem(title: $0.title, url: $0.url) }, canHide: false)
                    }
                    let sites = store.topSites
                    if !sites.isEmpty {
                        tileSection(title: L.t("mostVisited"), items: sites, canHide: true)
                    }
                }
                Spacer(minLength: 40)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(background.ignoresSafeArea())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return L.t("greetingMorning") }
        if hour < 18 { return L.t("greetingDay") }
        return L.t("greetingEvening")
    }

    private var background: some View {
        LinearGradient(
            colors: [store.settings.accent.color.opacity(isPrivate ? 0.10 : 0.14), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .center
        )
    }

    private func tileSection(title: String, items: [SiteItem], canHide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    Button {
                        store.open(item.url)
                    } label: {
                        VStack(spacing: 8) {
                            FaviconView(url: item.url, size: 26)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            store.open(item.url, newTab: true)
                        } label: {
                            Label(L.t("openInNewTab"), systemImage: "plus.square.on.square")
                        }
                        if canHide {
                            Button(role: .destructive) {
                                withAnimation { store.hideSite(item.url) }
                            } label: {
                                Label(L.t("hide"), systemImage: "eye.slash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
