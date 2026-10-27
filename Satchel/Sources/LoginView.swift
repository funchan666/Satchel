import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var backend: PortalBackend
    @State private var agreed = false
    @State private var document: LegalDocument?
    let l: L10n
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("LoginJourney").resizable().scaledToFill().frame(height: 280).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                EditorialTitle(title: "Satchel", subtitle: l.text("Your journeys, together."))
                Text(l.text("A little place for everything your journey holds.")).font(.system(size: 20, design: .serif)).foregroundColor(Palette.muted)
                Button {
                    guard agreed, !backend.busy else { return }
                    Task { await backend.signIn() }
                } label: {
                    Text(backend.busy ? l.text("Signing in…") : l.text("Sign in"))
                        .frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButton()).disabled(!agreed || backend.busy).opacity(agreed ? 1 : 0.55)
                HStack(alignment: .top, spacing: 9) {
                    Button { agreed.toggle() } label: {
                        Image(agreed ? "CheckOn" : "CheckOff").resizable().scaledToFit().frame(width: 28, height: 28)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(l.text("Agree to the terms and privacy policy")).accessibilityValue(agreed ? l.text("Selected") : l.text("Not selected"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l.text("I have read and agree to:")).font(.footnote).foregroundColor(Palette.muted)
                        HStack {
                            Button { document = .terms } label: { Text(l.text("Terms of use")).underline() }
                            Text("·").foregroundColor(Palette.muted)
                            Button { document = .privacy } label: { Text(l.text("Privacy policy")).underline() }
                        }.font(.footnote.weight(.semibold)).foregroundColor(Palette.rust)
                    }.padding(.top, 5)
                }
                if let error = backend.error { Text(l.text(error)).font(.footnote).foregroundColor(Palette.rust) }
                Text(l.text("Sign-in sends your network address and a device identifier to the service provider.")).font(.footnote).foregroundColor(Palette.muted)
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.modifier(Page())
            .sheet(item: $document) { doc in NavigationStack { LegalDocumentView(document: doc, l: l, presented: true) } }
    }
}
