import SwiftUI

enum CannywareTheme {
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let ink = Color.primary
    static let forest = Color("AccentColor")
    static let mint = Color("Mint")
    static let line = Color.primary.opacity(0.09)
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .background(CannywareTheme.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(CannywareTheme.line, lineWidth: 1))
    }
}

struct StepLabel: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(CannywareTheme.forest)
                .frame(width: 25, height: 25)
                .background(CannywareTheme.mint, in: Circle())
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(isEnabled ? Color("OnAccent") : Color.secondary)
            .background(isEnabled ? CannywareTheme.forest : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(CannywareTheme.paper, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct CannywareBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color("OnAccent"))
                .frame(width: 40, height: 40)
                .background(CannywareTheme.forest, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 0) {
                Text("Cannyware").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Utility").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
        .accessibilityLabel("Cannyware Utility")
    }
}

