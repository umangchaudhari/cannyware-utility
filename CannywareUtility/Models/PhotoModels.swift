import Foundation

enum SizeUnit: String, CaseIterable, Identifiable {
    case kb = "KB"
    case mb = "MB"

    var id: String { rawValue }
    var multiplier: Double { self == .kb ? 1_000 : 1_000_000 }
}

struct TargetSize: Equatable, Sendable {
    static let allowedBytes = 10_000...20_000_000
    let bytes: Int

    init(text: String, unit: SizeUnit, locale: Locale = .current) throws {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: separator))
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              trimmed.components(separatedBy: separator).count <= 2,
              let value = formatter.number(from: trimmed)?.doubleValue,
              value.isFinite,
              (Double(Self.allowedBytes.lowerBound)...Double(Self.allowedBytes.upperBound))
                .contains(value * unit.multiplier) else {
            throw PhotoError.invalidTarget
        }
        bytes = Int((value * unit.multiplier).rounded(.down))
    }
}

struct ImportedPhoto: Sendable {
    let data: Data
    let previewData: Data
    let width: Int
    let height: Int
    let format: String

    var dimensions: String { "\(width) × \(height)" }
}

struct CompressedPhoto: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let previewData: Data
    let width: Int
    let height: Int
    let originalBytes: Int
    let targetBytes: Int

    var dimensions: String { "\(width) × \(height)" }
    var savedBytes: Int { max(0, originalBytes - data.count) }
    var savedPercentage: Int {
        guard originalBytes > 0 else { return 0 }
        return Int((Double(savedBytes) / Double(originalBytes) * 100).rounded())
    }
}

enum PhotoError: LocalizedError {
    case invalidImage, imageTooLarge, invalidTarget, encodingFailed, targetUnreachable
    case photoAccessDenied, loadingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "This photo couldn't be opened. Try a JPEG, HEIC, or PNG image."
        case .imageTooLarge: "This image is too large to process safely. Choose a photo under 100 MB and 150 megapixels."
        case .invalidTarget: "Enter a size from 10 KB to 20,000 KB."
        case .encodingFailed: "The photo couldn't be compressed. Please try another image."
        case .targetUnreachable: "This photo couldn't fit the requested size. Try a larger target."
        case .photoAccessDenied: "Allow Cannyware Utility to add photos in Settings, or use Share to save the image to Files."
        case .loadingFailed: "The photo couldn't be loaded. If it's in iCloud, check your connection and try again."
        }
    }
}

enum FileSize {
    static func string(_ bytes: Int) -> String {
        let value = bytes >= 1_000_000 ? Double(bytes) / 1_000_000 : Double(bytes) / 1_000
        let unit = bytes >= 1_000_000 ? "MB" : "KB"
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }
}
