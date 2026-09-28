import SwiftUI
import UIKit

/// Safekeep palette, sampled from the logo. Used regardless of light/dark mode.
enum Theme {
    static let tealTop = Color(hex: 0x145F67)
    static let tealMid = Color(hex: 0x0E4F57)
    static let tealBottom = Color(hex: 0x0B3F47)
    static let tealDeep = Color(hex: 0x07323A)
    static let card = Color(hex: 0x1B6A72).opacity(0.55)
    static let cardStroke = Color(hex: 0x9DBDB2).opacity(0.18)
    static let cream = Color(hex: 0xF8F0E2)
    static let peach = Color(hex: 0xF4C38F)
    static let peachDeep = Color(hex: 0xDBA476)
    static let sage = Color(hex: 0x9DBDB2)
    static let onPeach = Color(hex: 0x0B3F47)
    static let warning = Color(hex: 0xF4C38F)

    static let uiPeach = UIColor(red: 0xF4 / 255, green: 0xC3 / 255, blue: 0x8F / 255, alpha: 1)
    static let uiOnPeach = UIColor(red: 0x0B / 255, green: 0x3F / 255, blue: 0x47 / 255, alpha: 1)

    static var background: some View {
        LinearGradient(colors: [tealTop, tealMid, tealBottom, tealDeep], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Soft, slightly lighter teal card.
struct ThemeCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

extension View {
    func themeCard(padding: CGFloat = 16) -> some View { modifier(ThemeCard(padding: padding)) }
}

/// Peach primary button with dark teal text.
struct PeachButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(.body, .semibold))
            .foregroundStyle(Theme.onPeach)
            .padding(.vertical, 12).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.peach.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// Quiet secondary button: cream text on a faint teal capsule.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(.footnote, .medium))
            .foregroundStyle(Theme.cream)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
    }
}
