// Standalone macOS checks for the shared processing services. Does not launch the iOS app.
import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

@main
struct ProcessingChecks {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "ProcessingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func image(_ color: CGColor, width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try require(CGImageDestinationFinalize(destination), "PNG fixture creation")
        return data as Data
    }

    static func dimensions(_ url: URL) throws -> CGSize {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        return CGSize(width: properties[kCGImagePropertyPixelWidth] as! Int, height: properties[kCGImagePropertyPixelHeight] as! Int)
    }

    static func main() async throws {
        let processor = PDFProcessor()
        let photos = PhotoProcessor()
        let folder = try ExportFiles.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let red = try image(CGColor(red: 1, green: 0, blue: 0, alpha: 1), width: 600, height: 300)
        let blue = try image(CGColor(red: 0, green: 0, blue: 1, alpha: 1), width: 300, height: 600)
        let first = try await photos.preparePDFPhoto(red)
        let second = try await photos.preparePDFPhoto(blue)
        let combined = try await processor.photosToPDF([first, second])
        let imported = try await processor.importPDF(from: combined.url)
        try require(imported.pageCount == 2, "Photos to PDF page count")
        let document = PDFDocument(url: combined.url)!
        try require(document.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 300, height: 150), "Landscape image page aspect")
        try require(document.page(at: 1)!.bounds(for: .mediaBox).size == CGSize(width: 150, height: 300), "Portrait image page aspect")

        let split = try await processor.split(imported, pages: [1])
        let splitDocument = PDFDocument(url: split.url)!
        try require(splitDocument.pageCount == 1, "Selected page count")
        try require(splitDocument.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 150, height: 300), "Correct page extracted")
        let sorted = try await processor.split(imported, pages: [1, 0, 1])
        let sortedDocument = PDFDocument(url: sorted.url)!
        try require(sortedDocument.pageCount == 2, "Duplicate selections removed")
        try require(sortedDocument.page(at: 0)!.bounds(for: .mediaBox).width == 300, "Original page order retained")

        let exported = try await processor.exportPhotos(imported, pages: [0, 1]) { _, _ in }
        try require(exported.count == 2, "PDF to photos count")
        try require(try dimensions(exported[0].url) == CGSize(width: 2400, height: 1200), "Landscape JPEG dimensions")
        try require(try dimensions(exported[1].url) == CGSize(width: 1200, height: 2400), "Portrait JPEG dimensions")

        // A crop with nonzero origin and a 90° rotation exercises PDF page transforms.
        let rotatedURL = folder.appendingPathComponent("rotated.pdf")
        let rotatedPage = document.page(at: 0)!
        rotatedPage.rotation = 90
        rotatedPage.setBounds(CGRect(x: 20, y: 10, width: 200, height: 100), for: .cropBox)
        let annotation = PDFAnnotation(bounds: CGRect(x: 30, y: 20, width: 60, height: 30), forType: .square, withProperties: nil)
        annotation.color = .green
        annotation.interiorColor = .green
        rotatedPage.addAnnotation(annotation)
        try require(document.write(to: rotatedURL), "Rotated fixture write")
        let rotated = try await processor.importPDF(from: rotatedURL)
        let rotatedImages = try await processor.exportPhotos(rotated, pages: [0]) { _, _ in }
        try require(try dimensions(rotatedImages[0].url) == CGSize(width: 1200, height: 2400), "Rotated crop dimensions")
        let copied = try await processor.split(rotated, pages: [0])
        let copiedPage = PDFDocument(url: copied.url)!.page(at: 0)!
        try require(copiedPage.rotation == 90 && copiedPage.annotations.count == 1, "Rotation and annotations retained")

        // Verify that the renderer did not produce an empty white page.
        let source = CGImageSourceCreateWithURL(rotatedImages[0].url as CFURL, nil)!
        let rendered = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let sample = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sample.draw(rendered, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = sample.data!.assumingMemoryBound(to: UInt8.self)
        try require(pixel[2] < 100, "Rotated page rendered with its colored content")

        do {
            _ = try await processor.split(imported, pages: [])
            throw NSError(domain: "ProcessingChecks", code: 2)
        } catch DocumentError.emptySelection {}
        do {
            _ = try await processor.split(imported, pages: [4])
            throw NSError(domain: "ProcessingChecks", code: 3)
        } catch DocumentError.invalidPage {}
        let invalid = folder.appendingPathComponent("invalid.pdf")
        try Data("not a pdf".utf8).write(to: invalid)
        do {
            _ = try await processor.importPDF(from: invalid)
            throw NSError(domain: "ProcessingChecks", code: 4)
        } catch DocumentError.invalidPDF {}

        let lockedURL = folder.appendingPathComponent("locked.pdf")
        try require(document.write(to: lockedURL, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "secret"]), "Encrypted fixture write")
        do {
            _ = try await processor.importPDF(from: lockedURL)
            throw NSError(domain: "ProcessingChecks", code: 6)
        } catch DocumentError.lockedPDF {}
        let oversized = folder.appendingPathComponent("oversized.pdf")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 100_000_001)
        try handle.close()
        do {
            _ = try await processor.importPDF(from: oversized)
            throw NSError(domain: "ProcessingChecks", code: 7)
        } catch DocumentError.tooLarge {}
        let longDocument = PDFDocument()
        for _ in 0..<501 { longDocument.insert(document.page(at: 1)!.copy() as! PDFPage, at: longDocument.pageCount) }
        let longURL = folder.appendingPathComponent("too-many-pages.pdf")
        try require(longDocument.write(to: longURL), "Long fixture write")
        do {
            _ = try await processor.importPDF(from: longURL)
            throw NSError(domain: "ProcessingChecks", code: 8)
        } catch DocumentError.tooManyPages {}

        // Recheck the compressor's upper bound after the shared photo service changes.
        let importedPhoto = try await photos.inspect(red)
        for size in [100_000, 200_000, 250_000, 500_000, 1_000_000] {
            let result = try await photos.compress(importedPhoto, targetBytes: size)
            try require(result.data.count <= size, "Compression limit \(size)")
        }
        let cancelled = Task {
            try Task.checkCancellation()
            return try await processor.exportPhotos(imported, pages: [0, 1]) { _, _ in }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw NSError(domain: "ProcessingChecks", code: 5) }
        catch is CancellationError {}
        print("PASS: photos-to-PDF, page ordering/selection, rotated crops, annotations, JPEG export, invalid/locked/oversized inputs, page-count limits, cancellation, and compression limits.")
        print("Rotation preview fixture: \(rotatedImages[0].url.path)")
    }
}
