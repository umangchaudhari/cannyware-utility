import SwiftUI
import PhotosUI

@MainActor
@Observable
final class CompressorModel {
    var selectedItem: PhotosPickerItem?
    var photo: ImportedPhoto?
    var result: CompressedPhoto?
    var targetText = "500"
    var isLoading = false
    var isCompressing = false
    var isSaving = false
    var didSave = false
    var errorMessage: String?
    var shareURL: URL?

    private let processor = PhotoProcessor()
    private var compressionTask: Task<Void, Never>?
    private var operationID = UUID()

    var target: TargetSize? { try? TargetSize(text: targetText, unit: .kb) }
    var isBusy: Bool { isLoading || isCompressing || isSaving }
    var canCompress: Bool { photo != nil && target != nil && !isBusy }

    func loadSelection() async {
        guard let item = selectedItem else { return }
        cancelCompression()
        let currentID = UUID()
        operationID = currentID
        isLoading = true
        defer { if operationID == currentID { isLoading = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.loadingFailed }
            try Task.checkCancellation()
            let imported = try await processor.inspect(data)
            try Task.checkCancellation()
            guard operationID == currentID else { return }
            clearResult()
            photo = imported
        } catch is CancellationError {
            // A newer selection superseded this request.
        } catch {
            guard !Task.isCancelled, operationID == currentID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func setPreset(_ bytes: Int) {
        targetText = String(bytes / 1_000)
        clearResult()
    }

    func clearResult() {
        result = nil
        didSave = false
        shareURL = nil
    }

    func compress() {
        guard canCompress, let photo, let target else { return }
        clearResult()
        isCompressing = true
        let currentID = UUID()
        operationID = currentID
        compressionTask = Task {
            defer { if operationID == currentID { isCompressing = false } }
            do {
                let output = try await processor.compress(photo, targetBytes: target.bytes)
                try Task.checkCancellation()
                guard operationID == currentID else { return }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CannywareUtilityExports", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Each result gets its own file, so a later compression cannot
                // replace a file that is still being shared by the system sheet.
                let url = folder.appendingPathComponent("Cannyware-Utility-\(output.id.uuidString.prefix(8)).jpg")
                try output.data.write(to: url, options: .atomic)
                result = output
                shareURL = url
            } catch is CancellationError {
            } catch {
                guard operationID == currentID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelCompression() {
        compressionTask?.cancel()
        isLoading = false
        operationID = UUID()
        isCompressing = false
    }

    func save() async {
        guard let result, !isSaving, !didSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibrarySaver.save(result.data)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func loadUITestPhoto() async {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting-photo") else { return }
        do { photo = try await processor.inspect(DemoPhoto.make()) }
        catch { errorMessage = error.localizedDescription }
    }
    #endif
}
