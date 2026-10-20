import XCTest
import ImageIO
import UniformTypeIdentifiers
import UIKit
@testable import CannywareUtility

final class PhotoProcessorTests: XCTestCase {
    private let processor = PhotoProcessor()

    func testTargetSizesAndLocale() throws {
        XCTAssertEqual(try TargetSize(text: "500", unit: .kb).bytes, 500_000)
        XCTAssertEqual(try TargetSize(text: "1.5", unit: .mb, locale: Locale(identifier: "en_US")).bytes, 1_500_000)
        XCTAssertEqual(try TargetSize(text: "0,25", unit: .mb, locale: Locale(identifier: "de_DE")).bytes, 250_000)
        for input in ["", "0", "-100", "9", "nan", "500abc", "20.0.0", "999999999999999999999999"] {
            XCTAssertThrowsError(try TargetSize(text: input, unit: .kb))
        }
        XCTAssertThrowsError(try TargetSize(text: "21", unit: .mb))
    }

    func testOutputNeverExceedsRequestedBytes() async throws {
        let input = noiseImage(width: 1200, height: 900)
        let photo = try await processor.inspect(input)
        for target in [10_000, 100_000, 250_000, 500_000, 1_000_000] {
            let result = try await processor.compress(photo, targetBytes: target)
            XCTAssertLessThanOrEqual(result.data.count, target)
            XCTAssertGreaterThan(result.data.count, 0)
            XCTAssertNotNil(UIImage(data: result.data))
            XCTAssertEqual(result.originalBytes, input.count)
            XCTAssertEqual(Double(result.width) / Double(result.height), 4.0 / 3.0, accuracy: 0.02)
        }
        XCTAssertEqual(photo.data, input, "The source data must remain unchanged")
    }

    func testOrientationAndMetadataAreHandled() async throws {
        let raw = noiseImage(width: 800, height: 400)
        let source = CGImageSourceCreateWithData(raw as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private comment"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let photo = try await processor.inspect(bytes as Data)
        XCTAssertEqual(photo.width, 400)
        XCTAssertEqual(photo.height, 800)
        let result = try await processor.compress(photo, targetBytes: 100_000)
        XCTAssertLessThan(result.width, result.height)
        let output = CGImageSourceCreateWithData(result.data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(output, 0, nil)! as NSDictionary
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
    }

    func testTransparentPNGBecomesWhiteJPEGWithoutUpscaling() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).pngData { _ in }
        let photo = try await processor.inspect(data)
        let result = try await processor.compress(photo, targetBytes: 100_000)
        XCTAssertEqual(result.width, 40)
        XCTAssertEqual(result.height, 30)
        let source = CGImageSourceCreateWithData(result.data as CFData, nil)!
        XCTAssertEqual(CGImageSourceGetType(source)! as String, UTType.jpeg.identifier)
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(pixel.prefix(3).allSatisfy { $0 > 245 })
    }

    func testHEICInput() async throws {
        let source = CGImageSourceCreateWithData(noiseImage(width: 320, height: 240) as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.heic.identifier as CFString, 1, nil) else {
            throw XCTSkip("HEIC encoding is unavailable on this test destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("HEIC encoder unavailable") }
        let photo = try await processor.inspect(bytes as Data)
        let result = try await processor.compress(photo, targetBytes: 20_000)
        XCTAssertLessThanOrEqual(result.data.count, 20_000)
        XCTAssertNotNil(UIImage(data: result.data))
    }

    func testInvalidImageIsRejected() async {
        do {
            _ = try await processor.inspect(Data("not an image".utf8))
            XCTFail("Invalid bytes must be rejected")
        } catch { XCTAssertTrue(error is PhotoError) }
    }

    func testCancellationIsHonored() async throws {
        let photo = try await processor.inspect(noiseImage(width: 600, height: 400))
        let processor = self.processor
        let task = Task { try await processor.compress(photo, targetBytes: 10_000) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func noiseImage(width: Int, height: Int) -> Data {
        var state: UInt64 = 42
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in pixels.indices where index % 4 != 3 {
            state = state &* 6364136223846793005 &+ 1
            pixels[index] = UInt8(truncatingIfNeeded: state >> 32)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image).pngData()!
    }
}
