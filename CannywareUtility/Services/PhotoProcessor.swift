import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Image decoding and repeated encoding run on this actor, away from the UI.
actor PhotoProcessor {
    func inspect(_ data: Data) throws -> ImportedPhoto {
        let (source, index, width, height) = try readSource(data)
        try Task.checkCancellation()
        let preview = try thumbnail(source, index: index, maxPixel: min(1_200, max(width, height)))
        let type = CGImageSourceGetType(source).map { $0 as String } ?? ""
        let format = UTType(type)?.preferredFilenameExtension?.uppercased() ?? "IMAGE"
        return ImportedPhoto(
            data: data, previewData: try encode(preview, quality: 0.85),
            width: width, height: height, format: format == "JPG" ? "JPEG" : format
        )
    }

    func compress(_ photo: ImportedPhoto, targetBytes: Int) throws -> CompressedPhoto {
        guard TargetSize.allowedBytes.contains(targetBytes) else { throw PhotoError.invalidTarget }
        let (source, index, width, height) = try readSource(photo.data)
        // Avoid growing files that are already below the requested maximum.
        let limit = max(TargetSize.allowedBytes.lowerBound, min(targetBytes, photo.data.count))
        var maxPixel = min(max(width, height), 8_192)

        while true {
            try Task.checkCancellation()
            let pixels = try thumbnail(source, index: index, maxPixel: maxPixel)
            let minimum = try encode(pixels, quality: 0.45)

            if minimum.count <= limit {
                var best = minimum
                var low = 0.45
                var high = 0.96
                // Keep the highest measured quality that fits. Never assume that
                // a requested JPEG quality corresponds to a particular byte size.
                for _ in 0..<9 {
                    try Task.checkCancellation()
                    let quality = (low + high) / 2
                    let candidate = try encode(pixels, quality: quality)
                    if candidate.count <= limit {
                        best = candidate
                        low = quality
                    } else {
                        high = quality
                    }
                }
                guard best.count <= targetBytes else { throw PhotoError.targetUnreachable }
                guard let previewSource = CGImageSourceCreateWithData(best as CFData, nil) else {
                    throw PhotoError.encodingFailed
                }
                let preview = try thumbnail(previewSource, index: 0, maxPixel: min(1_200, max(pixels.width, pixels.height)))
                return CompressedPhoto(
                    data: best, previewData: try encode(preview, quality: 0.88),
                    width: pixels.width, height: pixels.height,
                    originalBytes: photo.data.count, targetBytes: targetBytes
                )
            }

            // Resample from the source each time to avoid cumulative blur. Quality
            // stays at least 45%; dimensions decrease when that quality won't fit.
            guard maxPixel > 1 else {
                throw PhotoError.targetUnreachable
            }
            let scale = min(0.85, max(0.2, sqrt(Double(limit) / Double(minimum.count)) * 0.94))
            maxPixel = max(1, Int(Double(maxPixel) * scale))
        }
    }

    func preparePDFPhoto(_ data: Data) throws -> PDFPhoto {
        let (source, index, width, height) = try readSource(data)
        try Task.checkCancellation()
        let image = try thumbnail(source, index: index, maxPixel: min(3_000, max(width, height)))
        let preview = try thumbnail(source, index: index, maxPixel: min(420, max(width, height)))
        let id = UUID()
        let url = try ExportFiles.folder().appendingPathComponent("Photo-\(id.uuidString).jpg")
        try encode(image, quality: 0.92).write(to: url, options: .atomic)
        return PDFPhoto(id: id, url: url, thumbnail: try encode(preview, quality: 0.75), width: image.width, height: image.height)
    }

    private func readSource(_ data: Data) throws -> (CGImageSource, Int, Int, Int) {
        guard data.count <= 100_000_000 else { throw PhotoError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw PhotoError.invalidImage }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PhotoError.invalidImage }
        guard Double(width) * Double(height) <= 150_000_000 else { throw PhotoError.imageTooLarge }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (source, index, (5...8).contains(orientation) ? height : width,
                (5...8).contains(orientation) ? width : height)
    }

    private func thumbnail(_ source: CGImageSource, index: Int, maxPixel: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PhotoError.invalidImage
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { throw PhotoError.encodingFailed }
        return flattened
    }

    private func encode(_ image: CGImage, quality: Double) throws -> Data {
        try autoreleasepool {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PhotoError.encodingFailed
            }
            // Encode fresh pixels, omitting source EXIF, GPS and other metadata.
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PhotoError.encodingFailed }
            return output as Data
        }
    }
}
