import SwiftUI
import WebKit

struct PortalEntry: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("satchel.language") private var language = "en"
    @EnvironmentObject private var backend: PortalBackend
    @StateObject private var ads = RewardedAds()
    @State private var privacyError = false
    let l: L10n
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Button(l.text("Me")) { backend.closePortal(); dismiss() }.buttonStyle(SecondaryButton()); Spacer() }
            if ads.privacyOptionsRequired { Button(l.text("Ad privacy choices")) { Task { do { try await ads.showPrivacyOptions(from: nil) } catch { privacyError = true } } }.buttonStyle(SecondaryButton()) }
            if privacyError { Text(l.text("Privacy options are unavailable right now.")).foregroundColor(Palette.rust) }
            if let url = backend.url {
                PortalWebView(url: url, backend: backend, ads: ads).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EditorialTitle(title: l.text("Online service"))
                Text(l.text("Opening the online service sends your network address and a device identifier to its provider.")).foregroundColor(Palette.muted)
                if let error = backend.error { Text(l.text(error)).foregroundColor(Palette.rust) }
                Button(backend.busy ? l.text("Connecting…") : l.text("Connect")) { Task { await backend.open(language: language) } }.buttonStyle(PrimaryButton()).disabled(backend.busy)
                Spacer()
            }
        }.padding(20).modifier(Page()).toolbar(.hidden, for: .navigationBar)
            .onDisappear { backend.closePortal() }
    }
}

struct PortalWebView: UIViewRepresentable {
    let url: URL
    let backend: PortalBackend
    let ads: RewardedAds
    func makeCoordinator() -> Coordinator { Coordinator(backend: backend, ads: ads) }
    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        let shim = """
        (() => {
          if (!window.flutter_inappwebview) window.flutter_inappwebview = {};
          if (!window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler = function(name, payload) {
              if (name !== 'appBridge') return Promise.reject(new Error('Unsupported handler'));
              return window.webkit.messageHandlers.appBridge.postMessage(payload);
            };
          }
        })();
        """
        content.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "appBridge")
        let config = WKWebViewConfiguration(); config.userContentController = content
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; context.coordinator.webView = view
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "appBridge", contentWorld: .page)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
        let backend: PortalBackend
        let ads: RewardedAds
        weak var webView: WKWebView?
        private var pending: Set<String> = []
        init(backend: PortalBackend, ads: RewardedAds) { self.backend = backend; self.ads = ads }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, PortalConfiguration.isWebURL(url) else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            let origin = message.frameInfo.securityOrigin
            guard let trusted = backend.url, trusted.scheme?.lowercased() == "https", let host = trusted.host?.lowercased(),
                  message.frameInfo.isMainFrame, origin.`protocol`.lowercased() == "https", origin.host.lowercased() == host,
                  origin.port == (trusted.port ?? 443) || (trusted.port == nil && origin.port == 0) else {
                replyHandler(response(id: "", action: "", status: "failed", code: "origin_not_allowed", message: "Origin is not allowed."), nil); return
            }
            guard let payload = message.body as? [String: Any], let id = payload["requestId"] as? String, (1...128).contains(id.count),
                  let action = payload["action"] as? String, let version = payload["version"] as? Int, version == 1, payload["params"] is [String: Any] else {
                replyHandler(response(id: "", action: "", status: "failed", code: "invalid_request", message: "Invalid bridge request."), nil); return
            }
            guard pending.insert(id).inserted else { replyHandler(response(id: id, action: action, status: "failed", code: "duplicate_request_id", message: "Request is already in progress."), nil); return }
            Task { @MainActor in
                defer { pending.remove(id) }
                switch action {
                case "subscription.getStatus":
                    do { let result = try await backend.userStatus(); replyHandler(["version": 1, "requestId": id, "action": action, "ok": true, "status": "available", "data": result], nil) }
                    catch { replyHandler(response(id: id, action: action, status: "failed", code: "user_query_failed", message: "Unable to retrieve account status."), nil) }
                case "subscription.getProducts", "subscription.purchase", "subscription.restore":
                    replyHandler(response(id: id, action: action, status: "config_error", code: "not_configured", message: "Web subscriptions are not configured."), nil)
                case "ad.showRewarded":
                    let result = await ads.show(from: presentingController())
                    if result == "rewarded" || result == "dismissed" {
                        replyHandler(["version": 1, "requestId": id, "action": action, "ok": true, "status": result, "data": ["completed": result == "rewarded"]], nil)
                    } else {
                        var failure = response(id: id, action: action, status: "failed", code: result, message: "Rewarded ad is unavailable.")
                        failure["data"] = ["completed": false]; replyHandler(failure, nil)
                    }
                default:
                    replyHandler(response(id: id, action: action, status: "failed", code: "invalid_request", message: "Unsupported action."), nil)
                }
            }
        }
        private func presentingController() -> UIViewController? {
            var responder: UIResponder? = webView
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }
        private func response(id: String, action: String, status: String, code: String, message: String) -> [String: Any] {
            ["version": 1, "requestId": id, "action": action, "ok": false, "status": status, "error": ["code": code, "message": message]]
        }
    }
}
