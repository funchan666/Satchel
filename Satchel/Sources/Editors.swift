import SwiftUI
import PhotosUI
import UIKit

private let dateTimeFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; f.isLenient = false; return f
}()
private let dateFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
}()
struct NewTripView: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) var dismiss
    let l: L10n
    @State private var destination = ""
    @State private var startText = dateFormatter.string(from: Date())
    @State private var endText = dateFormatter.string(from: Date())
    @State private var kind: TravelKind = .leisure
    @State private var copyID: UUID?
    @State private var useTemplate = false
    @State private var coverData: Data?
    @State private var validation = false
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ErrorNotice(l: l)
                    HStack(spacing: 12) {
                        BackTagButton(label: l.text("Back")) { dismiss() }
                        Text(l.text("Create trip")).font(.system(.title3, design: .serif))
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(l.text("Cover photo")).font(.headline)
                            Spacer()
                            Text(l.text("Optional")).font(.subheadline).foregroundColor(Palette.muted)
                        }
                        if let coverData, let image = UIImage(data: coverData) {
                            GeometryReader { geometry in
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            }.frame(height: 165).clipShape(RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel(l.text("Cover photo"))
                        } else {
                            ZStack(alignment: .leading) {
                                GeometryReader { geometry in
                                    Image("CoverPaperV2").resizable().scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                }.accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(l.text("No cover photo yet"))
                                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                    Text(l.text("Add one whenever you like."))
                                        .font(.footnote).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: 180, alignment: .leading).padding(16)
                            }.frame(minHeight: 125).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        PhotoSelector(label: l.text(coverData == nil ? "Add photo" : "Change cover"), cameraLabel: l.text("Camera"), cameraError: l.text("Camera access is unavailable. Check your device settings.")) { data in
                            guard UIImage(data: data) != nil else { store.error = "Could not load the photo. Please try again."; return }
                            coverData = data
                        }
                        if coverData != nil {
                            Button(l.text("Remove cover")) { coverData = nil }.buttonStyle(SecondaryButton())
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        field(l.text("Destination"), text: $destination)
                        field(l.text("Start date") + " · YYYY-MM-DD", text: $startText)
                        field(l.text("End date") + " · YYYY-MM-DD", text: $endText)
                    }.padding(14).modifier(SatchelGlass(tint: Palette.cream.opacity(0.25), cornerRadius: 18))
                    Text(l.text("Trip type")).font(.system(.headline, design: .serif))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TravelKind.allCases, id: \.self) { value in
                                ChoiceButton(title: l.text(value.rawValue.capitalized), selected: kind == value, selectedLabel: l.text("Selected"), unselectedLabel: l.text("Not selected")) { kind = value }
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    if !store.trips.isEmpty {
                        Text(l.text("Copy a previous list")).font(.system(.headline, design: .serif))
                        ChoiceButton(title: l.text("Suggested list"), selected: copyID == nil && !useTemplate, selectedLabel: l.text("Selected"), unselectedLabel: l.text("Not selected")) { copyID = nil; useTemplate = false }
                        ForEach(store.trips) { trip in
                            ChoiceButton(title: trip.destination, selected: copyID == trip.id, selectedLabel: l.text("Selected"), unselectedLabel: l.text("Not selected")) { copyID = trip.id; useTemplate = false }
                        }
                    }
                    if !store.template.isEmpty { ChoiceButton(title: l.text("Common list"), selected: useTemplate, selectedLabel: l.text("Selected"), unselectedLabel: l.text("Not selected")) { copyID = nil; useTemplate = true } }
                    if validation { Text(l.text("Please check the destination and dates.")).foregroundColor(Palette.rust).font(.footnote) }
                    Button { create() } label: { AddActionLabel(title: l.text("Create trip")).frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                }.padding(20).padding(.bottom, 28).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar)
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(Palette.muted)
            TextField(title, text: text).font(.subheadline).modifier(FieldStyle())
        }
    }
    private func create() {
        guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = dateFormatter.date(from: startText), dateFormatter.string(from: start) == startText,
              let end = dateFormatter.date(from: endText), dateFormatter.string(from: end) == endText, end >= start else { validation = true; return }
        let days = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        var trip = Trip(destination: destination.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end, kind: kind.rawValue)
        if useTemplate { trip.items = store.template.map { var item = $0; item.id = UUID(); item.packed = false; item.returned = false; return item } }
        else if let source = store.trips.first(where: { $0.id == copyID }) {
            trip.items = source.items.map { var item = $0; item.id = UUID(); item.packed = false; item.returned = false; return item }
            trip.lessons = source.lessons
        } else { trip.items = suggestedItems(kind: kind, days: days, l: l) }
        if let coverData { guard let name = store.savePhoto(coverData) else { return }; trip.cover = name }
        if store.update(trip) { dismiss() } else if let cover = trip.cover { store.removeUnusedPhotos([cover]) }
    }
}
struct ItemEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) var dismiss
    let l: L10n
    let tripID: UUID
    let existing: PackingItem?
    @State private var name = ""
    @State private var category = ""
    @State private var quantity = 1
    @State private var location = ""
    @State private var notes = ""
    @State private var needsReturn = true
    @State private var photo: String?
    @State private var invalid = false
    @State private var confirmingItemDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                ErrorNotice(l: l)
                BackTagButton(label: l.text("Back")) { if let photo { store.removeUnusedPhotos([photo]) }; dismiss() }
                EditorialBanner(artwork: "PackingEditorial")
                VStack(alignment: .leading, spacing: 14) { input("Item name", $name); input("Category", $category) }
                    .padding(14).modifier(SatchelGlass(tint: Palette.cream.opacity(0.2), cornerRadius: 18))
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(l.text("Quantity")); Spacer()
                        Button(l.text("Less")) { quantity = max(1, quantity - 1) }.buttonStyle(SecondaryButton())
                        Text("\(quantity)").monospacedDigit().frame(minWidth: 32)
                        Button(l.text("More")) { quantity = min(999, quantity + 1) }.buttonStyle(SecondaryButton())
                    }
                    input("Where is it?", $location)
                    input("Notes", $notes)
                }.padding(14).modifier(SatchelGlass(tint: Palette.cream.opacity(0.25), cornerRadius: 18))
                Button { needsReturn.toggle() } label: { HStack { Text(l.text("Bring back")); Spacer(); Image(needsReturn ? "FlatCheckOn" : "FlatCheckOff").resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true) } }.buttonStyle(SecondaryButton()).accessibilityValue(needsReturn ? l.text("Selected") : l.text("Not selected"))
                PhotoSelector(label: l.text("Add photo"), cameraLabel: l.text("Camera"), cameraError: l.text("Camera access is unavailable. Check your device settings.")) { data in
                    if let name = store.savePhoto(data) {
                        if let old = photo { store.removeUnusedPhotos([old]) }
                        photo = name
                    }
                }
                if let image = store.image(photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12)) }
                if invalid { Text(l.text("Please enter a name and category.")).foregroundColor(Palette.rust).font(.footnote) }
                HStack { Button(l.text("Cancel")) { if let photo { store.removeUnusedPhotos([photo]) }; dismiss() }.buttonStyle(SecondaryButton()); Button { save() } label: { ButtonArtworkLabel(title: l.text("Save"), artwork: "ActionSave") }.buttonStyle(PrimaryButton()) }
                if existing != nil {
                    if confirmingItemDelete { HStack { Button(l.text("Cancel")) { confirmingItemDelete = false }.buttonStyle(SecondaryButton()); Button { remove() } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) } }
                    else { Button { confirmingItemDelete = true } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) }
                }
            }.padding(20).padding(.bottom, 28).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar).onAppear {
            if let item = existing { name = item.suggestedNameKey.map(l.text) ?? item.name; category = item.suggestedCategoryKey.map(l.text) ?? item.category; quantity = item.quantity; location = item.location; notes = item.notes; needsReturn = item.needsReturn; photo = item.photo }
        }
    }
    private func input(_ title: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(l.text(title)).font(.subheadline.weight(.semibold)); TextField(l.text(title), text: value).modifier(FieldStyle()) }
    }
    private func save() {
        guard let index = store.trips.firstIndex(where: { $0.id == tripID }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), c = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty && !c.isEmpty else { invalid = true; return }
        var trip = store.trips[index]; var item = existing ?? PackingItem(name: n, category: c)
        if n != (item.suggestedNameKey.map(l.text) ?? item.name) { item.suggestedNameKey = nil }; if c != (item.suggestedCategoryKey.map(l.text) ?? item.category) { item.suggestedCategoryKey = nil }; item.name = n; item.category = c; item.quantity = quantity; item.location = location; item.notes = notes; item.needsReturn = needsReturn; item.photo = photo
        if let i = trip.items.firstIndex(where: { $0.id == item.id }) { trip.items[i] = item } else { trip.items.append(item) }
        if store.update(trip) { if let old = existing?.photo { store.removeUnusedPhotos([old]) }; dismiss() }
    }
    private func remove() {
        guard var trip = store.trips.first(where: { $0.id == tripID }), let existing else { return }
        trip.items.removeAll { $0.id == existing.id }; if store.update(trip) { if let old = existing.photo { store.removeUnusedPhotos([old]) }; dismiss() }
    }
}
struct EntryEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) var dismiss
    let l: L10n
    let tripID: UUID
    let existing: JournalEntry?
    @State private var text = ""
    @State private var date = Date()
    @State private var dateText = dateTimeFormatter.string(from: Date())
    @State private var invalidDate = false
    @State private var photos: [String] = []
    @State private var confirmingDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                ErrorNotice(l: l)
                BackTagButton(label: l.text("Back")) { store.removeUnusedPhotos(Set(photos)); dismiss() }
                EditorialBanner(artwork: "JournalEditorial")
                VStack(alignment: .leading, spacing: 12) {
                    Text(l.text("Date")).font(.headline)
                    TextField("YYYY-MM-DD HH:mm", text: $dateText).modifier(FieldStyle())
                    if invalidDate { Text(l.text("Please check the date and time.")).foregroundColor(Palette.rust).font(.footnote) }
                    TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 160).padding(8).background(Palette.cream.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text(l.text("Write a little something...")).foregroundColor(Palette.muted).padding(.horizontal, 14).padding(.top, 16).allowsHitTesting(false) }
                        }.accessibilityLabel(l.text("Write a little something..."))
                }.padding(16).modifier(SatchelGlass(tint: Palette.cream.opacity(0.25), cornerRadius: 20))
                PhotoSelector(label: l.text("Add photo"), cameraLabel: l.text("Camera"), cameraError: l.text("Camera access is unavailable. Check your device settings.")) { data in if let name = store.savePhoto(data) { photos.append(name) } }
                ForEach(photos, id: \.self) { photo in
                    HStack { if let image = store.image(photo) { Image(uiImage: image).resizable().scaledToFill().frame(width: 90, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 10)) }
                        Button { photos.removeAll { $0 == photo }; store.removeUnusedPhotos([photo]) } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) }
                }
                HStack { Button(l.text("Cancel")) { store.removeUnusedPhotos(Set(photos)); dismiss() }.buttonStyle(SecondaryButton()); Button { save() } label: { ButtonArtworkLabel(title: l.text("Save"), artwork: "ActionSave") }.buttonStyle(PrimaryButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty) }
                if existing != nil {
                    if confirmingDelete { HStack { Button(l.text("Cancel")) { confirmingDelete = false }.buttonStyle(SecondaryButton()); Button { remove() } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) } }
                    else { Button { confirmingDelete = true } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) }
                }
            }.padding(20).padding(.bottom, 28).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar).onAppear { if let entry = existing { text = entry.text; date = entry.date; dateText = dateTimeFormatter.string(from: entry.date); photos = entry.photos } }
    }
    private func save() {
        guard var trip = store.trips.first(where: { $0.id == tripID }) else { return }
        guard let parsedDate = dateTimeFormatter.date(from: dateText), dateTimeFormatter.string(from: parsedDate) == dateText else { invalidDate = true; return }
        var entry = existing ?? JournalEntry(); entry.text = text; entry.date = parsedDate; entry.photos = photos
        if let i = trip.entries.firstIndex(where: { $0.id == entry.id }) { trip.entries[i] = entry } else { trip.entries.append(entry) }
        if store.update(trip) { store.removeUnusedPhotos(Set(existing?.photos ?? [])); dismiss() }
    }
    private func remove() {
        guard var trip = store.trips.first(where: { $0.id == tripID }), let existing else { return }
        trip.entries.removeAll { $0.id == existing.id }; if store.update(trip) { store.removeUnusedPhotos(Set(existing.photos)); dismiss() }
    }
}

struct TripEditor: View {
    @EnvironmentObject var store: TravelStore
    @Environment(\.dismiss) var dismiss
    let l: L10n
    let tripID: UUID
    @State private var destination = ""
    @State private var start = ""
    @State private var end = ""
    @State private var invalid = false
    @State private var deleting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ErrorNotice(l: l)
                BackTagButton(label: l.text("Back")) { dismiss() }
                EditorialBanner(artwork: "SeaJourneyHero")
                VStack(alignment: .leading, spacing: 14) {
                    labelField("Destination", $destination)
                    labelField("Start date", $start)
                    labelField("End date", $end)
                    Text("YYYY-MM-DD").font(.caption).foregroundColor(Palette.muted)
                }.padding(16).modifier(SatchelGlass(tint: Palette.cream.opacity(0.25), cornerRadius: 20))
                if invalid { Text(l.text("Please check the destination and dates.")).foregroundColor(Palette.rust) }
                HStack { Button(l.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButton()); Button { save() } label: { ButtonArtworkLabel(title: l.text("Save"), artwork: "ActionSave") }.buttonStyle(PrimaryButton()) }
                if deleting {
                    Text(l.text("Delete this trip and its records?"))
                    HStack { Button(l.text("Cancel")) { deleting = false }.buttonStyle(SecondaryButton()); Button { delete() } label: { ButtonArtworkLabel(title: l.text("Delete"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) }
                } else { Button { deleting = true } label: { ButtonArtworkLabel(title: l.text("Delete trip"), artwork: "ActionDelete") }.buttonStyle(DangerButton()) }
            }.padding(20).padding(.bottom, 28).frame(maxWidth: 700)
        }.modifier(Page()).toolbar(.hidden, for: .navigationBar).onAppear {
            if let trip = store.trips.first(where: { $0.id == tripID }) { destination = trip.destination; start = dateFormatter.string(from: trip.start); end = dateFormatter.string(from: trip.end) }
        }
    }
    private func labelField(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(l.text(label)); TextField(l.text(label), text: value).modifier(FieldStyle()) }
    }
    private func save() {
        let name = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let first = dateFormatter.date(from: start), dateFormatter.string(from: first) == start,
              let last = dateFormatter.date(from: end), dateFormatter.string(from: last) == end, last >= first,
              var trip = store.trips.first(where: { $0.id == tripID }) else { invalid = true; return }
        trip.destination = name; trip.start = first; trip.end = last
        if store.update(trip) { dismiss() }
    }
    private func delete() { let old = store.referencedPhotos(in: store.trips.filter { $0.id == tripID }); if store.save(store.trips.filter { $0.id != tripID }) { store.removeUnusedPhotos(old); dismiss() } }
}
