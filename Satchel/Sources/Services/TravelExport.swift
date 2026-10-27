import Foundation
import SwiftUI
import UIKit

struct ExportFile: Identifiable { let id = UUID(); let url: URL }
extension TravelStore {
    func export() throws -> URL {
        guard dataAvailable else { throw CocoaError(.fileReadCorruptFile) }
        let names = referencedPhotos(in: trips).union(template.compactMap(\.photo)).sorted()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SatchelExports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Satchel-\(UUID().uuidString).json")
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        do {
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            let encoder = JSONEncoder()
            try output.write(contentsOf: Data("{\"formatVersion\":1,\"trips\":".utf8))
            try output.write(contentsOf: encoder.encode(trips))
            try output.write(contentsOf: Data(",\"commonList\":".utf8))
            try output.write(contentsOf: encoder.encode(template))
            try output.write(contentsOf: Data(",\"photos\":{ ".utf8))
            for (index, name) in names.enumerated() {
                guard let data = photoData(name) else { throw CocoaError(.fileReadNoSuchFile) }
                if index > 0 { try output.write(contentsOf: Data(",".utf8)) }
                try output.write(contentsOf: encoder.encode(name))
                try output.write(contentsOf: Data(":".utf8))
                try output.write(contentsOf: encoder.encode(data))
            }
            try output.write(contentsOf: Data("}}".utf8))
            return file
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: file) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
