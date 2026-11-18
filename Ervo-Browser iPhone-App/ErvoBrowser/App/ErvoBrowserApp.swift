import SwiftUI

@main
struct ErvoBrowserApp: App {
    @State private var store = BrowserStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environment(store)
                .tint(store.settings.accent.color)
                .preferredColorScheme(store.isPrivateMode ? Optional(ColorScheme.dark) : store.settings.themeMode.colorScheme)
                .onOpenURL { url in
                    store.handleIncoming(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.persistAll() }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !store.settings.onboarded },
                    set: { if !$0 { store.settings.onboarded = true } }
                )) {
                    OnboardingView()
                        .environment(store)
                        .tint(store.settings.accent.color)
                        .preferredColorScheme(store.settings.themeMode.colorScheme)
                }
        }
    }
}
