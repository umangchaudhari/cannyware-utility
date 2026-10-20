import SwiftUI
import PhotosUI

@MainActor @Observable
final class PhotosPDFModel {
    var selection: [PhotosPickerItem] = []
    var photos: [PDFPhoto] = []
    var output: DocumentOutput?
    var isLoading = false
    var isCreating = false
    var progress = ""
    var errorMessage: String?
    private let photoProcessor = PhotoProcessor()
    private let pdfProcessor = PDFProcessor()
    private var operationID = UUID()
    private var task: Task<Void, Never>?
    var isBusy: Bool { isLoading || isCreating }

    func loadSelection() async {
        guard !selection.isEmpty else { return }
        let items = selection
        let id = UUID()
        operationID = id
        isLoading = true
        output = nil
        defer { if operationID == id { isLoading = false } }
        do {
            var loaded: [PDFPhoto] = []
            for (index, item) in items.enumerated() {
                progress = "Loading photo \(index + 1) of \(items.count)…"
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.loadingFailed }
                try Task.checkCancellation()
                loaded.append(try await photoProcessor.preparePDFPhoto(data))
            }
            try Task.checkCancellation()
            guard operationID == id else { return }
            photos = loaded
            selection = []
        } catch is CancellationError {
        } catch {
            guard operationID == id else { return }
            errorMessage = error.localizedDescription
        }
    }

    func move(_ photo: PDFPhoto, by offset: Int) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }), photos.indices.contains(index + offset) else { return }
        photos.swapAt(index, index + offset)
        output = nil
    }

    func remove(_ photo: PDFPhoto) {
        photos.removeAll { $0.id == photo.id }
        output = nil
    }

    func create() {
        guard !isBusy, !photos.isEmpty else { return }
        let input = photos
        isCreating = true
        output = nil
        let id = UUID()
        operationID = id
        task = Task {
            defer { if operationID == id { isCreating = false } }
            do {
                let result = try await pdfProcessor.photosToPDF(input)
                try Task.checkCancellation()
                guard operationID == id else { return }
                output = result
            } catch is CancellationError {
            } catch {
                if operationID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancel() {
        task?.cancel()
        operationID = UUID()
        isCreating = false
        isLoading = false
    }
}
