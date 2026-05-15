import SwiftUI
import PhotosUI
import UIKit

// Two thin UIViewControllerRepresentable wrappers — PHPicker for library,
// UIImagePickerController for camera. PHPicker doesn't support a live
// camera source, so we keep both. Callers present them via `.sheet`.

enum PhotoPickerSource {
    case camera, library
}

struct PhotoPicker: UIViewControllerRepresentable {
    let source: PhotoPickerSource
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .camera:
            // Camera availability isn't guaranteed (Simulator, iPads without a
            // camera). Fall through to the library picker if it isn't there.
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                return makeLibraryPicker(context: context)
            }
            let vc = UIImagePickerController()
            vc.sourceType = .camera
            vc.cameraCaptureMode = .photo
            vc.allowsEditing = false
            vc.delegate = context.coordinator
            return vc
        case .library:
            return makeLibraryPicker(context: context)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func makeLibraryPicker(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate,
                              UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker
        init(parent: PhotoPicker) { self.parent = parent }

        // PHPicker (library)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [parent] obj, _ in
                guard let image = obj as? UIImage else { return }
                DispatchQueue.main.async { parent.onPick(image) }
            }
        }

        // UIImagePickerController (camera)
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Presents a confirmation dialog with Camera / Library options, then
    /// the matching `PhotoPicker` sheet, calling `onPick` with the result.
    func photoPicker(isPresented: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoPickerModifier(isPresented: isPresented, onPick: onPick))
    }
}

private struct PhotoPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (UIImage) -> Void

    @State private var pickerSource: PhotoPickerSource? = nil

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add photo", isPresented: $isPresented, titleVisibility: .hidden) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo") { pickerSource = .camera }
                }
                Button("Choose from library") { pickerSource = .library }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: Binding(get: { pickerSource.map { PhotoPickerSourceItem(source: $0) } },
                                  set: { pickerSource = $0?.source })) { item in
                PhotoPicker(source: item.source) { image in
                    pickerSource = nil
                    onPick(image)
                }
                .ignoresSafeArea()
            }
    }
}

// `.sheet(item:)` needs an Identifiable. PhotoPickerSource is a plain enum;
// wrap it so SwiftUI is happy.
private struct PhotoPickerSourceItem: Identifiable {
    let source: PhotoPickerSource
    var id: String {
        switch source {
        case .camera:  return "camera"
        case .library: return "library"
        }
    }
}
