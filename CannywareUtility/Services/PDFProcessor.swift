import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// PDFKit objects stay on this actor; UI previews open their own document instances.
actor PDFProcessor {
    private var cachedURL: URL?
    private var cachedDocument: PDFDocument?

    func importPDF(from source: URL) throws -> ImportedPDF {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let folder = try ExportFiles.folder()
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                let size = try readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw DocumentError.tooLarge }
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch { copyError = error }
        }
        do {
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
            try Task.checkCancellation()
            let document = try open(destination)
            return ImportedPDF(url: destination, title: source.deletingPathExtension().lastPathComponent, pageCount: document.pageCount)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func thumbnail(_ pdf: ImportedPDF, page index: Int) throws -> Data {
        try Task.checkCancellation()
        let document = try open(pdf.url)
        guard let page = document.page(at: index) else { throw DocumentError.invalidPage }
        return try jpeg(render(page, maxPixel: 420), quality: 0.75)
    }

    func split(_ pdf: ImportedPDF, pages: [Int]) throws -> DocumentOutput {
        let source = try open(pdf.url)
        let indices = try validated(pages, count: source.pageCount)
        let output = PDFDocument()
        for index in indices {
            try Task.checkCancellation()
            guard let page = source.page(at: index)?.copy() as? PDFPage else { throw DocumentError.invalidPage }
            // Copy pages instead of rasterizing, preserving text, rotation, and annotations.
            output.insert(page, at: output.pageCount)
        }
        let folder = try ExportFiles.folder()
        let url = folder.appendingPathComponent("Selected-pages.pdf")
        do {
            guard output.write(to: url) else { throw DocumentError.exportFailed }
            try Task.checkCancellation()
            return DocumentOutput(url: url, pageCount: output.pageCount)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func exportPhotos(_ pdf: ImportedPDF, pages: [Int], progress: @Sendable (Int, Int) async -> Void) async throws -> [PageImage] {
        let document = try open(pdf.url)
        let indices = try validated(pages, count: document.pageCount)
        let folder = try ExportFiles.folder()
        var output: [PageImage] = []
        do {
            for index in indices {
                try Task.checkCancellation()
                let image: PageImage = try autoreleasepool {
                    guard let page = document.page(at: index) else { throw DocumentError.invalidPage }
                    let url = folder.appendingPathComponent(String(format: "Page-%03d.jpg", index + 1))
                    try jpeg(render(page, maxPixel: 2_400), quality: 0.92).write(to: url, options: .atomic)
                    return PageImage(page: index + 1, url: url, thumbnail: try jpeg(render(page, maxPixel: 420), quality: 0.75))
                }
                output.append(image)
                await progress(output.count, indices.count)
            }
            try Task.checkCancellation()
            return output
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func photosToPDF(_ photos: [PDFPhoto]) throws -> DocumentOutput {
        guard !photos.isEmpty else { throw DocumentError.emptySelection }
        let folder = try ExportFiles.folder()
        let url = folder.appendingPathComponent("Photos.pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw DocumentError.exportFailed
        }
        var closed = false
        do {
            for photo in photos {
                try Task.checkCancellation()
                try autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        throw PhotoError.invalidImage
                    }
                    // Match each page to its image: no cropping, stretching, or imposed paper size.
                    var box = CGRect(x: 0, y: 0, width: Double(photo.width) / 2, height: Double(photo.height) / 2)
                    let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                    context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
                    context.draw(image, in: box)
                    context.endPDFPage()
                }
            }
            context.closePDF()
            closed = true
            try Task.checkCancellation()
            guard let check = PDFDocument(url: url), check.pageCount == photos.count else { throw DocumentError.exportFailed }
            return DocumentOutput(url: url, pageCount: photos.count)
        } catch {
            if !closed { context.closePDF() }
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func open(_ url: URL) throws -> PDFDocument {
        if cachedURL == url, let cachedDocument { return cachedDocument }
        guard let document = PDFDocument(url: url) else { throw DocumentError.invalidPDF }
        guard !document.isLocked else { throw DocumentError.lockedPDF }
        guard document.pageCount > 0 else { throw DocumentError.invalidPDF }
        guard document.allowsCopying else { throw DocumentError.restrictedPDF }
        guard document.pageCount <= 500 else { throw DocumentError.tooManyPages }
        cachedURL = url
        cachedDocument = document
        return document
    }

    private func validated(_ pages: [Int], count: Int) throws -> [Int] {
        let sorted = Set(pages).sorted()
        guard !sorted.isEmpty else { throw DocumentError.emptySelection }
        guard sorted.allSatisfy({ (0..<count).contains($0) }) else { throw DocumentError.invalidPage }
        return sorted
    }

    private func render(_ page: PDFPage, maxPixel: Int) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        let rotated = abs(page.rotation % 180) == 90
        let width = rotated ? bounds.height : bounds.width
        let height = rotated ? bounds.width : bounds.height
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw DocumentError.invalidPage }
        let scale = Double(maxPixel) / max(width, height)
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw DocumentError.exportFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        page.displaysAnnotations = true
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw DocumentError.exportFailed }
        return image
    }

    private func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw DocumentError.exportFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DocumentError.exportFailed }
        return data as Data
    }
}
