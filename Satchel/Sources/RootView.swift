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
                    TripsView(l: l, creating: $creating, tab: $tab).opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
                    JournalOverview(l: l, creating: $creating).opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
                    TravelGuideView(l: l, isActive: tab == 2).opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2)
                    SettingsView(l: l).opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3).accessibilityHidden(tab != 3)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 0) {
                    ForEach(Array(["Trips", "Journal", "Travel guide", "Me"].enumerated()), id: \.offset) { index, title in
                        Button { tab = index } label: {
                            Image(["NavTrips", "SeaJournal", "NavGuide", "NavMe"][index])
                                .resizable().scaledToFit().frame(width: 45, height: 45)
                                .opacity(tab == index ? 1 : 0.52)
                                .scaleEffect(tab == index ? 1.08 : 0.94)
                                .frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(l.text(title))
                            .accessibilityValue(tab == index ? l.text("Selected") : l.text("Not selected"))
                    }
                }
                .padding(.horizontal, 10).modifier(SatchelGlass(tint: Palette.paper.opacity(0.15), interactive: true, cornerRadius: 25))
                .padding(.horizontal, 20).padding(.vertical, 8)
            }.modifier(Page())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $creating) { NewTripView(l: l) }
        }
    }
}
struct TripsView: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let l: L10n
    @Binding var creating: Bool
    @Binding var tab: Int
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var sorted: [Trip] { store.trips.sorted { $0.start > $1.start } }
    private var filtered: [Trip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? sorted : sorted.filter { $0.destination.localizedCaseInsensitiveContains(term) || $0.entries.contains { $0.text.localizedCaseInsensitiveContains(term) } }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TabHero(artwork: "CoastNotebook")
                VStack(alignment: .leading, spacing: 20) {
                    searchCard
                    if sorted.isEmpty {
                        welcome
                    } else {
                        overview
                        if filtered.isEmpty {
                            Text(l.text("No matching journeys")).font(.system(.headline, design: .serif)).padding(.vertical, 24)
                        } else {
                            let upcoming = filtered.filter { Calendar.current.startOfDay(for: $0.end) >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.start < $1.start }
                            let past = filtered.filter { Calendar.current.startOfDay(for: $0.end) < Calendar.current.startOfDay(for: Date()) }
                            if !upcoming.isEmpty { section(l.text("Upcoming"), trips: upcoming) }
                            if !past.isEmpty { section(l.text("Past journeys"), trips: past) }
                        }
                    }
                    shortcuts
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28).frame(maxWidth: 720)
                    .background(Palette.paper)
            }.frame(maxWidth: .infinity)
        }.ignoresSafeArea(.container, edges: .top).onChange(of: tab) { if $0 != 0 { searchFocused = false } }
            .onChange(of: creating) { if $0 { searchFocused = false } }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.text("Explore Satchel")).font(.subheadline.weight(.semibold)).foregroundColor(Palette.muted)
            if dynamicTypeSize.isAccessibilitySize {
                shortcutStack
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        shortcut("JournalMarkV2", "Journal", subtitle: "Save travel memories", surface: "ButtonPaper", destination: 1)
                        shortcut("GuideMarkV2", "Travel guide", subtitle: "Ideas for your journey", surface: "ButtonSelected", destination: 2)
                    }.frame(minWidth: 260)
                    shortcutStack
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var shortcutStack: some View {
        VStack(spacing: 10) {
            shortcut("JournalMarkV2", "Journal", subtitle: "Save travel memories", surface: "ButtonPaper", destination: 1)
            shortcut("GuideMarkV2", "Travel guide", subtitle: "Ideas for your journey", surface: "ButtonSelected", destination: 2)
        }
    }
    private func shortcut(_ artwork: String, _ title: String, subtitle: String, surface: String, destination: Int) -> some View {
        Button { tab = destination } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(artwork).resizable().scaledToFit().frame(width: 42, height: 42).accessibilityHidden(true)
                Text(l.text(title)).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(l.text(subtitle)).font(.footnote).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .padding(12).modifier(PaperSurface(artwork: surface, radius: 16))
                .contentShape(Rectangle()).multilineTextAlignment(.leading)
        }.buttonStyle(ShortcutTileStyle())
            .accessibilityLabel(l.text(title)).accessibilityHint(l.text(subtitle))
    }
    private var searchCard: some View {
        HStack(spacing: 8) {
            Image("SearchMarkV2").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
            TextField(l.text("Search journeys and memories"), text: $query)
                .font(.subheadline).focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel(l.text("Search journeys and memories"))
                .frame(maxWidth: .infinity, minHeight: 48)
            if searchFocused || !query.isEmpty {
                Button(l.text("Cancel")) { query = ""; searchFocused = false }
                    .font(.footnote.weight(.semibold)).foregroundColor(Palette.ocean)
                    .frame(minHeight: 44).buttonStyle(.plain)
            }
        }.padding(.horizontal, 12).modifier(PaperSurface(artwork: "ButtonPaper", radius: 15))
    }
    private var welcome: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(l.text("Your next journey starts here."))
                    .font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true)
                Text(l.text("Keep your packing list and memories in one place."))
                    .font(.footnote).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }
                    .buttonStyle(TabPrimaryButton())
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 65).frame(maxWidth: 100)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PaperSurface(artwork: "JourneyPaper", radius: 22))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image("NavTrips").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    countLabel(store.trips.count, title: l.text("Trips"))
                    countLabel(store.trips.reduce(0) { $0 + $1.entries.count }, title: l.text("Memories"))
                }
                Spacer(minLength: 0)
            }
            Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }.buttonStyle(PrimaryButton())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .modifier(SatchelGlass(tint: Palette.seaTint.opacity(0.28), cornerRadius: 20))
    }
    private func countLabel(_ count: Int, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)").font(.system(.headline, design: .serif)).monospacedDigit()
            Text(title).font(.caption.weight(.medium)).foregroundColor(Palette.muted)
        }
    }
    private func section(_ title: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(.headline, design: .serif))
            ForEach(trips) { trip in
                NavigationLink { TripDetail(tripID: trip.id, l: l) } label: { TripCard(trip: trip, l: l, featured: trip.id == trips.first?.id) }.buttonStyle(.plain)
            }
        }
    }
}
private struct ShortcutTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
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
                Text(trip.destination).font(.system(.title3, design: .serif)).multilineTextAlignment(.leading)
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
            VStack(spacing: 0) {
                TabHero(artwork: "JournalCoast")
                VStack(alignment: .leading, spacing: 22) {
                    if !trips.isEmpty {
                        HStack(spacing: 8) {
                            Image("SearchMarkV2").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                            TextField(l.text("Search journeys and memories"), text: $query)
                                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 48)
                                .accessibilityLabel(l.text("Search journeys and memories"))
                        }.padding(.horizontal, 12).modifier(PaperSurface(artwork: "ButtonPaper", radius: 15))
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
                        journalInvitation
                    } else if matches.isEmpty {
                        if query.isEmpty { journalInvitation }
                        else { Text(l.text("No matching memories")).font(.system(.title3, design: .serif)) }
                    } else {
                        ForEach(matches) { trip in
                            NavigationLink { TripDetail(tripID: trip.id, l: l, initialSection: 1) } label: { memoryCard(trip) }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28).frame(maxWidth: 720)
                    .background(Palette.paper)
            }.frame(maxWidth: .infinity)
        }.ignoresSafeArea(.container, edges: .top)
            .navigationDestination(isPresented: Binding(
                get: { selectedTrip != nil },
                set: { if !$0 { selectedTrip = nil } }
            )) {
                if let trip = selectedTrip { EntryEditor(l: l, tripID: trip.id, existing: nil) }
            }
    }
    private var journalInvitation: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geometry in
                    Image("JournalPaperV2").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                Text(l.text("Your memories start here."))
                    .font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true)
                Text(l.text("Save the places, moments and photos you want to remember."))
                    .font(.subheadline).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if trips.isEmpty {
                    Text(l.text("Create a trip first, then add your first memory."))
                        .font(.footnote).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button { creating = true } label: { AddActionLabel(title: l.text("New Trip")) }.buttonStyle(TabPrimaryButton())
                } else if trips.count == 1, let trip = trips.first {
                    Button { selectedTrip = trip } label: { AddActionLabel(title: l.text("Add a memory")) }.buttonStyle(TabPrimaryButton())
                } else {
                    Text(l.text("Choose a journey above to begin."))
                        .font(.footnote).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .modifier(PaperSurface(artwork: "ButtonPaper", radius: 18))
            VStack(alignment: .leading, spacing: 8) {
                Text(l.text("A little inspiration")).font(.subheadline.weight(.semibold)).foregroundColor(Palette.muted)
                inspirationRow("TravelTicket", "A place worth remembering")
                inspirationRow("JournalMarkV2", "A moment that made you smile")
                inspirationRow("CoverCamera", "A photo and the story behind it")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func inspirationRow(_ artwork: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(artwork).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(l.text(title)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
    private func memoryCard(_ trip: Trip) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = trip.entries.sorted { $0.date > $1.date }
        let entry = entries.first { term.isEmpty || trip.destination.localizedCaseInsensitiveContains(term) || $0.text.localizedCaseInsensitiveContains(term) } ?? entries.first
        return VStack(alignment: .leading, spacing: 0) {
            PhotoView(name: entry?.photos.first ?? trip.cover).frame(height: 190).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.destination).font(.system(.title3, design: .serif))
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
    @EnvironmentObject private var membership: MembershipStore
    @State private var exportFile: ExportFile?
    @State private var restoreMessage: String?
    @State private var showLanguages = false
    let l: L10n
    @AppStorage("satchel.language") private var language = "en"
    private let options = [("en", "English"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("ja", "日本語"), ("ko", "한국어"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português")]
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TabHero(artwork: "CollectionCoast")
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l.text("Your collection"))
                            .font(.subheadline.weight(.semibold)).foregroundColor(Palette.muted)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 24) {
                                collectionCount(store.trips.count, l.text("Trips"))
                                collectionCount(store.trips.reduce(0) { $0 + $1.entries.count }, l.text("Memories"))
                                collectionCount(store.referencedPhotos(in: store.trips).count, l.text("Photos"))
                            }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 10) {
                                collectionCount(store.trips.count, l.text("Trips"))
                                collectionCount(store.trips.reduce(0) { $0 + $1.entries.count }, l.text("Memories"))
                                collectionCount(store.referencedPhotos(in: store.trips).count, l.text("Photos"))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .modifier(PaperSurface(artwork: "CollectionPaperV2", radius: 18))
                    NavigationLink { MembershipView(l: l) } label: {
                        HStack(spacing: 15) {
                            Image("MembershipArt").resizable().scaledToFit().frame(width: 74, height: 74).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(l.text("Satchel Membership")).font(.system(.headline, design: .serif)).multilineTextAlignment(.leading)
                                Text(l.text("More room for every journey.")).font(.caption).foregroundColor(Palette.muted).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image("NextMark").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(15)
                            .modifier(PaperSurface(artwork: "CoastalPaper", radius: 20))
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 0) {
                            NavigationLink { TemplateView(l: l) } label: { settingRow("Common list", artwork: "SeaTrips") }.buttonStyle(.plain)
                            Button { do { exportFile = ExportFile(url: try store.export()) } catch { store.error = "Your journal could not be exported. Please try again." } } label: { settingRow("Export your journal", artwork: "SeaJournal") }.buttonStyle(.plain)
                        }.padding(.horizontal, 14).modifier(PaperSurface(artwork: "CoastalPaper", radius: 20))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 0) {
                            Button {
                                restoreMessage = nil
                                Task { await membership.restore(); restoreMessage = membership.message }
                            } label: { settingRow("Restore purchases") }.buttonStyle(.plain).disabled(membership.loading)
                            NavigationLink { LegalDocumentView(document: .privacy, l: l) } label: { settingRow("Privacy policy") }.buttonStyle(.plain)
                            NavigationLink { LegalDocumentView(document: .terms, l: l) } label: { settingRow("Terms of use") }.buttonStyle(.plain)
                        }.padding(.horizontal, 14).modifier(PaperSurface(artwork: "CoastalPaper", radius: 20))
                    }
                    if let restoreMessage {
                        Text(l.text(restoreMessage)).font(.footnote).foregroundColor(Palette.muted)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showLanguages.toggle() } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(l.text("Language")).font(.system(.headline, design: .serif))
                                    Text(options.first { $0.0 == language }?.1 ?? "English")
                                        .font(.subheadline).foregroundColor(Palette.muted)
                                }
                                Spacer(minLength: 8)
                                Image("NextMark").resizable().scaledToFit().frame(width: 30, height: 30)
                                    .rotationEffect(.degrees(showLanguages ? 90 : 0)).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(14)
                                .modifier(PaperSurface(artwork: "CoastalPaper", radius: 18))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(l.text(showLanguages ? "Close" : "More options"))
                        if showLanguages {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                                ForEach(options, id: \.0) { option in
                                    Button { language = option.0; showLanguages = false } label: {
                                        HStack(spacing: 6) {
                                            Text(option.1).font(.subheadline)
                                            Spacer(minLength: 2)
                                            if language == option.0 { Image("FlatCheckOn").resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true) }
                                        }.padding(.horizontal, 12).frame(minHeight: 48)
                                            .modifier(PaperSurface(artwork: language == option.0 ? "ButtonSelected" : "ButtonPaper", radius: 14))
                                    }.buttonStyle(.plain).accessibilityValue(language == option.0 ? l.text("Selected") : l.text("Not selected"))
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28).frame(maxWidth: 720)
                    .background(Palette.paper)
            }.frame(maxWidth: .infinity)
        }.ignoresSafeArea(.container, edges: .top)
            .sheet(item: $exportFile) { ShareSheet(file: $0.url) }
    }
    private func collectionCount(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)").font(.system(.title3, design: .serif)).monospacedDigit()
            Text(label).font(.footnote).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private func settingRow(_ title: String, artwork: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let artwork { Image(artwork).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true) }
            Text(l.text(title)).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image("NextMark").resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
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
                BackTagButton(label: l.text("Back")) { dismiss() }
                EditorialBanner(artwork: "PackingEditorial", height: 170)
                ForEach($draft) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(l.text("Item name"), text: $item.name).modifier(FieldStyle())
                            .onChange(of: item.name) { _ in item.suggestedNameKey = nil }
                        TextField(l.text("Category"), text: $item.category).modifier(FieldStyle())
                            .onChange(of: item.category) { _ in item.suggestedCategoryKey = nil }
                        Button(l.text("Delete")) { draft.removeAll { $0.id == item.id } }.buttonStyle(SecondaryButton())
                    }.padding(14).modifier(SatchelGlass(tint: Palette.cream.opacity(0.3), cornerRadius: 18))
                }
                VStack(alignment: .leading, spacing: 12) {
                    TextField(l.text("Item name"), text: $name).modifier(FieldStyle())
                    TextField(l.text("Category"), text: $category).modifier(FieldStyle())
                    Button(l.text("Add item")) {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), c = category.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !n.isEmpty && !c.isEmpty { draft.append(PackingItem(name: n, category: c)); name = ""; category = "" }
                    }.buttonStyle(SecondaryButton())
                }.padding(16).modifier(SatchelGlass(tint: Palette.seaTint.opacity(0.24), cornerRadius: 20))
                Button { if store.saveTemplate(draft.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { dismiss() } } label: {
                    Text(l.text("Save")).frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButton())
            }.padding(20).padding(.bottom, 28).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar).onAppear {
            draft = store.template.map { var item = $0; item.name = item.suggestedNameKey.map(l.text) ?? item.name; item.category = item.suggestedCategoryKey.map(l.text) ?? item.category; return item }
        }
    }
}
