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
                    JournalOverview(l: l, creating: $creating).opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
                    SettingsView(l: l).opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    ForEach(Array(["Trips", "Journal", "Me"].enumerated()), id: \.offset) { index, title in
                        Button { tab = index } label: {
                            VStack(spacing: 2) {
                                Image(["SeaTrips", "SeaJournal", "SeaMe"][index]).resizable().scaledToFit().frame(width: index == 2 ? 46 : 38, height: 38).accessibilityHidden(true)
                                Text(l.text(title)).font(.system(.caption, design: .rounded).weight(tab == index ? .bold : .medium)).multilineTextAlignment(.center)
                            }.foregroundColor(tab == index ? Palette.ocean : Palette.muted).frame(maxWidth: .infinity).frame(minHeight: 64)
                                .background { if tab == index { Image("SeaSecondary").resizable().interpolation(.high).opacity(0.68).accessibilityHidden(true) } }
                                .contentShape(Rectangle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let l: L10n
    @Binding var creating: Bool
    @State private var query = ""
    @State private var showSearch = false
    private var sorted: [Trip] { store.trips.sorted { $0.start > $1.start } }
    private var filtered: [Trip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? sorted : sorted.filter { $0.destination.localizedCaseInsensitiveContains(term) || $0.entries.contains { $0.text.localizedCaseInsensitiveContains(term) } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Satchel").font(.system(size: 36, design: .serif))
                        Text(l.text("Your journeys, together.")).font(.subheadline).foregroundColor(Palette.muted)
                    }
                    Spacer(minLength: 10)
                    Button(l.text(showSearch ? "Cancel" : "Search")) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showSearch.toggle(); if !showSearch { query = "" } } }
                        .buttonStyle(SecondaryButton())
                }
                if showSearch {
                    TextField(l.text("Search journeys and memories"), text: $query).modifier(FieldStyle())
                        .accessibilityLabel(l.text("Search journeys and memories"))
                }
                if sorted.isEmpty {
                    welcome
                    HStack(alignment: .top, spacing: 20) {
                        Image("TravelTicket").resizable().scaledToFit().frame(width: 74).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(l.text("A little room for every journey")).font(.system(size: 21, design: .serif))
                            Text(l.text("Keep your packing list and memories in one place.")).font(.subheadline).foregroundColor(Palette.muted)
                        }
                    }.padding(.horizontal, 3)
                } else {
                    overview
                    if filtered.isEmpty {
                        Text(l.text("No matching journeys")).font(.system(size: 22, design: .serif)).padding(.vertical, 24)
                    } else {
                        let upcoming = filtered.filter { Calendar.current.startOfDay(for: $0.end) >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.start < $1.start }
                        let past = filtered.filter { Calendar.current.startOfDay(for: $0.end) < Calendar.current.startOfDay(for: Date()) }
                        if !upcoming.isEmpty { section(l.text("Upcoming"), trips: upcoming) }
                        if !past.isEmpty { section(l.text("Past journeys"), trips: past) }
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28).frame(maxWidth: 720)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.text("Your next journey starts here.")).font(.system(size: 31, design: .serif)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
            Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }.buttonStyle(PrimaryButton()).padding(.top, 3)
        }.padding(22).frame(maxWidth: .infinity, minHeight: 350, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    Image("SeaJourneyHero").resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay(Palette.ink.opacity(0.62)).accessibilityHidden(true)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text(l.text("Your journeys")).font(.system(size: 27, design: .serif))
                Spacer()
                Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }.buttonStyle(PrimaryButton())
            }
            HStack(spacing: 20) {
                countLabel(store.trips.count, title: l.text("Trips"))
                countLabel(store.trips.reduce(0) { $0 + $1.entries.count }, title: l.text("Memories"))
                Spacer(minLength: 0)
            }
        }
    }
    private func countLabel(_ count: Int, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)").font(.system(size: 22, design: .serif)).monospacedDigit()
            Text(title).font(.caption.weight(.medium)).foregroundColor(Palette.muted)
        }
    }
    private func section(_ title: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, design: .serif))
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
            ZStack(alignment: .bottomTrailing) {
                PhotoView(name: trip.cover).frame(height: featured ? 210 : 150).frame(maxWidth: .infinity).clipped()
                Text(l.text(showsJournal ? "Journal" : "Open trip"))
                    .font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 9)
                    .modifier(SatchelGlass(tint: Palette.paper.opacity(0.18), cornerRadius: 12)).padding(12)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(trip.destination).font(.system(size: 25, design: .serif)).multilineTextAlignment(.leading)
                Text(trip.start.formatted(date: .abbreviated, time: .omitted) + " — " + trip.end.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundColor(Palette.muted)
                if showsJournal { Text("\(trip.entries.count)  ·  \(l.text("Memories"))").font(.caption.weight(.semibold)).foregroundColor(Palette.olive) }
                else if !trip.items.isEmpty { Text("\(trip.items.filter(\.packed).count) / \(trip.items.count)  ·  \(l.text("Packing"))").font(.caption.weight(.semibold)).foregroundColor(Palette.olive) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
        }.background(Palette.cream, in: RoundedRectangle(cornerRadius: 20)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
struct JournalOverview: View {
    @EnvironmentObject var store: TravelStore
    let l: L10n
    @Binding var creating: Bool
    @State private var query = ""
    @State private var selectedTrip: Trip?
    private var trips: [Trip] { store.trips.sorted { $0.start > $1.start } }
    private var matches: [Trip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trips.filter { trip in !trip.entries.isEmpty && (term.isEmpty || trip.destination.localizedCaseInsensitiveContains(term) || trip.entries.contains { $0.text.localizedCaseInsensitiveContains(term) }) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorialTitle(title: l.text("Journal"))
                if !trips.isEmpty {
                    TextField(l.text("Search journeys and memories"), text: $query).modifier(FieldStyle())
                    if trips.count == 1, let trip = trips.first, !trip.entries.isEmpty {
                        Button { selectedTrip = trip } label: { AddActionLabel(title: l.text("Add a memory")) }.buttonStyle(PrimaryButton())
                    } else if trips.count > 1 {
                        Text(l.text("Choose a journey to add a memory")).font(.subheadline.weight(.semibold)).foregroundColor(Palette.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(trips) { trip in Button(trip.destination) { selectedTrip = trip }.buttonStyle(SecondaryButton()) } }
                        }
                    }
                }
                if trips.isEmpty {
                    Image("SeaJournal").resizable().scaledToFit().frame(maxWidth: 250).frame(maxWidth: .infinity).accessibilityHidden(true)
                    Text(l.text("Your memories start here.")).font(.system(size: 25, design: .serif))
                    Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }.buttonStyle(PrimaryButton())
                } else if matches.isEmpty {
                    Image("SeaJournal").resizable().scaledToFit().frame(maxWidth: 200).frame(maxWidth: .infinity).accessibilityHidden(true)
                    Text(l.text(query.isEmpty ? "Your memories start here." : "No matching memories")).font(.system(size: 23, design: .serif))
                    if query.isEmpty, trips.count == 1, let trip = trips.first { Button { selectedTrip = trip } label: { AddActionLabel(title: l.text("Add a memory")) }.buttonStyle(PrimaryButton()) }
                } else {
                    ForEach(matches) { trip in
                        NavigationLink { TripDetail(tripID: trip.id, l: l, initialSection: 1) } label: { memoryCard(trip) }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28).frame(maxWidth: 720)
        }.sheet(item: $selectedTrip) { trip in EntryEditor(l: l, tripID: trip.id, existing: nil) }
    }
    private func memoryCard(_ trip: Trip) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = trip.entries.sorted { $0.date > $1.date }
        let entry = entries.first { term.isEmpty || trip.destination.localizedCaseInsensitiveContains(term) || $0.text.localizedCaseInsensitiveContains(term) } ?? entries.first
        return VStack(alignment: .leading, spacing: 0) {
            PhotoView(name: entry?.photos.first ?? trip.cover).frame(height: 190).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.destination).font(.system(size: 24, design: .serif))
                    Spacer(minLength: 8)
                    Text("\(trip.entries.count)  ·  \(l.text("Memories"))").font(.caption.weight(.semibold)).foregroundColor(Palette.olive)
                }
                if let entry {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold)).foregroundColor(Palette.rust)
                    if !entry.text.isEmpty { Text(entry.text).font(.subheadline).foregroundColor(Palette.ink).lineLimit(3).multilineTextAlignment(.leading) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
        }.background(Palette.cream, in: RoundedRectangle(cornerRadius: 20)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: TravelStore
    @EnvironmentObject private var ads: RewardedAds
    @State private var exportFile: ExportFile?
    @State private var privacyError = false
    let l: L10n
    @AppStorage("satchel.language") private var language = "en"
    private let options = [("en", "English"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("ja", "日本語"), ("ko", "한국어"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    EditorialTitle(title: l.text("Me"), subtitle: l.text("Your travel journal stays on this device."))
                    Image("SeaTrips").resizable().scaledToFit().frame(width: 94, height: 74).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(l.text("Your collection")).font(.system(size: 22, design: .serif))
                    HStack(spacing: 18) {
                        collectionCount(store.trips.count, l.text("Trips"))
                        collectionCount(store.trips.reduce(0) { $0 + $1.entries.count }, l.text("Memories"))
                        collectionCount(store.referencedPhotos(in: store.trips).count, l.text("Photos"))
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .modifier(SatchelGlass(tint: Palette.paper.opacity(0.18), cornerRadius: 20))
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.text("Your Satchel")).font(.system(size: 22, design: .serif)).padding(.bottom, 12)
                    VStack(spacing: 0) {
                        NavigationLink { MembershipView(l: l) } label: { settingRow("Satchel Membership", artwork: "MembershipArt") }.buttonStyle(.plain)
                        NavigationLink { TemplateView(l: l) } label: { settingRow("Common list", artwork: "SeaTrips") }.buttonStyle(.plain)
                        Button { do { exportFile = ExportFile(url: try store.export()) } catch { store.error = "Your journal could not be exported. Please try again." } } label: { settingRow("Export your journal", artwork: "SeaJournal") }.buttonStyle(.plain)
                    }.padding(.horizontal, 14).modifier(SatchelGlass(tint: Palette.paper.opacity(0.16), cornerRadius: 20))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.text("More options")).font(.system(size: 22, design: .serif)).padding(.bottom, 12)
                    VStack(spacing: 0) {
                        NavigationLink { PortalEntry(l: l) } label: { settingRow("Online service") }.buttonStyle(.plain)
                        NavigationLink { LegalDocumentView(document: .privacy, l: l) } label: { settingRow("Privacy policy") }.buttonStyle(.plain)
                        NavigationLink { LegalDocumentView(document: .terms, l: l) } label: { settingRow("Terms of use") }.buttonStyle(.plain)
                        if ads.privacyOptionsRequired {
                            Button { Task { do { try await ads.showPrivacyOptions(from: nil) } catch { privacyError = true } } } label: { settingRow("Ad privacy choices") }.buttonStyle(.plain)
                        }
                        if privacyError { Text(l.text("Privacy options are unavailable right now.")).font(.footnote).foregroundColor(Palette.rust).padding(.vertical, 8) }
                    }.padding(.horizontal, 14).modifier(SatchelGlass(tint: Palette.paper.opacity(0.16), cornerRadius: 20))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(l.text("Language")).font(.system(size: 22, design: .serif))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                        ForEach(options, id: \.0) { option in
                            Button { language = option.0 } label: {
                                HStack(spacing: 6) { Text(option.1).font(.subheadline); Spacer(minLength: 2); if language == option.0 { Image("SeaCheckOn").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true) } }
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .modifier(SatchelGlass(tint: language == option.0 ? Palette.ocean.opacity(0.20) : Palette.paper.opacity(0.12), interactive: true, cornerRadius: 12, fallback: language == option.0 ? Palette.seaTint : Palette.cream))
                            }.buttonStyle(.plain).accessibilityValue(language == option.0 ? l.text("Selected") : l.text("Not selected"))
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28).frame(maxWidth: 720)
        }.sheet(item: $exportFile) { ShareSheet(file: $0.url) }
    }
    private func collectionCount(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text("\(count)").font(.system(size: 24, design: .serif)).monospacedDigit(); Text(label).font(.caption).foregroundColor(Palette.muted) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func settingRow(_ title: String, artwork: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let artwork { Image(artwork).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true) }
            Text(l.text(title)).font(.body.weight(.medium)).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image("ForwardMark").resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(.vertical, 4)
            .overlay(alignment: .bottom) { Palette.muted.opacity(0.12).frame(height: 0.5) }
            .contentShape(Rectangle())
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
