import SwiftUI
import UIKit
import WebKit
import OSLog

struct PortalWebView: UIViewRepresentable {
    let url: URL
    let backend: PortalBackend
    let ads: RewardedAds
    let onInitialLoadFinished: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(backend: backend, ads: ads, initialURL: url, onInitialLoadFinished: onInitialLoadFinished) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator; context.coordinator.webView = view
        context.coordinator.startSocket()
        view.load(URLRequest(url: url))
        context.coordinator.startInitialLoadDeadline()
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onInitialLoadFinished = onInitialLoadFinished
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.cancelInitialLoadDeadline()
        coordinator.stopSocket()
        view.stopLoading(); view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let backend: PortalBackend
        let ads: RewardedAds
        weak var webView: WKWebView?
        private var socket: PortalSocket?
        private let initialURL: URL
        var onInitialLoadFinished: (URL) -> Void
        private var initialLoadFinished = false
        private var initialLoadDeadline: Task<Void, Never>?
        private var initialContentProbe: Task<Void, Never>?
        private var initialLoadStarted: Date?
        private let startupLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Satchel", category: "PortalStartup")
        init(backend: PortalBackend, ads: RewardedAds, initialURL: URL, onInitialLoadFinished: @escaping (URL) -> Void) {
            self.backend = backend; self.ads = ads; self.initialURL = initialURL; self.onInitialLoadFinished = onInitialLoadFinished
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markInitialContentReady(reason: "navigation finished")
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !initialLoadFinished else { return }
            startupLog.info("Initial web navigation committed")
            initialContentProbe?.cancel()
            initialContentProbe = Task { @MainActor [weak self, weak webView] in
                while !Task.isCancelled {
                    guard let self, let webView, !self.initialLoadFinished else { return }
                    let script = """
                    (() => {
                        if (!document.body) return false;
                        if (document.body.innerText.trim().length > 0) return true;
                        return Array.from(document.images).some(image => {
                            const rect = image.getBoundingClientRect();
                            return image.complete && image.naturalWidth > 0 && rect.width > 0 && rect.height > 0;
                        });
                    })()
                    """
                    let ready = (try? await webView.evaluateJavaScript(script)) as? Bool ?? false
                    guard !Task.isCancelled else { return }
                    if ready { self.markInitialContentReady(reason: "visible content"); return }
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                }
            }
        }
        private func markInitialContentReady(reason: String) {
            guard !initialLoadFinished else { return }
            initialLoadFinished = true
            if let initialLoadStarted {
                startupLog.info("Initial web content ready; reason=\(reason, privacy: .public), seconds=\(Date().timeIntervalSince(initialLoadStarted), privacy: .public)")
            }
            cancelInitialLoadDeadline()
            onInitialLoadFinished(initialURL)
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if !initialLoadFinished, response.isForMainFrame,
               let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                startupLog.error("Initial web response failed; HTTP status=\(http.statusCode)")
                decisionHandler(.cancel)
                backend.closePortal()
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { initialFailure(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { initialFailure(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard !initialLoadFinished else { return }
            startupLog.error("Initial web content process terminated")
            cancelInitialLoadDeadline()
            backend.closePortal()
        }
        private func initialFailure(_ error: Error) {
            guard !initialLoadFinished, (error as NSError).code != NSURLErrorCancelled else { return }
            let failure = error as NSError
            startupLog.error("Initial web navigation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            cancelInitialLoadDeadline()
            backend.closePortal()
        }
        func startInitialLoadDeadline() {
            initialLoadStarted = Date()
            initialLoadDeadline = Task { @MainActor [weak self] in
                var activeSeconds = 0
                while activeSeconds < 30 {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard let self, !self.initialLoadFinished else { return }
                    if UIApplication.shared.applicationState == .active { activeSeconds += 1 }
                }
                guard let self, !self.initialLoadFinished else { return }
                self.startupLog.error("Initial web content timed out")
                self.backend.closePortal()
            }
        }
        func cancelInitialLoadDeadline() {
            initialLoadDeadline?.cancel(); initialLoadDeadline = nil
            initialContentProbe?.cancel(); initialContentProbe = nil
        }
        func startSocket() {
            guard let webView else { return }
            socket = PortalSocket(backend: backend, ads: ads, webView: webView)
            socket?.start()
        }
        func stopSocket() { socket?.stop(); socket = nil }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, PortalConfiguration.isWebURL(url) else {
                decisionHandler(.cancel)
                if !initialLoadFinished, action.targetFrame?.isMainFrame == true {
                    cancelInitialLoadDeadline()
                    backend.closePortal()
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}
