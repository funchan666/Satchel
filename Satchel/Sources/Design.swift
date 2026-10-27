import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// Satchel's surfaces are ordinary layout; artwork comes from the asset catalog.
enum Palette {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let muted = Color(red: 0.46, green: 0.40, blue: 0.34)
    static let rust = Color(red: 0.65, green: 0.31, blue: 0.22)
    static let olive = Color(red: 0.40, green: 0.45, blue: 0.34)
    static let cream = Color(red: 1, green: 0.985, blue: 0.95)
}
struct Page: ViewModifier {
    func body(content: Content) -> some View { content.foregroundColor(Palette.ink).background(Palette.paper.ignoresSafeArea()) }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 14).background(Palette.rust.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold)).foregroundColor(Palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 12).background(Palette.cream.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View { content.padding(13).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10)) }
}
struct EditorialTitle: View {
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 32, weight: .regular, design: .serif))
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundColor(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct PhotoView: View {
    @EnvironmentObject var store: TravelStore
    let name: String?
    var body: some View {
        GeometryReader { geometry in
            Group { if let image = store.image(name) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image("TravelCover").resizable().scaledToFill() } }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
struct PhotoSelector: View {
    @EnvironmentObject private var store: TravelStore
    let label: String
    var cameraLabel: String = "Camera"
    var cameraError: String = "Camera access is unavailable. Check your device settings."
    var onData: (Data) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var cameraUnavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            PhotosPicker(selection: $selection, matching: .images) { Text(label) }.buttonStyle(SecondaryButton())
            if UIImagePickerController.isSourceTypeAvailable(.camera) { Button(cameraLabel) { requestCamera() }.buttonStyle(SecondaryButton()) }
          }
          if cameraUnavailable { Text(cameraError).font(.footnote).foregroundColor(Palette.rust) }
        }.sheet(isPresented: $camera) { CameraCapture(onData: onData) }
            .onChange(of: selection) { item in
                guard let item else { return }
                Task {
                    do { if let data = try await item.loadTransferable(type: Data.self) { onData(data) } else { store.error = "Could not load the photo. Please try again." } }
                    catch { store.error = "Could not load the photo. Please try again." }
                    selection = nil
                }
            }
    }
    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = true
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { allowed in DispatchQueue.main.async { if allowed { camera = true } else { cameraUnavailable = true } } }
        default: cameraUnavailable = true
        }
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onData: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onData(data) }
            parent.dismiss()
        }
    }
}

struct ErrorNotice: View {
    @EnvironmentObject private var store: TravelStore
    let l: L10n
    var body: some View {
        if let message = store.error {
            HStack { Text(l.text(message)).font(.footnote); Spacer(); Button("OK") { store.error = nil }.buttonStyle(SecondaryButton()) }
                .padding(12).background(Palette.cream, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
