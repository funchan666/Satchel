import SwiftUI
import WebKit

struct PortalEntry: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("satchel.language") private var language = "en"
    @EnvironmentObject private var backend: PortalBackend
    @EnvironmentObject private var ads: RewardedAds
    @State private var privacyError = false
    let l: L10n
    var directEntry = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !directEntry { HStack { Button(l.text("Me")) { backend.closePortal(); dismiss() }.buttonStyle(SecondaryButton()); Spacer() } }
            if ads.privacyOptionsRequired { Button(l.text("Ad privacy choices")) { Task { do { try await ads.showPrivacyOptions(from: nil) } catch { privacyError = true } } }.buttonStyle(SecondaryButton()) }
            if privacyError { Text(l.text("Privacy options are unavailable right now.")).foregroundColor(Palette.rust) }
            if let url = backend.url {
                PortalWebView(url: url, backend: backend, ads: ads, fallbackOnFailure: directEntry).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(l.text("Opening the online service sends your network address and a device identifier to its provider.")).foregroundColor(Palette.muted)
                if let error = backend.error { Text(l.text(error)).foregroundColor(Palette.rust) }
                Button(backend.busy ? l.text("Connecting…") : l.text("Connect")) { Task { await backend.open(language: language) } }.buttonStyle(PrimaryButton()).disabled(backend.busy)
                Spacer()
            }
        }.padding(20).modifier(Page()).toolbar(.hidden, for: .navigationBar)
            .onDisappear { if !directEntry && !ads.isPresentingFullScreen && backend.url == nil { backend.closePortal() } }
    }
}

struct PortalWebView: UIViewRepresentable {
    let url: URL
    let backend: PortalBackend
    let ads: RewardedAds
    let fallbackOnFailure: Bool
    func makeCoordinator() -> Coordinator { Coordinator(backend: backend, ads: ads, fallbackOnFailure: fallbackOnFailure) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; context.coordinator.webView = view
        context.coordinator.startSocket()
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopSocket()
        view.stopLoading(); view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let backend: PortalBackend
        let ads: RewardedAds
        weak var webView: WKWebView?
        private var socket: PortalSocket?
        private let fallbackOnFailure: Bool
        private var initialLoadFinished = false
        init(backend: PortalBackend, ads: RewardedAds, fallbackOnFailure: Bool) {
            self.backend = backend; self.ads = ads; self.fallbackOnFailure = fallbackOnFailure
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { initialLoadFinished = true }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if fallbackOnFailure, !initialLoadFinished, response.isForMainFrame,
               let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                decisionHandler(.cancel)
                backend.closePortal()
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { initialFailure(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { initialFailure(error) }
        private func initialFailure(_ error: Error) {
            guard fallbackOnFailure, !initialLoadFinished, (error as NSError).code != NSURLErrorCancelled else { return }
            backend.closePortal()
        }
        func startSocket() {
            guard let webView else { return }
            socket = PortalSocket(backend: backend, ads: ads, webView: webView)
            socket?.start()
        }
        func stopSocket() { socket?.stop(); socket = nil }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, PortalConfiguration.isWebURL(url) else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}
