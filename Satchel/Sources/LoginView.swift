import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var backend: PortalBackend
    @State private var agreed = false
    @State private var document: LegalDocument?
    let l: L10n

    var body: some View {
        GeometryReader { container in
            ZStack {
                GeometryReader { background in
                    Image("LoginCoast")
                        .resizable()
                        .scaledToFill()
                        .frame(width: background.size.width, height: background.size.height)
                        .clipped()
                }
                .ignoresSafeArea(.container)
                .accessibilityHidden(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        brand
                        Spacer(minLength: 100)
                        signInPanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 580)
                    .frame(minHeight: container.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(item: $document) { doc in
            NavigationStack { LegalDocumentView(document: doc, l: l, presented: true) }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Satchel")
                .font(.system(size: 38, weight: .regular, design: .serif))
                .accessibilityAddTraits(.isHeader)
            Text(l.text("Your journeys, together."))
                .font(.subheadline)
        }
        .foregroundColor(Palette.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(SatchelGlass(tint: Palette.cream.opacity(0.65), cornerRadius: 20))
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l.text("A little place for everything your journey holds."))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Button {
                guard agreed, !backend.busy else { return }
                Task { await backend.signIn() }
            } label: {
                Text(backend.busy ? l.text("Signing in…") : l.text("Sign in"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Palette.rust.opacity(agreed && !backend.busy ? 1 : 0.65), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!agreed || backend.busy)

            consent

            if let error = backend.error {
                Text(l.text(error)).font(.footnote).foregroundColor(Palette.rust)
            }
        }
        .foregroundColor(Palette.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SatchelGlass(tint: Palette.cream.opacity(0.7), cornerRadius: 26))
    }

    private var consent: some View {
        HStack(alignment: .top, spacing: 4) {
            Button { agreed.toggle() } label: {
                Image(agreed ? "CheckOn" : "CheckOff")
                    .resizable().scaledToFit().frame(width: 26, height: 26)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l.text("Agree to the terms and privacy policy"))
            .accessibilityValue(agreed ? l.text("Selected") : l.text("Not selected"))

            VStack(alignment: .leading, spacing: 6) {
                Text(l.text("I have read and agree to:"))
                    .font(.footnote).foregroundColor(Palette.muted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        termsButton
                        Text("·").foregroundColor(Palette.muted)
                        privacyButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        termsButton
                        privacyButton
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(Palette.rust)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var termsButton: some View {
        Button { document = .terms } label: { Text(l.text("Terms of use")).underline() }
            .buttonStyle(.plain)
    }

    private var privacyButton: some View {
        Button { document = .privacy } label: { Text(l.text("Privacy policy")).underline() }
            .buttonStyle(.plain)
    }
}
