import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms = "Terms", privacy = "Privacy"
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of use" : "Privacy policy" }
    var url: URL? {
        URL(string: self == .terms ? "https://www.satchel.click/#terms" : "https://www.satchel.click/#privacy")
    }
}
struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument
    let l: L10n
    var presented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { BackTagButton(label: l.text(presented ? "Close" : "Back")) { dismiss() }; Spacer() }
            Text(l.text("The full document is currently available in English.")).font(.footnote).foregroundColor(Palette.muted)
            LegalWebView(document: document).frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }.padding(20).modifier(Page()).toolbar(.hidden, for: .navigationBar)
    }
}
struct LegalWebView: UIViewRepresentable {
    let document: LegalDocument
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear
        if let url = document.url {
            view.load(URLRequest(url: url))
        } else {
            view.loadHTMLString("<!doctype html><meta name='viewport' content='width=device-width, initial-scale=1'><p>Document unavailable.</p>", baseURL: nil)
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
