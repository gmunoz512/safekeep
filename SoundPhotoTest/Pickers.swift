import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// PHPicker bound to the shared library so results carry an assetIdentifier when possible.
/// The system picker itself does not require full Photo Library access.
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (PHPickerResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            if let first = results.first { parent.onPick(first) }
        }
    }
}

/// Button + sheet used on the add screens and in the share/Messages extensions.
struct ChooseFromPhotosButton: View {
    var disabled = false
    let onResult: (PHPickerResult) -> Void
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            Label("Choose from Photos", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(disabled)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(isPresented: $showPicker, onPick: onResult)
        }
    }
}

/// Document picker for audio files (copied into the app sandbox).
struct AudioDocPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    static var types: [UTType] {
        var t: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        let extra = ["com.apple.m4a-audio", "com.apple.coreaudio-format", "org.xiph.opus", "org.xiph.ogg-audio"]
        t += extra.compactMap { UTType($0) }
        t += ["opus", "ogg", "caf", "m4a", "amr", "flac"].compactMap { UTType(filenameExtension: $0) }
        return t
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: Self.types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioDocPicker
        init(_ p: AudioDocPicker) { parent = p }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            if let u = urls.first { parent.onPick(u) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
