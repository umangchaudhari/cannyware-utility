import Foundation

struct PDFPhoto: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let thumbnail: Data
    let width: Int
    let height: Int
}

struct ImportedPDF: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let title: String
    let pageCount: Int
}

struct DocumentOutput: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let pageCount: Int
}

struct PageImage: Identifiable, Sendable {
    let page: Int
    let url: URL
    let thumbnail: Data
    var id: Int { page }
}

enum DocumentError: LocalizedError {
    case invalidPDF, lockedPDF, restrictedPDF, tooLarge, tooManyPages, invalidPage, emptySelection, exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF: "This PDF couldn't be opened. Choose another file."
        case .lockedPDF: "This PDF is password protected. Choose an unlocked copy."
        case .restrictedPDF: "This PDF does not allow copying its pages. Choose a PDF without copying restrictions."
        case .tooLarge: "Choose a PDF smaller than 100 MB."
        case .tooManyPages: "Choose a PDF with 500 pages or fewer."
        case .invalidPage: "A page in this PDF couldn't be read. Try another PDF."
        case .emptySelection: "Select at least one page."
        case .exportFailed: "The output couldn't be created. Check your device's available storage and try again."
        }
    }
}

enum ExportFiles {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CannywareUtilityExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
