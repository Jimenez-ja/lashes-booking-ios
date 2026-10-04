import SwiftUI
import PhotosUI
import UIKit

struct BusinessPhotoPreview: View {
    let image: BusinessImage?
    var body: some View {
        Group {
            if let encoded = image?.base64, let data = Data(base64Encoded: encoded), let photo = UIImage(data: data) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else if let raw = image?.url, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let photo = phase.image { photo.resizable().scaledToFill() }
                    else { placeholder }
                }
            } else { placeholder }
        }
        .frame(maxWidth: .infinity).frame(height: 130)
        .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private var placeholder: some View {
        ZStack { LoginStyle.cream; Image(systemName: "photo").font(.largeTitle).foregroundStyle(LoginStyle.muted) }
    }
}

struct BusinessPhotoField: View {
    let title: String
    @Binding var image: BusinessImage?
    @Binding var isImporting: Bool
    @State private var selected: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BusinessPhotoPreview(image: image).accessibilityLabel(title)
            PhotosPicker(selection: $selected, matching: .images) {
                Label(isImporting ? "Procesando foto…" : "Elegir \(title.lowercased())", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered).disabled(isImporting)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .onChange(of: selected) { _, item in
            guard let item else { return }
            isImporting = true; error = nil
            Task {
                defer { isImporting = false; selected = nil }
                do { image = try await importedPhoto(item) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct ServicePhotosField: View {
    @Binding var images: [BusinessImage]
    @Binding var isImporting: Bool
    @State private var selection: [PhotosPickerItem] = []
    @State private var error: String?
    private var active: [BusinessImage] { images.filter(\.isPresent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entre 1 y 5 fotos. Se mostrarán en el perfil de tu negocio.")
                .font(.footnote).foregroundStyle(LoginStyle.muted)
            ForEach(active) { image in
                HStack(alignment: .top) {
                    BusinessPhotoPreview(image: image)
                    Button(role: .destructive) {
                        guard let index = images.firstIndex(where: { $0.id == image.id }) else { return }
                        if images[index].fileId != nil { images[index].deleted = true }
                        else { images.remove(at: index) }
                    } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Quitar foto")
                }
            }
            if active.count < 5 {
                PhotosPicker(selection: $selection, maxSelectionCount: 5 - active.count, matching: .images) {
                    Label(isImporting ? "Procesando fotos…" : "Agregar fotos", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered).disabled(isImporting)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .disabled(isImporting)
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            isImporting = true; error = nil
            Task {
                defer { isImporting = false; selection = [] }
                do {
                    var imported: [BusinessImage] = []
                    for item in items { imported.append(try await importedPhoto(item)) }
                    guard active.count + imported.count <= 5 else { throw AuthError.message("Puedes agregar hasta 5 fotos.") }
                    images.append(contentsOf: imported)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
private func importedPhoto(_ item: PhotosPickerItem) async throws -> BusinessImage {
    guard let data = try await item.loadTransferable(type: Data.self), let source = UIImage(data: data) else {
        throw AuthError.message("No se pudo leer la foto. Elige otra imagen.")
    }
    let ratio = min(1, 1600 / max(source.size.width, source.size.height))
    let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
        source.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let jpeg = resized.jpegData(compressionQuality: 0.75), jpeg.count < 1_500_000 else {
        throw AuthError.message("La foto es demasiado grande. Elige una imagen más pequeña.")
    }
    return BusinessImage(name: "photo-\(UUID().uuidString).jpg", base64: jpeg.base64EncodedString(), isNew: true)
}
