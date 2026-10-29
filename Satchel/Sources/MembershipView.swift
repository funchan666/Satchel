import SwiftUI
import StoreKit

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var membership: MembershipStore
    let l: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BackTagButton(label: l.text("Back")) { dismiss() }
                membershipCard
                benefitCard
                if membership.isMember {
                    Text(l.text("Your membership is active."))
                        .font(.subheadline.weight(.semibold)).foregroundColor(Palette.olive)
                        .padding(.horizontal, 8)
                }
                ForEach([MembershipStore.monthlyID, MembershipStore.yearlyID], id: \.self) { id in
                    planCard(id)
                }
                if membership.loading { Text(l.text("Loading…")).font(.footnote).foregroundColor(Palette.muted) }
                if let message = membership.message {
                    Text(l.text(message)).font(.footnote).foregroundColor(Palette.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(l.text("Subscriptions renew automatically unless cancelled through your Apple account. Manage or cancel in your App Store account settings."))
                    .font(.footnote).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink { LegalDocumentView(document: .privacy, l: l) } label: { Text(l.text("Privacy policy")).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(SecondaryButton())
                    NavigationLink { LegalDocumentView(document: .terms, l: l) } label: { Text(l.text("Terms of use")).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(SecondaryButton())
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar)
            .task { await membership.loadProducts() }
    }

    private var membershipCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("MembershipArt").resizable().scaledToFit().frame(width: 100, height: 100).accessibilityHidden(true)
            Text(l.text("More room for every journey."))
                .font(.system(size: 24, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .modifier(SatchelGlass(tint: Palette.seaTint.opacity(0.30), cornerRadius: 22))
    }

    private var benefitCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image("SeaJournal").resizable().scaledToFit().frame(width: 54, height: 54).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(l.text("Free: up to 3 trips and 30 photos. Membership: unlimited trips and photos."))
                    .font(.subheadline.weight(.medium))
                Text(l.text("Free: one travel question per day. Membership: unlimited questions."))
                    .font(.subheadline.weight(.medium))
                Text(l.text("Your saved trips remain available to view and export even if membership ends."))
                    .font(.footnote).foregroundColor(Palette.muted)
            }.fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .modifier(SatchelGlass(tint: Palette.cream.opacity(0.30), cornerRadius: 20))
    }

    private func periodDescription(_ product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        var components = DateComponents()
        let unit: NSCalendar.Unit
        switch period.unit {
        case .day: unit = .day; components.day = period.value
        case .week: unit = .weekOfMonth; components.weekOfMonth = period.value
        case .month: unit = .month; components.month = period.value
        case .year: unit = .year; components.year = period.value
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: l.code)
        formatter.calendar = calendar
        formatter.allowedUnits = unit
        formatter.unitsStyle = .full
        return formatter.string(from: components)
    }

    private func planCard(_ id: String) -> some View {
        let monthly = id == MembershipStore.monthlyID
        let product = membership.products.first { $0.id == id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(monthly ? "NavTrips" : "SeaJournal").resizable().scaledToFit()
                    .frame(width: 48, height: 48).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if let product, let period = periodDescription(product) {
                        Text(period).font(.system(size: 20, design: .serif)).fixedSize(horizontal: false, vertical: true)
                        Text(product.displayPrice + " / " + period)
                            .font(.subheadline.weight(.semibold)).foregroundColor(Palette.ocean)
                    } else {
                        Text(l.text(monthly ? "Monthly membership" : "Yearly membership"))
                            .font(.system(size: 20, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let product, periodDescription(product) != nil {
                Button { Task { await membership.purchase(product) } } label: {
                    Text(l.text("Subscribe")).frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButton()).disabled(membership.loading)
            } else {
                Button { Task { await membership.loadProducts() } } label: {
                    Text(l.text(membership.loading ? "Loading…" : "Refresh products")).frame(maxWidth: .infinity)
                }.buttonStyle(SecondaryButton()).disabled(membership.loading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .modifier(SatchelGlass(tint: Palette.cream.opacity(0.38), cornerRadius: 20))
    }
}
