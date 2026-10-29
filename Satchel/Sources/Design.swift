import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// Satchel's surfaces are ordinary layout; artwork comes from the asset catalog.
enum Palette {
    static let paper = Color(red: 0.97, green: 0.975, blue: 0.96)
    static let cream = Color(red: 1.0, green: 0.99, blue: 0.96)
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.27)
    static let muted = Color(red: 0.35, green: 0.42, blue: 0.46)
    static let ocean = Color(red: 0.03, green: 0.28, blue: 0.64)
    static let seaTint = Color(red: 0.83, green: 0.91, blue: 0.97)
    static let rust = Color(red: 0.65, green: 0.28, blue: 0.18)
    static let olive = Color(red: 0.31, green: 0.43, blue: 0.37)
}
struct Page: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.subheadline).foregroundColor(Palette.ink)
            .background {
                ZStack {
                    Palette.paper
                    GeometryReader { geometry in
                        Image("PageLinen").resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .opacity(0.18).accessibilityHidden(true)
                    }
                }.ignoresSafeArea(.container)
            }
    }
}
struct BackTagButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image("BackTag").resizable().scaledToFit().frame(width: 72, height: 48)
                .frame(minWidth: 72, minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
/// Raster artwork supplies the surface; the rounded clip only defines its hit-area silhouette.
struct PaperSurface: ViewModifier {
    let artwork: String
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Image(artwork).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundColor(.white)
            .multilineTextAlignment(.center).padding(.horizontal, 22).padding(.vertical, 13)
            .frame(minHeight: 50).modifier(PaperSurface(artwork: "ButtonOcean", radius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .opacity(isEnabled ? 1 : 0.55)
    }
}
struct TabPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(.white).multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 48)
            .modifier(PaperSurface(artwork: "TabAction", radius: 15))
            .opacity(configuration.isPressed ? 0.8 : 1).opacity(isEnabled ? 1 : 0.55)
    }
}

/// A small, original mark makes creation actions recognizable without extra explanatory copy.
struct AddActionLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image("AddMark").resizable().scaledToFit().frame(width: 19, height: 19).accessibilityHidden(true)
            Text(title).multilineTextAlignment(.leading)
        }.accessibilityElement(children: .combine)
    }
}
struct SecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundColor(Palette.ink)
            .multilineTextAlignment(.center).padding(.horizontal, 17).padding(.vertical, 12)
            .frame(minHeight: 48).modifier(PaperSurface(artwork: "ButtonPaper", radius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.55)
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.subheadline).padding(.horizontal, 15).padding(.vertical, 13).frame(minHeight: 48)
            .modifier(PaperSurface(artwork: "ButtonPaper", radius: 14))
    }
}
// The picture can extend beneath system chrome; controls are placed below it.
struct TabHero: View {
    let artwork: String
    var height: CGFloat = 250
    var body: some View {
        GeometryReader { geometry in
            Image(artwork).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped().accessibilityHidden(true)
        }.frame(height: height).frame(maxWidth: .infinity)
    }
}

struct EditorialBanner: View {
    let artwork: String
    var height: CGFloat = 110
    var body: some View {
        GeometryReader { geometry in
            Image(artwork).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().accessibilityHidden(true)
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
struct PhotoView: View {
    @EnvironmentObject var store: TravelStore
    let name: String?
    var body: some View {
        GeometryReader { geometry in
            Group { if let image = store.image(name) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image("CoverPaperV2").resizable().scaledToFill().accessibilityHidden(true) } }
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
          HStack(spacing: 10) {
            PhotosPicker(selection: $selection, matching: .images) { Text(label).frame(maxWidth: .infinity) }.buttonStyle(SecondaryButton())
            if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { requestCamera() } label: { Text(cameraLabel).frame(maxWidth: .infinity) }.buttonStyle(SecondaryButton()) }
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

struct ChoiceButton: View {
    let title: String
    let selected: Bool
    let selectedLabel: String
    let unselectedLabel: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image("FlatCheckOn").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true) }
                Text(title).font(.subheadline.weight(selected ? .bold : .semibold))
            }.foregroundColor(Palette.ink)
                .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 48)
                .modifier(PaperSurface(artwork: selected ? "ButtonSelected" : "ButtonPaper", radius: 14))
        }.buttonStyle(.plain).accessibilityValue(selected ? selectedLabel : unselectedLabel)
    }
}

/// Keeps Satchel's warm palette while using system Liquid Glass where available.
struct SatchelGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color? = nil
    var interactive = false
    var cornerRadius: CGFloat = 16
    var fallback = Palette.cream

    init(tint: Color? = nil, interactive: Bool = false, cornerRadius: CGFloat = 16, fallback: Color = Palette.cream) {
        self.tint = tint; self.interactive = interactive; self.cornerRadius = cornerRadius; self.fallback = fallback
    }

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(fallback, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
                    .environment(\.colorScheme, .light)
            } else {
                content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .background(fallback.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius))
            }
            #else
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .background(fallback.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius))
            #endif
        }
    }
}

struct SatchelGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 8) { content }
        } else { content }
        #else
        content
        #endif
    }
}
