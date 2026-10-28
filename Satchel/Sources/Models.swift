import Foundation
import SwiftUI
import UIKit
import ImageIO

struct PackingItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var category: String
    var quantity: Int = 1
    var suggestedNameKey: String? = nil
    var suggestedCategoryKey: String? = nil
    var location: String = ""
    var notes: String = ""
    var photo: String? = nil
    var packed = false
    var returned = false
    var needsReturn = true
}
struct JournalEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text = ""
    var photos: [String] = []
}
struct Trip: Codable, Identifiable {
    var id = UUID()
    var destination: String
    var start: Date
    var end: Date
    var kind: String
    var cover: String? = nil
    var items: [PackingItem] = []
    var entries: [JournalEntry] = []
    var packingPhotos: [String] = []
    var packingPhotoNotes: [String: String] = [:]
    var lessons = ""
}

@MainActor final class TravelStore: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var error: String?
    @Published var template: [PackingItem] = []
    let membership = MembershipStore()
    private let folder: URL
    private let file: URL
    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 48 * 1024 * 1024; return cache
    }()
    private var canWrite = true
    var dataAvailable: Bool { canWrite }
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Satchel", isDirectory: true)
        folder = base; file = base.appendingPathComponent("trips.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { trips = try JSONDecoder().decode([Trip].self, from: Data(contentsOf: file)) }
            let templateFile = base.appendingPathComponent("template.json")
            if FileManager.default.fileExists(atPath: templateFile.path) { template = try JSONDecoder().decode([PackingItem].self, from: Data(contentsOf: templateFile)) }
        } catch { canWrite = false; self.error = "Could not open your travel journal. Your existing data has not been replaced." }
    }
    func save(_ updated: [Trip]) -> Bool {
        guard canWrite else { error = "Your journal could not be opened; saving is disabled to protect existing data."; return false }
        let oldPhotos = referencedPhotos(in: trips), newPhotos = referencedPhotos(in: updated)
        let addsTrip = updated.count > trips.count
        let addsPhoto = !newPhotos.subtracting(oldPhotos).isEmpty
        if addsTrip || addsPhoto {
            guard membership.entitlementsReady else { error = "Checking membership. Please try again in a moment."; return false }
            if !membership.isMember && addsTrip && updated.count > 3 { error = "The free plan includes up to 3 trips. Membership unlocks unlimited trips."; return false }
            if !membership.isMember && addsPhoto && newPhotos.count > 30 { error = "The free plan includes up to 30 photos. Membership unlocks unlimited photos."; return false }
        }
        do { try JSONEncoder().encode(updated).write(to: file, options: .atomic); trips = updated; return true }
        catch { self.error = "Could not save your changes. Please try again."; return false }
    }
    func saveTemplate(_ items: [PackingItem]) -> Bool {
        guard canWrite else { error = "Your journal could not be opened; saving is disabled to protect existing data."; return false }
        do { try JSONEncoder().encode(items).write(to: folder.appendingPathComponent("template.json"), options: .atomic); template = items; return true }
        catch { self.error = "Could not save your changes. Please try again."; return false }
    }
    func update(_ trip: Trip) -> Bool {
        var next = trips
        if let i = next.firstIndex(where: { $0.id == trip.id }) { next[i] = trip } else { next.append(trip) }
        return save(next)
    }
    func remove(_ id: UUID) { _ = save(trips.filter { $0.id != id }) }
    func savePhoto(_ data: Data) -> String? {
        guard canWrite else { error = "Your journal is unavailable; the photo was not saved."; return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: folder.appendingPathComponent(name), options: .atomic); return name }
        catch { self.error = "Could not save the photo. Please try again."; return nil }
    }
    func referencedPhotos(in trips: [Trip]) -> Set<String> {
        Set(trips.flatMap { trip in
            [trip.cover].compactMap { $0 } + trip.packingPhotos + trip.items.compactMap(\.photo) + trip.entries.flatMap(\.photos)
        })
    }
    func removeUnusedPhotos(_ candidates: Set<String>) {
        let referenced = referencedPhotos(in: trips).union(template.compactMap(\.photo))
        for name in candidates.subtracting(referenced) where !name.contains("/") && !name.contains("..") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            imageCache.removeObject(forKey: name as NSString)
        }
    }
    func photoData(_ name: String) -> Data? {
        guard !name.contains("/"), !name.contains("..") else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(name))
    }
    func image(_ name: String?) -> UIImage? {
        guard let name, !name.contains("/"), !name.contains("..") else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        let url = folder.appendingPathComponent(name) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        imageCache.setObject(image, forKey: name as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}

enum TravelKind: String, CaseIterable { case weekend, leisure, business }
func suggestedItems(kind: TravelKind, days: Int, l: L10n) -> [PackingItem] {
    var rows: [(String, String, Int)] = [("Clothes", "Tops", max(1, min(days, 7))), ("Clothes", "Underwear", max(1, min(days, 7))), ("Toiletries", "Toothbrush", 1), ("Toiletries", "Toiletries", 1), ("Electronics", "Phone charger", 1), ("Essentials", "ID and travel documents", 1)]
    if kind == .business { rows += [("Electronics", "Laptop", 1), ("Essentials", "Work materials", 1)] }
    return rows.map { PackingItem(name: $0.1, category: $0.0, quantity: $0.2, suggestedNameKey: $0.1, suggestedCategoryKey: $0.0) }
}
