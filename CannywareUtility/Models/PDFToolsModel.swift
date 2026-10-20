import SwiftUI

enum PDFToolMode {
    case photos, split
    var title: String { self == .photos ? "PDF to photos" : "Split PDF" }
    var action: String { self == .photos ? "Convert selected pages" : "Create PDF" }
}

@MainActor @Observable
final class PDFToolsModel {
    var pdf: ImportedPDF?
    var selectedPages: Set<Int> = []
    var documentOutput: DocumentOutput?
    var images: [PageImage] = []
    var isWorking = false
    var isSaving = false
    var didSave = false
    var progress = ""
    var errorMessage: String?
    let processor = PDFProcessor()
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    var isBusy: Bool { isWorking || isSaving }

    func importFile(_ url: URL, mode: PDFToolMode) {
        guard !isBusy else { return }
        isWorking = true
        progress = "Opening PDF…"
        let id = UUID()
        operationID = id
        task = Task {
            defer { if operationID == id { isWorking = false } }
            do {
                let imported = try await processor.importPDF(from: url)
                try Task.checkCancellation()
                guard operationID == id else { return }
                pdf = imported
                selectedPages = mode == .photos ? Set(0..<imported.pageCount) : []
                clearOutput()
            } catch is CancellationError {
            } catch {
                if operationID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    func toggle(_ index: Int) {
        if selectedPages.contains(index) { selectedPages.remove(index) }
        else { selectedPages.insert(index) }
        clearOutput()
    }

    func select(_ pages: Set<Int>) {
        selectedPages = pages
        clearOutput()
    }

    func create(mode: PDFToolMode) {
        guard !isBusy, let pdf, !selectedPages.isEmpty else { return }
        let pages = selectedPages.sorted()
        let id = UUID()
        operationID = id
        clearOutput()
        isWorking = true
        progress = mode == .photos ? "Converting pages…" : "Creating PDF…"
        task = Task {
            defer { if operationID == id { isWorking = false } }
            do {
                switch mode {
                case .split:
                    let output = try await processor.split(pdf, pages: pages)
                    try Task.checkCancellation()
                    guard operationID == id else { return }
                    documentOutput = output
                case .photos:
                    let output = try await processor.exportPhotos(pdf, pages: pages) { [weak self] completed, total in
                        await self?.updateProgress(completed: completed, total: total, id: id)
                    }
                    try Task.checkCancellation()
                    guard operationID == id else { return }
                    images = output
                }
            } catch is CancellationError {
            } catch {
                if operationID == id { errorMessage = error.localizedDescription }
            }
        }
    }

    private func updateProgress(completed: Int, total: Int, id: UUID) {
        if operationID == id { progress = "Converting page \(completed) of \(total)…" }
    }

    private func clearOutput() {
        documentOutput = nil
        images = []
        didSave = false
    }

    func savePhotos() async {
        guard !isBusy, !images.isEmpty, !didSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibrarySaver.save(files: images.map(\.url))
            didSave = true
        } catch { errorMessage = error.localizedDescription }
    }

    func cancel() {
        task?.cancel()
        operationID = UUID()
        isWorking = false
    }
}
