import SwiftUI

@main struct SatchelApp: App {
    @StateObject private var store = TravelStore()
    @StateObject private var backend = PortalBackend()
    @AppStorage("satchel.language") private var language = "en"
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if backend.isSignedIn { RootView(l: L10n(code: language)) }
                else { LoginView(l: L10n(code: language)) }
            }
                .environmentObject(store)
                .environmentObject(store.membership)
                .environmentObject(backend)
                .environment(\.locale, Locale(identifier: language))
                .onChange(of: scenePhase) { phase in if phase == .active { Task { await store.membership.refreshEntitlements() } } }
        }
    }
}
