import SwiftUI

enum DesignTokens {
    static let panelWidth: CGFloat = 380
    static let panelRadius: CGFloat = 24
    static let contentInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 18

    static let pearl = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let cyan = Color(red: 0.39, green: 0.78, blue: 0.82)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.68)

    // v0.3.4 targets macOS 26 only. The main panel uses dark native Liquid Glass;
    // these custom colors stay quiet so system reflection/refraction remains visible.
    static let divider = Color.primary.opacity(0.050)
    static let track = Color.primary.opacity(0.060)
    static let glassSheen = Color.white.opacity(0.13)

    static let amber = Color(red: 0.93, green: 0.66, blue: 0.24)
    static let red = Color(red: 0.94, green: 0.35, blue: 0.39)
    static let green = Color(red: 0.45, green: 0.80, blue: 0.54)
    static let sparkline = Color(red: 0.49, green: 0.73, blue: 0.95)

    static let titleFont = Font.system(size: 17, weight: .semibold)
    static let productFont = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let largeNumberFont = Font.system(size: 46, weight: .medium, design: .default)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let smallFont = Font.system(size: 12, weight: .regular)
    static let menuBarFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
}
