import SwiftUI

@main struct SatchelApp: App {
    @StateObject private var store = TravelStore()
    @StateObject private var backend = PortalBackend()
    @AppStorage("satchel.language") private var language = "en"
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingStartup = true
    var body: some Scene {
        WindowGroup {
            Group {
                if backend.isSignedIn { RootView(l: L10n(code: language)) }
                else { LoginView(l: L10n(code: language)) }
            }
                .accessibilityHidden(showingStartup)
                .overlay {
                    if showingStartup {
                        StartupView(l: L10n(code: language))
                            .ignoresSafeArea(.container)
                    }
                }
                .environmentObject(store)
                .environmentObject(store.membership)
                .environmentObject(backend)
                .environment(\.locale, Locale(identifier: language))
                .task {
                    guard showingStartup else { return }
                    do {
                        try await Task.sleep(nanoseconds: 800_000_000)
                        showingStartup = false
                    } catch { }
                }
                .onChange(of: scenePhase) { phase in if phase == .active { Task { await store.membership.refreshEntitlements() } } }
        }
    }
}

private struct StartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false
    let l: L10n

    var body: some View {
        GeometryReader { container in
            let iconSize = max(0, min(184, min(container.size.width - 32, container.size.height - 64)))
            VStack(spacing: 24) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)

                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Image("LaunchStitch")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 8)
                            .opacity(!reduceMotion && animating ? 0.3 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.14), value: animating)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(l.text("Loading…"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 253 / 255, green: 248 / 255, blue: 231 / 255).ignoresSafeArea())
        .onAppear { animating = true }
    }
}
