import AppKit
import ImageIO
import UniformTypeIdentifiers

// The app and home screen use the same native tools symbol.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 40.0 / 255, green: 85.0 / 255, blue: 68.0 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let config = NSImage.SymbolConfiguration(pointSize: 580, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
    fatalError("Tools symbol is unavailable")
}
let ratio = min(650 / symbol.size.width, 650 / symbol.size.height)
let width = symbol.size.width * ratio
let height = symbol.size.height * ratio
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
symbol.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
