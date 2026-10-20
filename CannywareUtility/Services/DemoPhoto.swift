#if DEBUG
import UIKit

/// Deterministic local fixture for simulator UI tests. Never used in release builds.
enum DemoPhoto {
    static func make() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format)
        return renderer.pngData { renderer in
            let context = renderer.cgContext
            let colors = [UIColor(red: 0.64, green: 0.78, blue: 0.83, alpha: 1).cgColor,
                          UIColor(red: 0.92, green: 0.91, blue: 0.81, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1100), options: [])
            context.setFillColor(UIColor(red: 0.97, green: 0.81, blue: 0.48, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: 1120, y: 150, width: 160, height: 160))
            for layer in 0..<5 {
                let path = UIBezierPath()
                let base = 540.0 + Double(layer) * 130
                path.move(to: CGPoint(x: 0, y: 1200))
                for x in stride(from: 0, through: 1600, by: 2) {
                    let y = base + sin(Double(x) / 210 + Double(layer) * 2) * 120
                        + cos(Double(x) / 107 + Double(layer)) * 40
                    path.addLine(to: CGPoint(x: Double(x), y: y))
                }
                path.addLine(to: CGPoint(x: 1600, y: 1200))
                path.close()
                UIColor(red: 0.34 - Double(layer) * 0.045, green: 0.54 - Double(layer) * 0.055,
                        blue: 0.48 - Double(layer) * 0.06, alpha: 1).setFill()
                path.fill()
            }
        }
    }
}
#endif
