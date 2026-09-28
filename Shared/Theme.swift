import SwiftUI
import UIKit

/// Safekeep design system (German's mockup palette). Used everywhere, regardless of light/dark mode.
enum Theme {
    // Named palette
    static let deepPetrol = Color(hex: 0x073B3E)     // background
    static let cardTeal = Color(hex: 0x0D5658)       // cards, background glow
    static let secondaryTeal = Color(hex: 0x147477)  // card borders, secondary buttons
    static let warmIvory = Color(hex: 0xF7F1E8)      // hero card background
    static let softSand = Color(hex: 0xE9C895)       // badges, accents
    static let mutedGold = Color(hex: 0xD9A85F)      // icon circles, step connector, icons
    static let primaryText = Color(hex: 0xFAF8F3)
    static let secondaryText = Color(hex: 0xB8CECB)

    // Roles (older names kept so every screen picks up the palette)
    static let card = cardTeal.opacity(0.72)
    static let cardStroke = secondaryTeal
    static let cream = primaryText
    static let peach = softSand
    static let gold = mutedGold
    static let sage = secondaryText
    static let onPeach = deepPetrol
    static let warning = softSand

    static let uiPeach = UIColor(red: 0xE9 / 255, green: 0xC8 / 255, blue: 0x95 / 255, alpha: 1)
    static let uiOnPeach = UIColor(red: 0x07 / 255, green: 0x3B / 255, blue: 0x3E / 255, alpha: 1)
    static let uiBackground = UIColor(red: 0x07 / 255, green: 0x3B / 255, blue: 0x3E / 255, alpha: 1)

    static let corner: CGFloat = 22

    /// Deep petrol with soft lighter-teal diagonal arcs (mockup).
    static var background: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                deepPetrol
                LinearGradient(colors: [cardTeal.opacity(0.9), deepPetrol.opacity(0.0), cardTeal.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Upper-left arc
                Circle()
                    .fill(RadialGradient(colors: [secondaryTeal.opacity(0.45), cardTeal.opacity(0.0)],
                                         center: .center, startRadius: 0, endRadius: w * 0.75))
                    .frame(width: w * 1.5, height: w * 1.5)
                    .position(x: -w * 0.15, y: -w * 0.35)
                Circle()
                    .stroke(secondaryTeal.opacity(0.25), lineWidth: 1.2)
                    .frame(width: w * 1.25, height: w * 1.25)
                    .position(x: -w * 0.2, y: -w * 0.3)
                // Right-side sweeping arc
                Circle()
                    .fill(cardTeal.opacity(0.45))
                    .frame(width: w * 2.2, height: w * 2.2)
                    .position(x: w * 1.55, y: h * 0.42)
                    .blur(radius: 2)
                Circle()
                    .stroke(secondaryTeal.opacity(0.22), lineWidth: 1.2)
                    .frame(width: w * 2.2, height: w * 2.2)
                    .position(x: w * 1.55, y: h * 0.42)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// SF Pro (system font).
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style).weight(weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Card teal with a thin secondary-teal border.
struct ThemeCard: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

extension View {
    func themeCard(padding: CGFloat = 18) -> some View { modifier(ThemeCard(padding: padding)) }
}

/// Primary: soft sand pill, deep petrol text.
struct PeachButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body).weight(.semibold))
            .foregroundStyle(Theme.onPeach)
            .padding(.vertical, 13).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.softSand.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// Secondary: outlined pill (secondary teal border), primary text.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote).weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.vertical, 8).padding(.horizontal, 13)
            .background(Capsule().fill(Theme.deepPetrol.opacity(configuration.isPressed ? 0.7 : 0.35)))
            .overlay(Capsule().stroke(Theme.secondaryTeal, lineWidth: 1))
    }
}

/// Larger outlined pill with a gold icon (mockup "Choose audio file").
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.vertical, 13).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.deepPetrol.opacity(configuration.isPressed ? 0.7 : 0.35)))
            .overlay(Capsule().stroke(Theme.secondaryTeal, lineWidth: 1))
    }
}

/// Label with a muted-gold icon, for PillButtonStyle.
struct PillLabel: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.mutedGold)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// Soft sand hero card with a warm gradient: petrol circle with an ivory icon, petrol text, chevron.
struct HeroCard: View {
    let title: String
    let subtitle: String
    var icon = "waveform"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.warmIvory)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Theme.deepPetrol))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title3).weight(.semibold)).foregroundStyle(Theme.deepPetrol)
                    Text(subtitle).font(.system(.subheadline)).foregroundStyle(Theme.deepPetrol.opacity(0.82))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.deepPetrol.opacity(0.8))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xF3DDB3), Theme.softSand, Color(hex: 0xE2B97E)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.warmIvory.opacity(0.55), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
    }
}

/// Gold numbered circles joined by a vertical gold line.
struct StepList: View {
    let steps: [(title: String, detail: String?)]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(i + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.deepPetrol)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.mutedGold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.system(.subheadline).weight(.semibold)).foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = s.detail {
                            Text(d).font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .background(alignment: .leading) {
            Rectangle().fill(Theme.mutedGold).frame(width: 2)
                .padding(.vertical, 16)
                .padding(.leading, 14)
        }
    }
}
