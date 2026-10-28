import SwiftUI
import StoreKit

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var membership: MembershipStore
    let l: L10n
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button(l.text("Me")) { dismiss() }.buttonStyle(SecondaryButton())
                Image("MembershipArt").resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity).accessibilityHidden(true)
                EditorialTitle(title: l.text("Satchel Membership"), subtitle: l.text("More room for every journey."))
                VStack(alignment: .leading, spacing: 10) {
                    Text(l.text("Free: up to 3 trips and 30 photos. Membership: unlimited trips and photos."))
                    Text(l.text("Your saved trips remain available to view and export even if membership ends.")).foregroundColor(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .modifier(SatchelGlass(tint: Palette.paper.opacity(0.16), cornerRadius: 16))
                if membership.isMember { Text(l.text("Your membership is active.")).foregroundColor(Palette.olive) }
                ForEach(membership.products, id: \.id) { product in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l.text(product.id == MembershipStore.monthlyID ? "Monthly membership" : "Yearly membership")).font(.system(size: 21, design: .serif))
                        Text(product.displayPrice + " / " + l.text(product.id == MembershipStore.monthlyID ? "month" : "year")).font(.headline)
                        Button(l.text("Subscribe")) { Task { await membership.purchase(product) } }.buttonStyle(PrimaryButton()).disabled(membership.loading)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Palette.cream, in: RoundedRectangle(cornerRadius: 14))
                }
                if membership.loading { Text(l.text("Loading…")).foregroundColor(Palette.muted) }
                if let message = membership.message { Text(l.text(message)).font(.footnote).foregroundColor(Palette.rust) }
                Button(l.text("Refresh products")) { Task { await membership.loadProducts() } }.buttonStyle(SecondaryButton()).disabled(membership.loading)
                Button(l.text("Restore purchases")) { Task { await membership.restore() } }.buttonStyle(SecondaryButton()).disabled(membership.loading)
                Button(l.text("Manage membership")) { if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) } }.buttonStyle(SecondaryButton())
                Text(l.text("Subscriptions renew automatically unless cancelled through your Apple account. Manage or cancel in your App Store account settings.")).font(.footnote).foregroundColor(Palette.muted)
                NavigationLink(l.text("Privacy policy")) { LegalDocumentView(document: .privacy, l: l) }.foregroundColor(Palette.rust)
                NavigationLink(l.text("Terms of use")) { LegalDocumentView(document: .terms, l: l) }.foregroundColor(Palette.rust)
            }.padding(20).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar)
    }
}
