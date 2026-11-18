import SwiftUI

/// First-run setup: look, search engine, address bar position.
struct OnboardingView: View {
    @Environment(BrowserStore.self) private var store
    @State private var page = 0

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var lastPage: Int { isPhone ? 4 : 3 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < lastPage {
                    Button(L.t("skip")) { finish() }
                        .padding()
                }
            }
            .frame(height: 52)

            TabView(selection: $page) {
                welcome.tag(0)
                look.tag(1)
                search.tag(2)
                if isPhone { bar.tag(3) }
                done.tag(lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page == 0 ? L.t("start") : page == lastPage ? L.t("startBrowsing") : L.t("next"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(colors: [store.settings.accent.color.opacity(0.18), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .interactiveDismissDisabled()
    }

    private func finish() {
        store.settings.onboarded = true
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("Logo").resizable().scaledToFit().frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
            Text(L.t("welcomeTitle")).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text(L.t("welcomeText")).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var look: some View {
        VStack(spacing: 22) {
            Text(L.t("welcomeLook")).font(.title.weight(.bold)).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        store.settings.themeMode = mode
                    } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(previewFill(mode))
                                .frame(height: 90)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(store.settings.themeMode == mode ? store.settings.accent.color : Color(.separator), lineWidth: store.settings.themeMode == mode ? 3 : 1)
                                )
                            Text(mode.title).font(.subheadline.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                ForEach(Accent.allCases) { accent in
                    Button {
                        store.settings.accent = accent
                    } label: {
                        Circle().fill(accent.color).frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.primary, lineWidth: 2).padding(-4).opacity(store.settings.accent == accent ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.title)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
    }

    private func previewFill(_ mode: ThemeMode) -> AnyShapeStyle {
        switch mode {
        case .light: return AnyShapeStyle(Color(white: 0.95))
        case .dark: return AnyShapeStyle(Color(white: 0.13))
        case .system: return AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.95), Color(white: 0.13), Color(white: 0.13)], startPoint: .leading, endPoint: .trailing))
        }
    }

    private var search: some View {
        VStack(spacing: 16) {
            Text(L.t("welcomeSearch")).font(.title.weight(.bold)).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(SearchEngine.allCases.filter { $0 != .custom }) { engine in
                    Button {
                        store.settings.searchEngine = engine
                    } label: {
                        HStack {
                            Text(engine.name).font(.body.weight(.medium))
                            Spacer()
                            Image(systemName: store.settings.searchEngine == engine ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.settings.searchEngine == engine ? store.settings.accent.color : Color.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var bar: some View {
        VStack(spacing: 22) {
            Text(L.t("welcomeBar")).font(.title.weight(.bold)).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                ForEach(AddressBarPosition.allCases) { position in
                    Button {
                        store.settings.addressBarPosition = position
                    } label: {
                        VStack(spacing: 10) {
                            phoneSketch(barAtTop: position == .top)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(store.settings.addressBarPosition == position ? store.settings.accent.color : Color(.separator),
                                                      lineWidth: store.settings.addressBarPosition == position ? 3 : 1)
                                )
                            Text(position.title).font(.subheadline.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func phoneSketch(barAtTop: Bool) -> some View {
        VStack(spacing: 6) {
            if barAtTop { Capsule().fill(store.settings.accent.color.opacity(0.8)).frame(height: 12) }
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 60, height: 10)
            Spacer(minLength: 0)
            if !barAtTop { Capsule().fill(store.settings.accent.color.opacity(0.8)).frame(height: 12) }
        }
        .padding(12)
        .frame(width: 110, height: 190)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var done: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 76))
                .foregroundStyle(.tint)
            Text(L.t("welcomeDone")).font(.largeTitle.weight(.bold))
            Text(L.t("welcomeDoneText")).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
