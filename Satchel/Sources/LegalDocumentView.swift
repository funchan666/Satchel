import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms = "Terms", privacy = "Privacy"
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of use" : "Privacy policy" }
}
struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument
    let l: L10n
    var presented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Button(l.text(presented ? "Close" : "Me")) { dismiss() }.buttonStyle(SecondaryButton()); Spacer() }
            Text(l.text(document.title)).font(.system(size: 25, design: .serif))
            Text(l.text("The full document is currently available in English.")).font(.footnote).foregroundColor(Palette.muted)
            LegalWebView(document: document).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(20).modifier(Page()).toolbar(.hidden, for: .navigationBar)
    }
}
struct LegalWebView: UIViewRepresentable {
    let document: LegalDocument
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear
        if let url = Bundle.main.url(forResource: document.rawValue, withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<!doctype html><meta name='viewport' content='width=device-width, initial-scale=1'><p>Document unavailable.</p>", baseURL: nil)
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
