import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: TravelStore
    let l: L10n
    @State private var tab = 0
    @State private var creating = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = store.error {
                    HStack { Text(l.text(message)).font(.footnote); Spacer(); Button("OK") { store.error = nil }.buttonStyle(SecondaryButton()) }.padding(12).background(Palette.cream)
                }
                ZStack {
                    TripsView(l: l, creating: $creating).opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
                    JournalOverview(l: l).opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
                    SettingsView(l: l).opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    ForEach(Array(["Trips", "Journal", "Me"].enumerated()), id: \.offset) { index, title in
                        Button { tab = index } label: {
                            VStack(spacing: 2) {
                                Image(["TripsIcon", "JournalIcon", "MeIcon"][index]).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                                Text(l.text(title)).font(.system(.caption, design: .rounded).weight(tab == index ? .bold : .medium)).multilineTextAlignment(.center)
                            }.foregroundColor(tab == index ? Palette.rust : Palette.muted).frame(maxWidth: .infinity).frame(minHeight: 64).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(tab == index ? l.text("Selected") : l.text("Not selected"))
                    }
                }
                .padding(.horizontal, 8)
                .modifier(SatchelGlass(tint: Palette.paper.opacity(0.12), interactive: true, cornerRadius: 22))
                .padding(.horizontal, 16).padding(.vertical, 8)
            }.modifier(Page())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $creating) { NewTripView(l: l) }
        }
    }
}
struct TripsView: View {
    @EnvironmentObject var store: TravelStore
    let l: L10n
    @Binding var creating: Bool
    private var sorted: [Trip] { store.trips.sorted { $0.start > $1.start } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorialTitle(title: "Satchel", subtitle: l.text("Your journeys, together."))
                if !sorted.isEmpty { Button(l.text("New Trip")) { creating = true }.buttonStyle(PrimaryButton()) }
                if sorted.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Image("PackingEmpty").resizable().scaledToFit().frame(maxWidth: 270).frame(maxWidth: .infinity)
                        Text(l.text("Your next journey starts here.")).font(.system(size: 25, design: .serif))
                        Text(l.text("Keep your packing list and memories in one place.")).foregroundColor(Palette.muted)
                        Button(l.text("New Trip")) { creating = true }.buttonStyle(PrimaryButton())
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    let upcoming = sorted.filter { Calendar.current.startOfDay(for: $0.end) >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.start < $1.start }
                    let past = sorted.filter { Calendar.current.startOfDay(for: $0.end) < Calendar.current.startOfDay(for: Date()) }
                    if !upcoming.isEmpty { section(l.text("Upcoming"), trips: upcoming) }
                    if !past.isEmpty { section(l.text("Past journeys"), trips: past) }
                }
            }.padding(20).frame(maxWidth: 720)
        }
    }
    @ViewBuilder private func section(_ title: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 21, design: .serif))
            ForEach(trips) { trip in
                NavigationLink { TripDetail(tripID: trip.id, l: l) } label: { TripCard(trip: trip, l: l, featured: trip.id == trips.first?.id) }.buttonStyle(.plain)
            }
        }
    }
}
struct TripCard: View {
    let trip: Trip
    let l: L10n
    var featured = false
    var showsJournal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoView(name: trip.cover).frame(height: featured ? 220 : 150).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(trip.destination).font(.system(size: 24, design: .serif)); Spacer(); Text(l.text("Open trip")).font(.caption.weight(.semibold)).foregroundColor(Palette.rust) }
                Text(trip.start.formatted(date: .abbreviated, time: .omitted) + " — " + trip.end.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundColor(Palette.muted)
                if showsJournal { Text("\(trip.entries.count)  ·  \(l.text("Journal"))").font(.caption.weight(.medium)).foregroundColor(Palette.olive) }
                else if !trip.items.isEmpty { Text("\(trip.items.filter(\.packed).count) / \(trip.items.count)  ·  \(l.text("Packing"))").font(.caption.weight(.medium)).foregroundColor(Palette.olive) }
            }.padding(16)
        }.background(Palette.cream, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
struct JournalOverview: View {
    @EnvironmentObject var store: TravelStore
    let l: L10n
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorialTitle(title: l.text("Journal"), subtitle: l.text("Your memories start here."))
                if store.trips.filter({ !$0.entries.isEmpty }).isEmpty {
                    Image("JournalEmpty").resizable().scaledToFit().frame(maxWidth: 260).frame(maxWidth: .infinity).padding(.top, 30)
                    Text(l.text("Your memories start here.")).font(.system(size: 23, design: .serif))
                }
                ForEach(store.trips.filter { !$0.entries.isEmpty }.sorted { $0.start > $1.start }) { trip in
                    NavigationLink { TripDetail(tripID: trip.id, l: l, initialSection: 1) } label: { TripCard(trip: trip, l: l, showsJournal: true) }.buttonStyle(.plain)
                }
            }.padding(20).frame(maxWidth: 720)
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var exportFile: ExportFile?
    let l: L10n
    @AppStorage("satchel.language") private var language = "en"
    private let options = [("en", "English"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("ja", "日本語"), ("ko", "한국어"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    EditorialTitle(title: l.text("Me"), subtitle: l.text("Your travel journal stays on this device."))
                    Image("SatchelIllustration").resizable().scaledToFit().frame(width: 88, height: 70).accessibilityHidden(true)
                }
                SatchelGlassGroup {
                    VStack(spacing: 12) {
                        NavigationLink { MembershipView(l: l) } label: { Text(l.text("Satchel Membership")).frame(maxWidth: .infinity, alignment: .leading).padding(15).modifier(SatchelGlass(tint: Palette.paper.opacity(0.12), interactive: true, cornerRadius: 12)) }.buttonStyle(.plain)
                        NavigationLink { PortalEntry(l: l) } label: { Text(l.text("Online service")).frame(maxWidth: .infinity, alignment: .leading).padding(15).modifier(SatchelGlass(tint: Palette.paper.opacity(0.12), interactive: true, cornerRadius: 12)) }.buttonStyle(.plain)
                    }
                }
                Button(l.text("Export your journal")) { do { exportFile = ExportFile(url: try store.export()) } catch { store.error = "Your journal could not be exported. Please try again." } }.buttonStyle(SecondaryButton())
                NavigationLink { LegalDocumentView(document: .privacy, l: l) } label: { Text(l.text("Privacy policy")).frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                NavigationLink { LegalDocumentView(document: .terms, l: l) } label: { Text(l.text("Terms of use")).frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                NavigationLink { TemplateView(l: l) } label: { Text(l.text("Common list")).frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                Text(l.text("Language")).font(.system(size: 21, design: .serif))
                ForEach(options, id: \.0) { option in
                    Button { language = option.0 } label: {
                        HStack { Text(option.1); Spacer(); if language == option.0 { Image("CheckOn").resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true) } }
                            .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(20).frame(maxWidth: 720)
        }.sheet(item: $exportFile) { ShareSheet(file: $0.url) }
    }
}

struct TemplateView: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    let l: L10n
    @State private var draft: [PackingItem] = []
    @State private var name = ""
    @State private var category = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(l.text("Me")) { dismiss() }.buttonStyle(SecondaryButton())
                EditorialTitle(title: l.text("Common list"))
                ForEach($draft) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(l.text("Item name"), text: $item.name).modifier(FieldStyle())
                            .onChange(of: item.name) { _ in item.suggestedNameKey = nil }
                        TextField(l.text("Category"), text: $item.category).modifier(FieldStyle())
                            .onChange(of: item.category) { _ in item.suggestedCategoryKey = nil }
                        Button(l.text("Delete")) { draft.removeAll { $0.id == item.id } }.buttonStyle(SecondaryButton())
                    }.padding(12).background(Palette.cream.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
                TextField(l.text("Item name"), text: $name).modifier(FieldStyle())
                TextField(l.text("Category"), text: $category).modifier(FieldStyle())
                Button(l.text("Add item")) {
                    let n = name.trimmingCharacters(in: .whitespacesAndNewlines), c = category.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !n.isEmpty && !c.isEmpty { draft.append(PackingItem(name: n, category: c)); name = ""; category = "" }
                }.buttonStyle(SecondaryButton())
                Button(l.text("Save")) { if store.saveTemplate(draft.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { dismiss() } }.buttonStyle(PrimaryButton())
            }.padding(20).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar).onAppear {
            draft = store.template.map { var item = $0; item.name = item.suggestedNameKey.map(l.text) ?? item.name; item.category = item.suggestedCategoryKey.map(l.text) ?? item.category; return item }
        }
    }
}
