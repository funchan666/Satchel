import SwiftUI
import UIKit

@main struct SatchelApp: App {
    @StateObject private var store = TravelStore()
    @StateObject private var backend = PortalBackend()
    @StateObject private var ads = RewardedAds()
    @AppStorage("satchel.language") private var language = "en"
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingStartup = true
    @State private var startupStarted = false
    @State private var routeResolved = false
    @State private var startupAdStarted = false
    @State private var startupAdResolved = false

    var body: some Scene {
        WindowGroup {
            Group {
                if showingStartup {
                    StartupView(l: L10n(code: language)).ignoresSafeArea(.container)
                } else if backend.url != nil {
                    PortalEntry(l: L10n(code: language), directEntry: true)
                } else {
                    RootView(l: L10n(code: language))
                }
            }
            .background(AdPresentationAnchor { controller in beginStartupAd(from: controller) })
            .environmentObject(store)
            .environmentObject(store.membership)
            .environmentObject(backend)
            .environmentObject(ads)
            .environment(\.locale, Locale(identifier: language))
            .task { startSession() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await store.membership.refreshEntitlements() } }
            }
        }
    }

    private func startSession() {
        guard !startupStarted else { return }
        startupStarted = true
        Task { @MainActor in
            await backend.signIn()
            if backend.isSignedIn { await backend.open(language: language) }
            routeResolved = true
            finishStartupIfReady()
        }
        // An unfilled or slow app-open request must never block the app indefinitely.
        Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            if !ads.openConsentInProgress && !ads.openAdIsPresenting {
                ads.cancelPendingOpen()
                startupAdResolved = true
                finishStartupIfReady()
            }
        }
    }

    private func beginStartupAd(from controller: UIViewController) {
        guard showingStartup, !startupAdStarted, !startupAdResolved else { return }
        startupAdStarted = true
        Task { @MainActor in
            _ = await ads.showAppOpen(from: controller) {
                showingStartup && !startupAdResolved && scenePhase == .active
            }
            startupAdResolved = true
            finishStartupIfReady()
        }
    }

    private func finishStartupIfReady() {
        if routeResolved && startupAdResolved { showingStartup = false }
    }
}

// The presenter belongs to this view's window rather than an arbitrary app scene.
private struct AdPresentationAnchor: UIViewControllerRepresentable {
    let onReady: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController()
        controller.onReady = onReady
        return controller
    }
    func updateUIViewController(_ controller: AnchorController, context: Context) { controller.onReady = onReady }
    final class AnchorController: UIViewController {
        var onReady: ((UIViewController) -> Void)?
        override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onReady?(self) }
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
