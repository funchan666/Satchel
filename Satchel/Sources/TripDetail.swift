import SwiftUI

struct TripDetail: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tripID: UUID
    let l: L10n
    var initialSection = 0
    @State private var section: Int
    @State private var returning = false
    @State private var showItem = false
    @State private var editingItem: PackingItem?
    @State private var showEntry = false
    @State private var editingEntry: JournalEntry?
    @State private var templateSaved = false
    @State private var editingPhoto = false
    @State private var selectedPhoto = ""
    @State private var confirmPhotoDeletion = false
    @State private var photoNote = ""
    @State private var editingTrip = false
    @State private var editingLessons = false
    @State private var lessonDraft = ""
    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    init(tripID: UUID, l: L10n, initialSection: Int = 0) {
        self.tripID = tripID; self.l = l; self.initialSection = initialSection
        _section = State(initialValue: initialSection)
    }
    var body: some View {
        Group {
            if let trip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack { Button(l.text("Trips")) { dismiss() }.buttonStyle(SecondaryButton()); Spacer(); Button(l.text("Edit trip")) { editingTrip = true }.buttonStyle(SecondaryButton()) }
                        ZStack(alignment: .bottomLeading) {
                            PhotoView(name: trip.cover).frame(height: 235).frame(maxWidth: .infinity).clipped()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(trip.destination).font(.system(size: 30, design: .serif))
                                Text(trip.start.formatted(date: .abbreviated, time: .omitted) + " — " + trip.end.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                            }.padding(14).background(Palette.cream.opacity(0.95), in: RoundedRectangle(cornerRadius: 12)).padding(14)
                        }.clipShape(RoundedRectangle(cornerRadius: 18))
                        PhotoSelector(label: l.text("Change cover"), cameraLabel: l.text("Camera"), cameraError: l.text("Camera access is unavailable. Check your device settings.")) { data in
                            if let name = store.savePhoto(data), var updated = self.trip { let previous = updated.cover; updated.cover = name; if store.update(updated) { if let previous { store.removeUnusedPhotos([previous]) } } else { store.removeUnusedPhotos([name]) } }
                        }
                        HStack {
                            sectionButton("Packing", index: 0)
                            sectionButton("Journal", index: 1)
                        }
                        if section == 0 { packing(trip) } else { journal(trip) }
                    }.padding(20).frame(maxWidth: 720)
                }
            } else { Text(l.text("Trips")) }
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showItem) { ItemEditor(l: l, tripID: tripID, existing: editingItem) }
            .sheet(isPresented: $showEntry) { EntryEditor(l: l, tripID: tripID, existing: editingEntry) }
            .sheet(isPresented: $editingLessons) { lessonEditor }
            .sheet(isPresented: $editingTrip) { TripEditor(l: l, tripID: tripID) }
            .sheet(isPresented: $editingPhoto) { packingPhotoEditor }
    }
    private func sectionButton(_ title: String, index: Int) -> some View {
        Button { if reduceMotion { section = index } else { withAnimation(.easeInOut(duration: 0.18)) { section = index } } } label: {
            Text(l.text(title)).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).foregroundColor(section == index ? .white : Palette.ink).background(section == index ? Palette.olive : Palette.cream, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func packing(_ trip: Trip) -> some View {
        let relevant = returning ? trip.items.filter(\.needsReturn) : trip.items
        let complete = relevant.filter { returning ? $0.returned : $0.packed }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(l.text("Packing")) { returning = false }.buttonStyle(SecondaryButton()).opacity(returning ? 0.55 : 1)
                Button(l.text("Returning")) { returning = true }.buttonStyle(SecondaryButton()).opacity(returning ? 1 : 0.55)
                Spacer()
            }
            if !relevant.isEmpty { Text("\(complete) / \(relevant.count)").font(.system(size: 25, design: .serif)).foregroundColor(Palette.olive) }
            if trip.items.isEmpty {
                Image("PackingEmpty").resizable().scaledToFit().frame(maxWidth: 190).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            let categories = Array(Set(trip.items.map { $0.suggestedCategoryKey.map(l.text) ?? $0.category })).sorted()
            ForEach(categories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category).font(.system(size: 21, design: .serif)).padding(.top, 8)
                    ForEach(trip.items.filter { ($0.suggestedCategoryKey.map(l.text) ?? $0.category) == category }) { item in
                        HStack(spacing: 12) {
                            Button { toggle(item.id) } label: {
                                Image((returning ? item.returned : item.packed) ? "CheckOn" : "CheckOff").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).disabled(returning && !item.needsReturn).accessibilityLabel(item.suggestedNameKey.map(l.text) ?? item.name).accessibilityValue((returning ? item.returned : item.packed) ? l.text("Selected") : l.text("Not selected"))
                            Button { editingItem = item; showItem = true } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(item.suggestedNameKey.map(l.text) ?? item.name).font(.body.weight(.medium)); Spacer(); Text("× \(item.quantity)").foregroundColor(Palette.muted) }
                                    if !item.location.isEmpty { Text(item.location).font(.caption).foregroundColor(Palette.muted) }
                                    if returning && !item.needsReturn { Text(l.text("Not returning")).font(.caption).foregroundColor(Palette.muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }.padding(.horizontal, 8).padding(.vertical, 4).background(Palette.cream, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Button(l.text("Add item")) { editingItem = nil; showItem = true }.buttonStyle(PrimaryButton())
            if !trip.items.isEmpty { Button(l.text("Save as common list")) { templateSaved = store.saveTemplate(trip.items.map { var item = $0; item.id = UUID(); item.packed = false; item.returned = false; item.photo = nil; return item }) }.buttonStyle(SecondaryButton()); if templateSaved { Text(l.text("Common list saved")).font(.footnote).foregroundColor(Palette.olive) } }
            Image("TravelTicket").resizable().scaledToFit().frame(width: 100).accessibilityHidden(true)
            Text(l.text("Packing photos")).font(.system(size: 21, design: .serif)).padding(.top, 5)
            ScrollView(.horizontal) { HStack { ForEach(trip.packingPhotos, id: \.self) { name in
                if let image = store.image(name) { Button { selectedPhoto = name; photoNote = trip.packingPhotoNotes[name] ?? ""; confirmPhotoDeletion = false; editingPhoto = true } label: { Image(uiImage: image).resizable().scaledToFill().frame(width: 130, height: 105).clipped().clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
            } } }
            PhotoSelector(label: l.text("Add photo"), cameraLabel: l.text("Camera"), cameraError: l.text("Camera access is unavailable. Check your device settings.")) { data in if let name = store.savePhoto(data), var current = self.trip { current.packingPhotos.append(name); if !store.update(current) { store.removeUnusedPhotos([name]) } } }
            Button { lessonDraft = trip.lessons; editingLessons = true } label: {
                VStack(alignment: .leading, spacing: 8) { Text(l.text("Notes for next time")).font(.system(size: 21, design: .serif)); if !trip.lessons.isEmpty { Text(trip.lessons).font(.body).foregroundColor(Palette.muted) } }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.buttonStyle(.plain).background(Palette.cream, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    @ViewBuilder private func journal(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(l.text("Journal")).font(.system(size: 24, design: .serif)); Spacer(); Button(l.text("Add a memory")) { editingEntry = nil; showEntry = true }.buttonStyle(PrimaryButton()) }
            if trip.entries.isEmpty {
                Image("JournalEmpty").resizable().scaledToFit().frame(maxWidth: 230).frame(maxWidth: .infinity)
                Text(l.text("Your memories start here.")).font(.system(size: 20, design: .serif))
            }
            let grouped = Dictionary(grouping: trip.entries) { Calendar.current.startOfDay(for: $0.date) }
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: 12) {
                    Text(day.formatted(date: .long, time: .omitted)).font(.system(size: 20, design: .serif))
                    ForEach((grouped[day] ?? []).sorted { $0.date > $1.date }) { entry in
                        Button { editingEntry = entry; showEntry = true } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.semibold)).foregroundColor(Palette.rust)
                                ForEach(entry.photos, id: \.self) { name in
                                    if let image = store.image(name) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10)) }
                                }
                                if !entry.text.isEmpty { Text(entry.text).font(.body).frame(maxWidth: .infinity, alignment: .leading) }
                            }.padding(16).background(Palette.cream, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var packingPhotoEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ErrorNotice(l: l)
                EditorialTitle(title: l.text("Packing photos"))
                if let image = store.image(selectedPhoto) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                Text(l.text("Notes")).font(.headline)
                TextField(l.text("Notes"), text: $photoNote).modifier(FieldStyle())
                HStack {
                    Button(l.text("Cancel")) { editingPhoto = false }.buttonStyle(SecondaryButton())
                    Button(l.text("Save")) { if var current = trip { current.packingPhotoNotes[selectedPhoto] = photoNote; if store.update(current) { editingPhoto = false } } }.buttonStyle(PrimaryButton())
                    Button(l.text("Delete")) { confirmPhotoDeletion = true }.buttonStyle(SecondaryButton())
                }
                if confirmPhotoDeletion {
                    Text(l.text("Delete this photo?"))
                    HStack {
                        Button(l.text("Cancel")) { confirmPhotoDeletion = false }.buttonStyle(SecondaryButton())
                        Button(l.text("Delete")) { if var current = trip { current.packingPhotos.removeAll { $0 == selectedPhoto }; current.packingPhotoNotes.removeValue(forKey: selectedPhoto); if store.update(current) { store.removeUnusedPhotos([selectedPhoto]); editingPhoto = false } } }.buttonStyle(PrimaryButton())
                    }
                }
            }.padding(20).frame(maxWidth: 700)
        }.modifier(Page())
    }
    private var lessonEditor: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            ErrorNotice(l: l)
            EditorialTitle(title: l.text("Notes for next time"))
            TextEditor(text: $lessonDraft).scrollContentBackground(.hidden).frame(minHeight: 180).padding(8).background(Palette.cream, in: RoundedRectangle(cornerRadius: 12))
            HStack { Button(l.text("Cancel")) { editingLessons = false }.buttonStyle(SecondaryButton()); Button(l.text("Save")) { if var current = trip { current.lessons = lessonDraft; if store.update(current) { editingLessons = false } } }.buttonStyle(PrimaryButton()) }
        }.padding(20).frame(maxWidth: 700) }.modifier(Page())
    }
    private func toggle(_ id: UUID) {
        guard var current = trip, let i = current.items.firstIndex(where: { $0.id == id }) else { return }
        if returning { current.items[i].returned.toggle() } else { current.items[i].packed.toggle() }
        _ = store.update(current)
    }
}
